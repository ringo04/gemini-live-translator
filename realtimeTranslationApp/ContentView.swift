import SwiftUI
import SwiftData


// MARK: - ContentView
struct ContentView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var apiKey: String = ""
    @State private var targetLanguage: Locale.Language = Locale.Language(components: .init(languageCode: .japanese))
    @State private var apiVersion: String = "v1beta"
    @State private var isShowingInvalidKeyAlert = false
    @StateObject private var keywordExtractor: KeywordExtractor
    @StateObject private var translator: GeminiLiveTranslator
    
    init() {
        let savedKey = KeychainHelper.load(for: "gemini_api_key") ?? ""
        _apiKey = State(initialValue: savedKey)
        
        let savedLangCode = UserDefaults.standard.string(forKey: "target_language") ?? "ja"
        let defaultLang = Locale.Language(components: .init(languageCode: Locale.LanguageCode(savedLangCode)))
        _targetLanguage = State(initialValue: defaultLang)
        
        let extractor = KeywordExtractor(apiKey: savedKey, targetLanguage: defaultLang.languageCode?.identifier ?? "ja")
        let liveTranslator = GeminiLiveTranslator(apiKey: savedKey, targetLanguage: defaultLang, keywordExtractor: extractor)
        
        _keywordExtractor = StateObject(wrappedValue: extractor)
        _translator = StateObject(wrappedValue: liveTranslator)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    APIKeyPromptView(apiKey: $apiKey)
                        .transition(.blurReplace)
                } else {
                    MainTimelineView(
                        apiKey: $apiKey,
                        translator: translator,
                        keywordExtractor: keywordExtractor,
                        targetLanguage: $targetLanguage,
                        onUnlockAPIKey: {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                apiKey = ""
                            }
                        }
                    )
                    .transition(.blurReplace)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        
        .onChange(of: apiKey) { _, newKey in
            KeychainHelper.save(newKey, for: "gemini_api_key")
            updateObjects(key: newKey, lang: targetLanguage, apiVersion: apiVersion)
        }
        .onChange(of: targetLanguage) { _, newLang in
            let langCode = newLang.languageCode?.identifier ?? "ja"
            UserDefaults.standard.set(langCode, forKey: "target_language")
            updateObjects(key: apiKey, lang: newLang, apiVersion: apiVersion)
        }
        .onChange(of: apiVersion) { _, newVersion in
            updateObjects(key: apiKey, lang: targetLanguage, apiVersion: newVersion)
        }
        .onChange(of: translator.isConnected) { _, isConnected in
            if isConnected {
                translator.isConnecting = false
                translator.startRecording()
            }
        }
        .onChange(of: translator.errorStatus) { _, error in
            if let error = error {
                translator.isConnecting = false
                if error.contains("API Keyが無効") {
                    isShowingInvalidKeyAlert = true
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .alert("接続に失敗しました。", isPresented: $isShowingInvalidKeyAlert) {
            Button("OK", role: .cancel) {
                translator.errorStatus = nil
            }
        } message: {
            Text("インターネットの接続状態、Gemini APIキーの設定を確認してください。")
        }
    }
    
    private func updateObjects(key: String, lang: Locale.Language, apiVersion: String) {
        translator.disconnect()
        translator.updateConfig(apiKey: key, targetLanguage: lang, apiVersion: apiVersion)
        keywordExtractor.updateConfig(apiKey: key, targetLanguage: lang.languageCode?.identifier ?? "ja")
    }
}
