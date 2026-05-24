import Foundation

struct TranscriptionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var finalText: String
    var originalASRText: String?
    var timestamp: Date
    var wordCount: Int
    var durationSeconds: Double
    var modelVariant: ASRModelVariant
    var wasProcessedByLLM: Bool

    init(
        id: UUID = UUID(),
        finalText: String,
        originalASRText: String? = nil,
        timestamp: Date = Date(),
        durationSeconds: Double,
        modelVariant: ASRModelVariant,
        wasProcessedByLLM: Bool
    ) {
        self.id = id
        self.finalText = finalText
        self.originalASRText = originalASRText
        self.timestamp = timestamp
        self.wordCount = WordCounter.count(finalText)
        self.durationSeconds = durationSeconds
        self.modelVariant = modelVariant
        self.wasProcessedByLLM = wasProcessedByLLM
    }
}

struct Hotword: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date

    init?(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.id = id
        self.text = trimmed
        self.createdAt = createdAt
    }
}

struct MicrophoneDevice: Identifiable, Equatable {
    var id: String
    var name: String

    static let systemDefault = MicrophoneDevice(id: "system-default", name: "System Default")
}

struct ASRResult: Equatable {
    var text: String
    var detectedLanguage: String?
}

