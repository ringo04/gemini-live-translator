


import Foundation
import SwiftData


// MARK: - Gemini Live API / WebSocket Models
struct LiveSetupMessage: Codable {
    let setup: SetupData
}

struct SetupData: Codable {
    let model: String
    let generationConfig: GenerationConfig
    let inputAudioTranscription: AudioTranscriptionConfig?
    let outputAudioTranscription: AudioTranscriptionConfig?
}

struct AudioTranscriptionConfig: Codable {}

struct GenerationConfig: Codable {
    let responseModalities: [String]
    let translationConfig: TranslationConfig
}

struct TranslationConfig: Codable {
    let targetLanguageCode: Locale.LanguageCode
    let echoTargetLanguage: Bool
}

struct LiveRealtimeInputMessage: Codable {
    let realtimeInput: RealtimeInputData
}

struct RealtimeInputData: Codable {
    let mediaChunks: [MediaChunk]
}

struct MediaChunk: Codable {
    let mimeType: String
    let data: String // Base64エンコード済み PCM
}

// MARK: - Server Response
struct LiveServerResponse: Codable {
    let serverContent: ServerContent?
}

struct ServerContent: Codable {
    let modelTurn: ModelTurn?
    let inputTranscription: TranscriptionText?
    let outputTranscription: TranscriptionText?
}

struct ModelTurn: Codable {
    let parts: [Part]
}

struct Part: Codable {
    let inlineData: InlineData?
}

struct InlineData: Codable {
    let mimeType: String
    let data: String // Base64エンコード済み PCM
}

struct TranscriptionText: Codable {
    let text: String?
    let languageCode: String?
}


// MARK: - Gemini GenerateContent API Models
struct GeminiRequest: Codable {
    let contents: [Content]
    let generationConfig: GeminiGenerationConfig

    struct Content: Codable {
        let parts: [TextPart]
        struct TextPart: Codable {
            let text: String
        }
    }

    struct GeminiGenerationConfig: Codable {
        let responseMimeType: String
        let responseSchema: Schema

        struct Schema: Codable {
            let type: String
            let items: SchemaItem?

            struct SchemaItem: Codable {
                let type: String
                let properties: [String: Property]
                let required: [String]

                struct Property: Codable {
                    let type: String
                }
            }
        }
    }
}

struct GeminiResponse: Codable {
    let candidates: [Candidate]

    struct Candidate: Codable {
        let content: Content

        struct Content: Codable {
            let parts: [Part]

            struct Part: Codable {
                let text: String
            }
        }
    }
}


// MARK: - App Models
struct TextSegment: Identifiable, Equatable, Codable {
    var id = UUID()
    let text: String
}


struct KeywordExplanation: Identifiable, Equatable, Codable {
    var id = UUID()
    let word: String
    let partOfSpeech: String
    let meaning: String
    let explanation: String
    let example: String
    let exampleTranslation: String

    enum CodingKeys: String, CodingKey {
        case word, meaning, explanation, example
        case partOfSpeech       = "part_of_speech"
        case exampleTranslation = "example_translation"
    }

    init(word: String, partOfSpeech: String, meaning: String, explanation: String, example: String, exampleTranslation: String) {
        self.id          = UUID()
        self.word        = word
        self.partOfSpeech = partOfSpeech
        self.meaning     = meaning
        self.explanation = explanation
        self.example     = example
        self.exampleTranslation = exampleTranslation
    }
}


// MARK: - SwiftData Model
@Model
final class SavedKeyword {
    var id: UUID
    var word: String
    var partOfSpeech: String
    var meaning: String
    var explanation: String
    var example: String
    var exampleTranslation: String
    var savedAt: Date

    init(id: UUID = UUID(), word: String, partOfSpeech: String, meaning: String, explanation: String, example: String, exampleTranslation: String, savedAt: Date = Date()) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.explanation = explanation
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.savedAt = savedAt
    }
}

@Model
final class TranslationSession {
    var id: UUID
    var date: Date
    var originalText: String
    var translatedText: String
    var targetLanguageCode: String
    
    var targetLanguage: Locale.LanguageCode {
        Locale.LanguageCode(targetLanguageCode)
    }
    
    init(id: UUID = UUID(), date: Date = Date(), originalText: String, translatedText: String, targetLanguageCode: String) {
        self.id = id
        self.date = date
        self.originalText = originalText
        self.translatedText = translatedText
        self.targetLanguageCode = targetLanguageCode
    }
}

struct TranslationDisplayState {
    var originalMessages: [TextSegment] = []
    var translatedMessages: [TextSegment] = []
    var accumulatedOriginal = ""
    var accumulatedTranslated = ""
    var currentOriginalText = ""
    var currentTranslatedText = ""
}
