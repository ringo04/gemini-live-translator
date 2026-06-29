import Foundation
import AVFoundation
import Combine


// MARK: - GeminiLiveTranslator
class GeminiLiveTranslator: NSObject, ObservableObject {
    
    @Published var isConnected    = false
    @Published var isRecording    = false
    @Published var isConnecting   = false
    @Published var isStopping     = false
    @Published var originalText   = ""
    @Published var translatedText = ""
    @Published var errorStatus: String? = nil
    @Published var microphoneLevel: Float = 0.0
    
    @Published var isAudioPlaybackEnabled = true {
        didSet {
            if !isAudioPlaybackEnabled {
                audioQueue.async { [weak self] in
                    guard let self else { return }
                    self.audioBufferQueue.removeAll()
                    self.isPlayingQueue = false
                    self.activeScheduledBuffersCount = 0
                    self.outputPlayerNode.stop()
                }
            }
        }
    }
    
    private var apiKey: String
    private var targetLanguage: Locale.Language
    private let modelName = "gemini-3.5-live-translate-preview"
    private var currentApiVersion = "v1beta"
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    
    private var audioEngine: AVAudioEngine? = nil
    private var isAudioOutputSetup = false
    private lazy var outputPlayerNode = AVAudioPlayerNode()
    private var outputFormat: AVAudioFormat?
    
    private var audioBufferQueue: [Data] = []
    private let minQueueSizeToStartPlay = 3
    private var isPlayingQueue = false
    private var activeScheduledBuffersCount = 0
    private let audioQueue = DispatchQueue(label: "com.translator.audioQueue", qos: .userInteractive)
    
    private var sendBufferAccumulator = Data()
    private let maxSendBufferSize = 3200 // 16kHz × 2bytes × 100ms = 3200 bytes
    private let bufferLock = NSLock()
    private var audioConverter: AVAudioConverter?
    
    private var reconnectCount = 0
    private let maxReconnectAttempts = 5
    private var isExplicitDisconnect = false
    private var hasConnectedOnce = false
    private var isFatalErrorEncountered = false
    
    private let keywordExtractor: KeywordExtractor
    private var lastExtractedText = ""
    private var isWaitingToMuteSession = false
    private var lastMicrophoneLevelUpdateTime = Date.distantPast
    
    init(apiKey: String, targetLanguage: Locale.Language, keywordExtractor: KeywordExtractor) {
        self.apiKey = apiKey
        self.targetLanguage = targetLanguage
        self.keywordExtractor = keywordExtractor
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        print("[Translator] init completed")
    }
    
    func connect() {
        guard !isConnected else { return }
        isExplicitDisconnect = false
        hasConnectedOnce = false
        isFatalErrorEncountered = false
        errorStatus = nil
        
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            errorStatus = "API Keyが設定されていません。API Keyを入力してください。"
            return
        }
        
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.\(currentApiVersion).GenerativeService.BidiGenerateContent?key=\(cleanKey)"
        guard let url = URL(string: urlString) else {
            errorStatus = "Invalid WebSocket URL"
            return
        }
        
        print("[Translator] Connecting (\(currentApiVersion))")
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }
    
    func disconnect() {
        isExplicitDisconnect = true
        cleanupConnection()
    }
    
    func updateConfig(apiKey: String, targetLanguage: Locale.Language, apiVersion: String) {
        if isConnected || isConnecting { disconnect() }
        self.apiKey = apiKey
        self.targetLanguage = targetLanguage
        self.currentApiVersion = apiVersion
    }
    
    func startRecording() {
        guard isConnected else { return }
        isWaitingToMuteSession = false
        
        if audioEngine == nil {
            audioEngine = AVAudioEngine()
            isAudioOutputSetup = false
        }
        if audioEngine?.isRunning == true { audioEngine?.stop() }
        guard let engine = audioEngine else { return }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredSampleRate(48000.0)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorStatus = "Audio Session error: \(error.localizedDescription)"
            return
        }
        
        engine.reset()
        setupAudioOutput()
        
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        let hwFormat = inputNode.inputFormat(forBus: 0)
        
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false) else { return }
        
        bufferLock.lock()
        audioConverter = nil
        sendBufferAccumulator = Data()
        bufferLock.unlock()
        
        inputNode.installTap(onBus: 0, bufferSize: 4800, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            
            self.bufferLock.lock()
            if self.audioConverter == nil {
                self.audioConverter = AVAudioConverter(from: buffer.format, to: targetFormat)
            }
            let converter = self.audioConverter
            self.bufferLock.unlock()
            
            guard let converter else { return }
            
            let inputCallback: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(targetFormat.sampleRate * 0.1)
            ) else { return }
            
            var convError: NSError?
            converter.convert(to: converted, error: &convError, withInputFrom: inputCallback)
            if let convError { print("Converter error: \(convError)"); return }
            
            guard let channelData = converted.int16ChannelData else { return }
            let frames = Int(converted.frameLength)
            let data = Data(bytes: channelData[0], count: frames * 2)
            
            var sum: Float = 0
            for i in 0..<frames {
                let s = Float(channelData[0][i]) / 32768.0
                sum += s * s
            }
            let rms = sqrt(sum / Float(frames))
            
            let now = Date()
            if now.timeIntervalSince(self.lastMicrophoneLevelUpdateTime) >= 0.3 {
                self.lastMicrophoneLevelUpdateTime = now
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.microphoneLevel = self.microphoneLevel * 0.4 + min(rms * 5.0, 1.0) * 0.6 * 100
                }
            }
            
            self.bufferLock.lock()
            self.sendBufferAccumulator.append(data)
            var chunkToSend: Data? = nil
            if self.sendBufferAccumulator.count >= self.maxSendBufferSize {
                chunkToSend = self.sendBufferAccumulator
                self.sendBufferAccumulator = Data()
            }
            self.bufferLock.unlock()
            
            if let chunk = chunkToSend {
                self.sendAudioChunk(chunk)
            }
        }
        
        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            errorStatus = nil
            print("[Translator] Recording started")
        } catch {
            errorStatus = "Audio Engine error: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        print("[Translator] Stopping recording")
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            isRecording = false
            microphoneLevel = 0.0
        }
        
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.isWaitingToMuteSession = false
            self.isPlayingQueue = false
            self.activeScheduledBuffersCount = 0
            self.audioBufferQueue.removeAll()
            self.outputPlayerNode.stop()
            self.audioEngine?.stop()
            self.audioEngine = nil
            self.deactivateRecordingCategory()
        }
        
        bufferLock.lock()
        audioConverter = nil
        sendBufferAccumulator = Data()
        bufferLock.unlock()
    }
    
    private func cleanupConnection() {
        stopRecording()
        audioEngine?.stop()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.audioBufferQueue.removeAll()
            self.isPlayingQueue = false
            self.activeScheduledBuffersCount = 0
        }
        
        outputPlayerNode.stop()
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            isConnected  = false
            isConnecting = false
            microphoneLevel = 0.0
        }
        
        bufferLock.lock()
        audioConverter = nil
        sendBufferAccumulator = Data()
        bufferLock.unlock()
    }
    
    private func handleDisconnect(error: Error?, isFatal: Bool = false) {
        if isFatal {
            self.isFatalErrorEncountered = true
        }
        guard !isExplicitDisconnect, !isStopping else { return }
        stopRecording()
        
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.audioBufferQueue.removeAll()
            self.isPlayingQueue = false
            self.activeScheduledBuffersCount = 0
        }
        outputPlayerNode.stop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            isConnected = false
            microphoneLevel = 0.0
            
            guard hasConnectedOnce, !isFatalErrorEncountered else {
                let defaultMsg = isFatalErrorEncountered
                ? "API Keyが無効です。設定から有効なキーを入力してください。"
                : "接続できませんでした。API Keyが無効であるか、ネットワークに接続されていません。"
                if errorStatus == nil || isFatalErrorEncountered {
                    errorStatus = error?.localizedDescription ?? defaultMsg
                }
                isConnecting = false
                return
            }
            
            if reconnectCount < maxReconnectAttempts {
                reconnectCount += 1
                let delay = Double(reconnectCount) * 2.0
                errorStatus = "接続が中断されました。\(Int(delay))秒後に再接続します (\(reconnectCount)/\(maxReconnectAttempts))"
                
                try? await Task.sleep(for: .seconds(delay))
                
                guard !isExplicitDisconnect, !isStopping else { return }
                connect()
            } else {
                errorStatus = "接続エラー: \(error?.localizedDescription ?? "不明なエラー")"
            }
        }
    }
    
    // MARK: - Private: Messaging
    private func sendSetupMessage() {
        let setup = LiveSetupMessage(
            setup: SetupData(
                model: "models/\(modelName)",
                generationConfig: GenerationConfig(
                    responseModalities: ["AUDIO"],
                    translationConfig: TranslationConfig(
                        targetLanguageCode: targetLanguage.languageCode ?? .japanese,
                        echoTargetLanguage: false
                    )
                ),
                inputAudioTranscription:  AudioTranscriptionConfig(),
                outputAudioTranscription: AudioTranscriptionConfig()
            )
        )
        guard
            let data = try? JSONEncoder().encode(setup),
            let json = String(data: data, encoding: .utf8)
        else { return }
        sendTextMessage(json)
    }
    
    private func sendTextMessage(_ text: String) {
        webSocketTask?.send(.string(text)) { error in
            if let error { print("[Translator] Send error: \(error)") }
        }
    }
    
    private func sendAudioChunk(_ chunk: Data) {
        let message = LiveRealtimeInputMessage(
            realtimeInput: RealtimeInputData(
                mediaChunks: [MediaChunk(mimeType: "audio/pcm;rate=16000", data: chunk.base64EncodedString())]
            )
        )
        guard
            let data = try? JSONEncoder().encode(message),
            let json = String(data: data, encoding: .utf8)
        else { return }
        sendTextMessage(json)
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                print("[Translator] Receive error: \(error)")
                let errorDesc = error.localizedDescription
                let isApiKeyInvalid = errorDesc.contains("API key not valid") || errorDesc.contains("403")
                self.handleDisconnect(error: error, isFatal: isApiKeyInvalid)
            case .success(let message):
                let text: String? = switch message {
                case .string(let s): s
                case .data(let d): String(data: d, encoding: .utf8)
                @unknown default: nil
                }
                if let text { self.handleServerResponse(text) }
                if self.isConnected { self.receiveMessage() }
            }
        }
    }
    
    private func handleServerResponse(_ json: String) {
        guard
            let data = json.data(using: .utf8),
            let response = try? JSONDecoder().decode(LiveServerResponse.self, from: data)
        else { return }
        Task { @MainActor [weak self] in
            guard let self, isConnected else { return }
            
            hasConnectedOnce = true
            
            guard let content = response.serverContent else { return }
            
            if let text = content.inputTranscription?.text {
                originalText = text
                triggerKeywordExtraction(text: text)
            }
            
            if let text = content.outputTranscription?.text {
                translatedText = text
            }
            
            if let parts = content.modelTurn?.parts {
                for part in parts {
                    if let b64 = part.inlineData?.data,
                       let audioData = Data(base64Encoded: b64) {
                        queueAudioChunk(audioData)
                    }
                }
            }
        }
    }
    
    @MainActor
    private func triggerKeywordExtraction(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 5, trimmed != lastExtractedText else { return }
        
        let newSegment: String
        if trimmed.hasPrefix(lastExtractedText) {
            newSegment = String(trimmed.suffix(trimmed.count - lastExtractedText.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            newSegment = trimmed
        }
        
        guard !newSegment.isEmpty else { return }
        
        let endsWithPunct = newSegment.hasSuffix(".") || newSegment.hasSuffix("?") || newSegment.hasSuffix("!") || newSegment.hasSuffix("。") || newSegment.hasSuffix("？") || newSegment.hasSuffix("！")
        let bigUpdate = newSegment.count > 50
        
        if endsWithPunct || bigUpdate {
            keywordExtractor.addTranscriptText(trimmed, newSegment: newSegment)
            lastExtractedText = trimmed
        }
    }
    
    private func setupAudioOutput() {
        guard !isAudioOutputSetup, let engine = audioEngine else { return }
        
        let session = AVAudioSession.sharedInstance()
        if session.category == .ambient || session.category == .soloAmbient {
            try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try? session.setActive(true, options: .notifyOthersOnDeactivation)
        }
        
        outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)
        engine.attach(outputPlayerNode)
        engine.connect(outputPlayerNode, to: engine.mainMixerNode, format: outputFormat)
        isAudioOutputSetup = true
        print("[Translator] Audio output setup done")
    }
    
    private func queueAudioChunk(_ data: Data) {
        guard isAudioPlaybackEnabled else { return }
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.audioBufferQueue.append(data)
            if self.isPlayingQueue {
                self.schedulePendingBuffers()
            } else if self.audioBufferQueue.count >= self.minQueueSizeToStartPlay {
                self.isPlayingQueue = true
                self.schedulePendingBuffers()
            }
        }
    }
    
    private func schedulePendingBuffers() {
        guard let engine = self.audioEngine else { return }
        
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[Translator] Engine start error: \(error)")
                self.isPlayingQueue = false
                return
            }
        }
        
        guard let fmt = self.outputFormat else { return }
        
        while !audioBufferQueue.isEmpty {
            let chunk = audioBufferQueue.removeFirst()
            let frameCount = AVAudioFrameCount(chunk.count / 2)
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else {
                continue
            }
            pcmBuffer.frameLength = frameCount
            chunk.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress,
                   let ch = pcmBuffer.int16ChannelData {
                    ch[0].initialize(from: base.assumingMemoryBound(to: Int16.self), count: Int(frameCount))
                }
            }
            
            if !self.outputPlayerNode.isPlaying {
                self.outputPlayerNode.play()
            }
            
            self.activeScheduledBuffersCount += 1
            self.outputPlayerNode.scheduleBuffer(pcmBuffer, at: nil, options: []) { [weak self] in
                guard let self else { return }
                self.audioQueue.async {
                    self.handleBufferCompletion()
                }
            }
        }
    }
    
    private func handleBufferCompletion() {
        activeScheduledBuffersCount -= 1
        if activeScheduledBuffersCount <= 0 {
            activeScheduledBuffersCount = 0
            isPlayingQueue = false
            
            if self.outputPlayerNode.isPlaying {
                self.outputPlayerNode.stop()
            }
            
            if self.isWaitingToMuteSession {
                self.audioEngine?.stop()
                self.deactivateRecordingCategory()
            }
        }
    }
    
    private func deactivateRecordingCategory() {
        guard !isRecording else { isWaitingToMuteSession = false; return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            print("[Translator] Audio session deactivated")
        } catch {
            print("[Translator] Session deactivation error: \(error)")
        }
        isWaitingToMuteSession = false
    }
}


// MARK: - URLSessionWebSocketDelegate
extension GeminiLiveTranslator: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("[Translator] WebSocket opened (\(currentApiVersion))")
        Task { @MainActor [weak self] in
            guard let self else { return }
            isConnected    = true
            reconnectCount = 0
            errorStatus    = nil
            
            try? await Task.sleep(for: .seconds(0.2))
            sendSetupMessage()
        }
    }
    
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        print("[Translator] WebSocket closed: \(closeCode.rawValue), \(reasonStr)")
        
        let isApiKeyInvalid = closeCode.rawValue == 1007 || reasonStr.contains("API key not valid")
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            if isApiKeyInvalid {
                isFatalErrorEncountered = true
                errorStatus = "API Keyが無効です。設定から有効なキーを入力してください。"
            } else {
                let reasonSuffix = reasonStr.isEmpty ? "" : " (原因: \(reasonStr))"
                errorStatus = "切断されました (Code: \(closeCode.rawValue)\(reasonSuffix))"
            }
        }
        handleDisconnect(error: nil, isFatal: isApiKeyInvalid)
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            print("[Translator] Task error: \(error)")
            let errorDesc = error.localizedDescription
            let isApiKeyInvalid = errorDesc.contains("API key not valid") || errorDesc.contains("403")
            handleDisconnect(error: error, isFatal: isApiKeyInvalid)
        }
    }
}
