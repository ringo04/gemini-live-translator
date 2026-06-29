import Foundation
import Combine
import NaturalLanguage

@MainActor
class KeywordExtractor: ObservableObject {
    
    @Published var explanations: [KeywordExplanation] = []
    @Published var isExtracting = false
    @Published var errorMessage: String?
    @Published var loadingWord: String? = nil
    
    private var apiKey: String
    private var targetLanguage = "ja"
    private var extractedWords: Set<String> = []
    private var currentContext = ""
    
    init(apiKey: String, targetLanguage: String = "ja") {
        self.apiKey = apiKey
        self.targetLanguage = targetLanguage
    }
    
    func clear() {
        explanations.removeAll()
        extractedWords.removeAll()
        errorMessage = nil
        loadingWord = nil
        currentContext = ""
    }
    
    func updateConfig(apiKey: String, targetLanguage: String) {
        self.apiKey = apiKey
        self.targetLanguage = targetLanguage
        clear()
    }
    
    // MARK: - Tap-to-Explain API
    func addTranscriptText(_ text: String, newSegment: String) {
        self.currentContext = text
    }
    
    func explainWord(_ word: String, context: String? = nil) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty, loadingWord == nil else { return }
        
        loadingWord = trimmedWord
        errorMessage = nil
        
        let activeContext = context ?? currentContext
        
        guard let url = makeAPIURL() else {
            loadingWord = nil
            errorMessage = "Invalid API URL"
            return
        }
        
        let request = makeSingleWordRequest(url: url, word: trimmedWord, context: activeContext)
        
        Task {
            defer {
                loadingWord = nil
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    errorMessage = "API status \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                    return
                }
                handleSingleWordResponse(data: data, originalWord: trimmedWord)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Private: Networking
    private func makeAPIURL() -> URL? {
        let clean = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(clean)")
    }
    
    private var targetLanguageName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: targetLanguage) ?? "Japanese"
    }
    
    private func makeSingleWordRequest(url: URL, word: String, context: String) -> URLRequest {
        let langName = targetLanguageName
        let prompt = """
        Explain the word or phrase "\(word)" based on the context in which it was used.
        
        [Context]
        "\(context)"
        
        Requirements:
        - Output a JSON array containing exactly 1 object for the explanation.
        - Provide the explanation in \(langName):
          - "part_of_speech": written in \(langName) (e.g. "名詞", "動詞", "形容詞", "副詞", "慣用句")
          - "meaning": its meaning in \(langName) matching the context
          - "explanation": a detailed explanation including nuance (1–2 sentences) in \(langName)
          - "example": a short example sentence using the word or phrase
          - "example_translation": a \(langName) translation of the example sentence
        """
        
        let body = GeminiRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(
                responseMimeType: "application/json",
                responseSchema: .init(
                    type: "ARRAY",
                    items: .init(
                        type: "OBJECT",
                        properties: [
                            "word":                .init(type: "STRING"),
                            "part_of_speech":      .init(type: "STRING"),
                            "meaning":             .init(type: "STRING"),
                            "explanation":         .init(type: "STRING"),
                            "example":             .init(type: "STRING"),
                            "example_translation": .init(type: "STRING"),
                        ],
                        required: ["word", "part_of_speech", "meaning", "explanation", "example", "example_translation"]
                    )
                )
            )
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }
    
    private func handleSingleWordResponse(data: Data, originalWord: String) {
        do {
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard
                let jsonText = geminiResponse.candidates.first?.content.parts.first?.text,
                let jsonData = jsonText.data(using: .utf8)
            else { return }
            
            let newItems = try JSONDecoder().decode([KeywordExplanation].self, from: jsonData)
            if let item = newItems.first {
                appendSingleWordExplanation(item, originalWord: originalWord)
            }
        } catch {
            errorMessage = "Failed to parse single word explanation data"
        }
    }
    
    private func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendSingleWordExplanation(_ item: KeywordExplanation, originalWord: String) {
        let key = normalized(item.word)
        explanations.append(item)
        extractedWords.insert(key)
    }
}
