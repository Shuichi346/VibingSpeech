import Foundation

enum ASRModelVariant: String, CaseIterable, Codable, Identifiable {
    case qwen3_0_6b_8bit
    case qwen3_1_7b_4bit
    case qwen3_1_7b_8bit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen3_0_6b_8bit: "Qwen3-ASR 0.6B (8-bit)"
        case .qwen3_1_7b_4bit: "Qwen3-ASR 1.7B (4-bit)"
        case .qwen3_1_7b_8bit: "Qwen3-ASR 1.7B (8-bit)"
        }
    }

    var huggingFaceModelID: String {
        switch self {
        case .qwen3_0_6b_8bit: "mlx-community/Qwen3-ASR-0.6B-8bit"
        case .qwen3_1_7b_4bit: "mlx-community/Qwen3-ASR-1.7B-4bit"
        case .qwen3_1_7b_8bit: "mlx-community/Qwen3-ASR-1.7B-8bit"
        }
    }

    var estimatedDownloadSize: String {
        switch self {
        case .qwen3_0_6b_8bit: "~1.0 GB"
        case .qwen3_1_7b_4bit: "~1.6 GB"
        case .qwen3_1_7b_8bit: "~2.5 GB"
        }
    }

    var estimatedMemory: String {
        switch self {
        case .qwen3_0_6b_8bit: "~1.5 GB"
        case .qwen3_1_7b_4bit: "~3.0 GB"
        case .qwen3_1_7b_8bit: "~3.5 GB"
        }
    }

    static let defaultVariant: ASRModelVariant = .qwen3_0_6b_8bit
}

enum TextProcessingPreset: String, CaseIterable, Codable, Identifiable {
    case fixTypos
    case bulletPoints
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixTypos: "Fix Typos"
        case .bulletPoints: "Bullet Points"
        case .custom: "Custom"
        }
    }

    func systemPrompt(detectedLanguage: String?, selectedLanguage: LanguageMode, customPrompt: String = "") -> String {
        let languageInstruction = selectedLanguage.promptLanguageInstruction(detectedLanguage: detectedLanguage)
        switch self {
        case .fixTypos:
            return """
                You are a speech-to-text correction assistant. \(languageInstruction)
                The input is auto-transcribed from speech. Fix misrecognized words, spelling errors, grammar mistakes, and incorrect word boundaries.
                Keep the original meaning and tone. Do not add or remove content.
                Output only the corrected text with no explanation or prefix.
            """
        case .bulletPoints:
            return """
                You are a text formatting assistant. \(languageInstruction)
                The input is auto-transcribed from speech. Fix any errors while reformatting.
                Convert the text into:
                - Line 1: A concise title summarizing the subject.
                - Line 2+: Key points as a bullet-point list, each starting with "- ".
                Organize points logically. Omit redundant or filler content.
                Output ONLY the title and bullet points. No explanation, no quotes, no prefix.
            """
        case .custom:
            return customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

enum RecordingPhase: String, Codable {
    case idle
    case starting
    case recording
    case transcribing
}

enum HistoryRetention: String, CaseIterable, Codable, Identifiable {
    case forever
    case oneWeek
    case oneDay
    case never

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forever: "Forever"
        case .oneWeek: "One Week"
        case .oneDay: "One Day"
        case .never: "Never"
        }
    }

    var cutoffDate: Date? {
        switch self {
        case .forever, .never:
            return nil
        case .oneWeek:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .oneDay:
            return Calendar.current.date(byAdding: .day, value: -1, to: Date())
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum LanguageMode: String, CaseIterable, Codable, Identifiable {
    case auto
    case english
    case japanese
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .english: "English"
        case .japanese: "Japanese"
        case .chinese: "Chinese"
        }
    }

    var asrLanguageHint: String? {
        switch self {
        case .auto: nil
        case .english: "en"
        case .japanese: "ja"
        case .chinese: "zh"
        }
    }

    static func normalized(_ value: String?) -> LanguageMode {
        let normalizedValue = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "language ", with: "")
        return switch normalizedValue {
        case "en", "eng", "english": LanguageMode.english
        case "ja", "jp", "japanese": LanguageMode.japanese
        case "zh", "zho", "chi", "chinese", "cn": LanguageMode.chinese
        default: LanguageMode.auto
        }
    }

    func promptLanguageName(detectedLanguage: String?) -> String {
        switch self {
        case .auto:
            return LanguageMode.normalized(detectedLanguage).displayName
        case .english, .japanese, .chinese:
            return displayName
        }
    }

    func promptLanguageInstruction(detectedLanguage: String?) -> String {
        switch self {
        case .auto:
            let detected = LanguageMode.normalized(detectedLanguage)
            guard detected != .auto else {
                return "Use the same language as the input transcription."
            }
            return "Write the output in \(detected.displayName)."
        case .english, .japanese, .chinese:
            return "Write the output in \(displayName)."
        }
    }
}

enum RecordingHotkey: String, CaseIterable, Codable, Identifiable {
    case rightOption
    case leftControl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightOption: "⌥ Right Option"
        case .leftControl: "⌃ Left Control"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .rightOption: 61
        case .leftControl: 59
        }
    }
}

enum SidebarSelection: String, CaseIterable, Identifiable {
    case home
    case hotwords
    case history
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .hotwords: "Hotwords"
        case .history: "History"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .hotwords: "text.badge.plus"
        case .history: "clock"
        case .other: "ellipsis.circle"
        }
    }
}

enum WordCounter {
    static func count(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        var count = 0
        var isInsideNonCJKWord = false

        for scalar in trimmed.unicodeScalars {
            if isCJK(scalar) {
                if isInsideNonCJKWord {
                    count += 1
                    isInsideNonCJKWord = false
                }
                count += 1
                continue
            }

            let category = scalar.properties.generalCategory
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                 .otherLetter, .decimalNumber, .letterNumber, .otherNumber:
                isInsideNonCJKWord = true
            case .nonspacingMark, .spacingMark, .enclosingMark:
                break
            default:
                if isInsideNonCJKWord {
                    count += 1
                    isInsideNonCJKWord = false
                }
            }
        }

        return count + (isInsideNonCJKWord ? 1 : 0)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}
