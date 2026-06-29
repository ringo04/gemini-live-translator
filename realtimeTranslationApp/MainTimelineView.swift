import SwiftUI
import SwiftData
import NaturalLanguage


// MARK: - MainTimelineView
struct MainTimelineView: View {
    @Binding var apiKey: String
    
    @ObservedObject var translator: GeminiLiveTranslator
    @ObservedObject var keywordExtractor: KeywordExtractor
    
    @Binding var targetLanguage: Locale.Language
    
    @State private var displayState = TranslationDisplayState()
    @State private var currentID: UUID?
    @State private var pillScrollID: UUID?
    
    @State private var isCardsExpanded: Bool = false
    @State private var isGroupExpanded: Bool = true
    @State private var isShowingSavedContentSheet: Bool = false
    @State private var isShowingSettingSheet: Bool = false
    @State private var isVariableColorActive: Bool = false
    
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    var onUnlockAPIKey: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - Timeline & Current Transcription
            TimelineSectionView(
                translator: translator,
                keywordExtractor: keywordExtractor,
                displayState: $displayState,
                targetLanguage: $targetLanguage
            )
            .padding(.bottom)
            .frame(maxHeight: .infinity)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "explain" {
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                        let word = components.host ?? ""
                        let context = components.queryItems?.first(where: { $0.name == "context" })?.value ?? ""
                        
                        let trimmedLower = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if let existing = keywordExtractor.explanations.first(where: { $0.word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == trimmedLower }) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isGroupExpanded = true
                            }
                            
                            Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    currentID = existing.id
                                    pillScrollID = existing.id
                                }
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isGroupExpanded = true
                                keywordExtractor.explainWord(word, context: context)
                            }
                        }
                    }
                    return .handled
                }
                return .systemAction
            })
            
            // MARK: - Keyword Explanations (New Carousel UI)
            ExplanationsSection(
                keywordExtractor: keywordExtractor,
                currentID: $currentID,
                pillScrollID: $pillScrollID,
                isCardsExpanded: $isCardsExpanded,
                isGroupExpanded: $isGroupExpanded
            )
            
            Spacer()
            
            ControlButtonView(
                translator: translator,
                displayState: $displayState,
                targetLanguage: $targetLanguage,
                isVariableColorActive: $isVariableColorActive
            )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("翻訳タイムライン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    isShowingSavedContentSheet = true
                }) {
                    Image(systemName: "list.star")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    isShowingSettingSheet = true
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isShowingSavedContentSheet) {
            SavedContentSheet()
        }
        .sheet(isPresented: $isShowingSettingSheet) {
            SettingSheet(apiKey: $apiKey, keywordExtractor: keywordExtractor)
        }
        .onChange(of: apiKey) { _, _ in
            displayState = TranslationDisplayState()
        }
        .onChange(of: targetLanguage) { _, _ in
            displayState = TranslationDisplayState()
        }
        .onChange(of: translator.originalText) { _, newText in
            handleTextSync(newText: newText, isOriginal: true)
        }
        .onChange(of: translator.translatedText) { _, newText in
            handleTextSync(newText: newText, isOriginal: false)
        }
        .onChange(of: translator.isConnecting) { _, _ in
            handleVariableColorSync()
        }
        .onChange(of: translator.isStopping) { _, _ in
            handleVariableColorSync()
        }
        .onChange(of: keywordExtractor.explanations) { old, new in
            guard old.count < new.count, let newLast = new.last else { return }
            let oldLast = old.last
            let oldSecondLast = old.count >= 2 ? old[old.count - 2] : nil
            
            let isLookingAtOldLast: Bool = currentID == oldLast?.id
            let isLookingAtOldSecondLast: Bool = sizeClass == .regular && currentID == oldSecondLast?.id
            let isLookingAtEnd: Bool = isLookingAtOldLast || isLookingAtOldSecondLast
            
            if oldLast == nil || isLookingAtEnd || currentID == newLast.id {
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        currentID = newLast.id
                        pillScrollID = newLast.id
                    }
                }
            }
        }
        .onChange(of: currentID) { _, newID in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                pillScrollID = newID
            }
        }
    }
    
    private func hasSentenceEnd(_ text: String) -> Bool {
        ["。", "？", ".", "?", "！", "!"]
            .contains(where: text.hasSuffix)
    }
    
    private func handleTextSync(newText: String, isOriginal: Bool) {
        let cleanNew = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNew.isEmpty else { return }
        
        if isOriginal {
            let cleanCurrent = displayState.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanCurrent.isEmpty && !cleanNew.hasPrefix(cleanCurrent) {
                displayState.accumulatedOriginal += (displayState.accumulatedOriginal.isEmpty ? "" : " ") + displayState.currentOriginalText
                let total = displayState.accumulatedOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
                if hasSentenceEnd(total) || total.count >= 150 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        displayState.originalMessages.append(TextSegment(text: total))
                        displayState.accumulatedOriginal = ""
                    }
                }
                displayState.currentOriginalText = ""
            }
            displayState.currentOriginalText = newText
        } else {
            let cleanCurrent = displayState.currentTranslatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanCurrent.isEmpty && !cleanNew.hasPrefix(cleanCurrent) {
                displayState.accumulatedTranslated += (displayState.accumulatedTranslated.isEmpty ? "" : " ") + displayState.currentTranslatedText
                let total = displayState.accumulatedTranslated.trimmingCharacters(in: .whitespacesAndNewlines)
                if hasSentenceEnd(total) || total.count >= 150 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        displayState.translatedMessages.append(TextSegment(text: total))
                        displayState.accumulatedTranslated = ""
                    }
                }
                displayState.currentTranslatedText = ""
            }
            displayState.currentTranslatedText = newText
        }
    }
    
    private func handleVariableColorSync() {
        if translator.isConnecting {
            self.isVariableColorActive = true
        } else if translator.isStopping {
            Task {
                try? await Task.sleep(for: .seconds(0.3))
                if translator.isStopping {
                    isVariableColorActive = true
                }
            }
        } else {
            self.isVariableColorActive = false
        }
    }
}


// MARK: - TimelineSectionView
struct TimelineSectionView: View {
    @ObservedObject var translator: GeminiLiveTranslator
    @ObservedObject var keywordExtractor: KeywordExtractor
    @Binding var displayState: TranslationDisplayState
    @Binding var targetLanguage: Locale.Language
    
    @State private var originalScrollPosition = ScrollPosition(edge: .bottom)
    @State private var translatedScrollPosition = ScrollPosition(edge: .bottom)
    
    var body: some View {
        let originalDisplay = displayState.accumulatedOriginal + displayState.currentOriginalText
        let translatedDisplay = displayState.accumulatedTranslated + displayState.currentTranslatedText
        let explainedSet = Set(keywordExtractor.explanations.map { $0.word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                
                Text("リアルタイム翻訳")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(translator.isConnected ? Color.pink : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(translator.isConnected ? "接続中" : "未接続")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
            
            ZStack {
                HStack(spacing: 10) {
                    TranscriptionColumnView(
                        messages: displayState.originalMessages,
                        currentDisplay: originalDisplay,
                        emptyPlaceholder: "入力を待っています...",
                        backgroundColor: Color(.secondarySystemGroupedBackground),
                        loadingWord: keywordExtractor.loadingWord,
                        explainedWords: explainedSet
                    ) {
                        HStack {
                            Label("入力", systemImage: "mic.fill")
                                .foregroundColor(.secondary)
                                .font(.caption.bold())
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    }
                    
                    TranscriptionColumnView(
                        messages: displayState.translatedMessages,
                        currentDisplay: translatedDisplay,
                        emptyPlaceholder: "翻訳を待っています...",
                        backgroundColor: Color.pink.opacity(0.08),
                        loadingWord: keywordExtractor.loadingWord,
                        explainedWords: explainedSet
                    ) {
                        HStack {
                            LanguagePickerView(targetLanguage: $targetLanguage)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        .font(.subheadline.weight(.semibold))
                    }
                }
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .clipShape(.circle)
                    .glassEffect(.clear)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: translator.isConnected)
    }
}


struct TranscriptionColumnView<Header: View>: View {
    let messages: [TextSegment]
    let currentDisplay: String
    let emptyPlaceholder: String
    let backgroundColor: Color
    let loadingWord: String?
    let explainedWords: Set<String>
    
    @ViewBuilder let header: () -> Header
    
    @State private var isAtBottom = true
    
    private let bottomAnchorID = "bottomAnchor"
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { segment in
                        Text(
                            AttributedString.makeInteractiveText(
                                segment.text,
                                context: segment.text,
                                foregroundColor: .secondary,
                                loadingWord: loadingWord,
                                explainedWords: explainedWords
                            )
                        )
                        .font(.footnote)
                        .lineSpacing(4)
                    }
                    
                    Group {
                        if !currentDisplay.isEmpty {
                            Text(
                                AttributedString.makeInteractiveText(
                                    currentDisplay,
                                    context: currentDisplay,
                                    foregroundColor: .primary,
                                    loadingWord: loadingWord,
                                    explainedWords: explainedWords
                                )
                            )
                            .font(.footnote.weight(.bold))
                            .lineSpacing(4)
                        } else if messages.isEmpty {
                            Text(emptyPlaceholder)
                                .foregroundStyle(.gray)
                                .font(.footnote)
                        }
                    }
                    .transaction { $0.animation = nil }
                    
                    Color.clear.frame(height: 20)
                    
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .onScrollGeometryChange(
                for: Bool.self
            ) { geometry in
                let distanceFromBottom =
                geometry.contentSize.height
                - geometry.visibleRect.maxY
                
                return distanceFromBottom < 150
            } action: { _, newValue in
                isAtBottom = newValue
            }
            .onChange(of: currentDisplay) { _, _ in
                scrollToBottomIfNeeded(proxy)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottomIfNeeded(proxy)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) {
                header()
            }
            .background {
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    backgroundColor
                }
            }
            .clipShape(.rect(corners: .concentric(minimum: 16), isUniform: true))
            .onAppear {
                proxy.scrollTo(
                    bottomAnchorID,
                    anchor: .bottom
                )
            }
        }
    }
    
    private func scrollToBottomIfNeeded(
        _ proxy: ScrollViewProxy
    ) {
        guard isAtBottom else { return }
        
        Task {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                proxy.scrollTo(
                    bottomAnchorID,
                    anchor: .bottom
                )
            }
        }
    }
}


struct LanguagePickerView: View {
    @Binding var targetLanguage: Locale.Language
    
    let mainLanguages: [Locale.LanguageCode] = [.japanese, .english, .korean, .chinese, .cantonese, .spanish, .german, .portuguese]
    
    
    var body: some View {
        let selectionBinding = Binding<Locale.LanguageCode>(
            get: { targetLanguage.languageCode ?? .japanese },
            set: { targetLanguage = Locale.Language(components: .init(languageCode: $0)) }
        )
        Menu {
            Picker("言語を選択", selection: selectionBinding) {
                
                ForEach(mainLanguages, id: \.self) { code in
                    Text(code.localizedName).tag(code)
                }
            }
            .labelsHidden()
        } label: {
            HStack {
                Label(selectionBinding.wrappedValue.localizedName, systemImage: "translate")
                    .foregroundColor(.pink)
                    .font(.caption)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundColor(.pink.opacity(0.5))
                    .font(.caption2)
            }
            .bold()
        }
    }
}

// MARK: - ControlButtonView
struct ControlButtonView: View {
    @Environment(\.modelContext) private var modelContext
    
    @ObservedObject var translator: GeminiLiveTranslator
    
    @Binding var displayState: TranslationDisplayState
    @Binding var targetLanguage: Locale.Language
    @Binding var isVariableColorActive: Bool
    
    @State private var previousLevel: Float = 0.0
    @State private var ripples: [UUID] = []
    @State private var lastRippleTime = Date.distantPast
    
    var body: some View {
        ZStack {
            
            HStack(spacing: 140) {
                if translator.isConnected {
                    Button(action: {
                        translator.isAudioPlaybackEnabled.toggle()
                    }) {
                        Image(systemName: translator.isAudioPlaybackEnabled ? "speaker.fill" : "speaker.slash.fill" )
                            .contentTransition(.symbolEffect)
                            .font(.system(size: 20))
                            .foregroundStyle(translator.isAudioPlaybackEnabled ? .primary : Color(.systemBackground))
                            .frame(width: 60, height: 60)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(translator.isAudioPlaybackEnabled ? Color(.secondarySystemGroupedBackground) : .primary.opacity(0.8))
                }
                
                if translator.isConnected {
                    Button(action: {
                        if translator.isRecording {
                            translator.stopRecording()
                        } else {
                            translator.startRecording()
                        }
                    }) {
                        Image(systemName: translator.isRecording ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 20))
                            .frame(width: 60, height: 60)
                            .foregroundStyle(translator.isRecording ? .primary : Color(.systemBackground))
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(!translator.isRecording ? .primary.opacity(0.8) : Color(.secondarySystemGroupedBackground))
                    .glassEffectTransition(.matchedGeometry)
                }
            }
            ForEach(ripples, id: \.self) { _ in
                Ripple()
            }
            .allowsHitTesting(false)
            
            Button(action: handleMainButtonTap) {
                Image(systemName: mainButtonSystemName)
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 30))
                    .frame(width: 80, height: 80)
                    .symbolEffect(
                        .variableColor,
                        options: .repeating,
                        isActive: isVariableColorActive && (translator.isConnecting || translator.isStopping)
                    )
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.pink)
        }
        .frame(height: 120)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: translator.isConnected)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: translator.isConnecting)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: translator.isRecording)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: translator.isAudioPlaybackEnabled)
        .onChange(of: translator.microphoneLevel) { _, newLevel in
            guard translator.isRecording else {
                if !ripples.isEmpty { ripples.removeAll() }
                return
            }
            
            let now = Date()
            guard now.timeIntervalSince(lastRippleTime) >= 0.75 else { return }
            let minVolumeThreshold: Float = 0.05
            if newLevel > minVolumeThreshold && newLevel > previousLevel {
                lastRippleTime = now
                let id = UUID()
                ripples.append(id)
                
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run {
                        ripples.removeAll { $0 == id }
                    }
                }
            }
            previousLevel = newLevel
        }
    }
    
    private var mainButtonSystemName: String {
        if translator.isConnecting || translator.isStopping {
            return "ellipsis"
        } else if translator.isConnected {
            return "stop.fill"
        } else {
            return "mic.fill"
        }
    }
    
    private func handleMainButtonTap() {
        if translator.isConnected {
            guard !translator.isStopping else { return }
            translator.isStopping = true
            translator.stopRecording()
            Task {
                await stopAndSaveSession()
            }
        } else {
            translator.isConnecting = true
            translator.connect()
            print("接続マイク開始")
        }
    }
    
    private func stopAndSaveSession() async {
        try? await Task.sleep(for: .seconds(1.5))
        
        let pastOriginals: [String] = displayState.originalMessages.map { $0.text }
        let currentOriginalCombined: String = displayState.accumulatedOriginal + displayState.currentOriginalText
        let allOriginals: [String] = pastOriginals + [currentOriginalCombined]
        let finalOriginal: String = allOriginals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        
        let pastTranslations: [String] = displayState.translatedMessages.map { $0.text }
        let currentTranslatedCombined: String = displayState.accumulatedTranslated + displayState.currentTranslatedText
        let allTranslations: [String] = pastTranslations + [currentTranslatedCombined]
        let finalTranslated: String = allTranslations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        
        if !finalOriginal.isEmpty || !finalTranslated.isEmpty {
            let newSession = TranslationSession(
                originalText: finalOriginal,
                translatedText: finalTranslated,
                targetLanguageCode: targetLanguage.languageCode?.identifier ?? "ja"
            )
            modelContext.insert(newSession)
            try? modelContext.save()
        }
        
        translator.disconnect()
        displayState = TranslationDisplayState()
        isVariableColorActive = false
        
        try? await Task.sleep(for: .seconds(0.2))
        translator.isStopping = false
    }
}


// MARK: - AttributedString Extension
extension AttributedString {
    static func makeInteractiveText(
        _ text: String,
        context: String,
        foregroundColor: Color,
        loadingWord: String?,
        explainedWords: Set<String>
    ) -> AttributedString {
        var attributedString = AttributedString()
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: []) { tag, tokenRange in
            let wordStr = String(text[tokenRange])
            var wordAttr = AttributedString(wordStr)
            var requestWord = wordStr
            if let lemmaTag = tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0 {
                requestWord = lemmaTag.rawValue
            }
            
            let isWord: Bool
            if let tag = tag {
                isWord = tag != .punctuation && tag != .whitespace
            } else {
                let trimmed = wordStr.trimmingCharacters(in: .whitespacesAndNewlines)
                isWord = !trimmed.isEmpty && !trimmed.allSatisfy { $0.isPunctuation }
            }
            
            if isWord {
                let lower = requestWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                let displayColor: Color
                if let loading = loadingWord?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), lower == loading {
                    displayColor = .orange
                    wordAttr.underlineStyle = .single
                } else if explainedWords.contains(lower) {
                    displayColor = .pink
                    wordAttr.underlineStyle = nil
                } else {
                    displayColor = foregroundColor
                    wordAttr.underlineStyle = nil
                }
                
                if let encodedWord = requestWord.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
                   let encodedContext = context.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "explain://\(encodedWord)?context=\(encodedContext)") {
                    wordAttr.link = url
                    wordAttr.foregroundColor = displayColor
                }
            } else {
                wordAttr.foregroundColor = foregroundColor
            }
            attributedString.append(wordAttr)
            return true
        }
        
        return attributedString
    }
}

