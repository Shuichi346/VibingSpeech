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

struct LiveTranscriptSnapshot: Equatable, Sendable {
    var finalizedText: String
    var partialText: String
    var statusMessage: String?

    static let empty = LiveTranscriptSnapshot(finalizedText: "", partialText: "", statusMessage: nil)

    var combinedText: String {
        LiveTranscriptBuffer.join(finalizedText, partialText)
    }
}

struct LiveTranscriptBuffer: Equatable, Sendable {
    private(set) var finalizedSegments: [String] = []
    private(set) var partialText: String = ""
    private(set) var statusMessage: String?

    var finalizedText: String {
        finalizedSegments.joined(separator: " ")
    }

    var snapshot: LiveTranscriptSnapshot {
        LiveTranscriptSnapshot(
            finalizedText: finalizedText,
            partialText: partialText,
            statusMessage: statusMessage
        )
    }

    var combinedText: String {
        Self.join(finalizedText, partialText)
    }

    mutating func updatePartial(_ text: String) {
        partialText = Self.normalized(text)
        statusMessage = nil
    }

    mutating func commitFinal(_ text: String) {
        let normalized = Self.normalized(text)
        guard !normalized.isEmpty else { return }
        finalizedSegments.append(normalized)
        partialText = ""
        statusMessage = nil
    }

    mutating func commitPartialIfNeeded() {
        commitFinal(partialText)
    }

    mutating func setStatus(_ message: String?) {
        statusMessage = message
    }

    mutating func reset() {
        finalizedSegments = []
        partialText = ""
        statusMessage = nil
    }

    static func join(_ finalizedText: String, _ partialText: String) -> String {
        [normalized(finalizedText), normalized(partialText)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
