//  TextProcessingPreset.swift
//  VibingSpeech

import Foundation

enum TextProcessingPreset: String, CaseIterable, Codable, Identifiable {
    case fixTypos
    case bulletPoints
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fixTypos: return "Fix Typos"
        case .bulletPoints: return "Bullet Points"
        case .custom: return "Custom"
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .fixTypos: return "誤字脱字修正"
        case .bulletPoints: return "箇条書きにする"
        case .custom: return "カスタム"
        }
    }

    func systemPrompt(detectedLanguage: String) -> String {
        let langInstruction: String
        switch detectedLanguage.lowercased().prefix(2) {
        case "ja":
            langInstruction = "入力テキストは日本語です。出力も日本語で返してください。"
        case "zh":
            langInstruction = "输入文本是中文。请用中文输出。"
        case "en":
            langInstruction = "The input text is in English. Respond in English."
        case "ko":
            langInstruction = "입력 텍스트는 한국어입니다. 한국어로 응답하세요."
        default:
            langInstruction =
                "Detect the language of the input text and always respond in that same language."
        }

        switch self {
        case .fixTypos:
            return """
                You are a speech-to-text correction assistant. \(langInstruction)
                The input is auto-transcribed from speech. Fix misrecognized words, spelling errors, grammar mistakes, and incorrect word boundaries.
                Keep the original meaning and tone. Do not add or remove content.
                Output only the corrected text with no explanation or prefix.
                """
        case .bulletPoints:
            return """
                You are a text formatting assistant. \(langInstruction)
                The input is auto-transcribed from speech. Fix any errors while reformatting.
                Convert the text into:
                - Line 1: A concise title summarizing the subject.
                - Line 2+: Key points as a bullet-point list, each starting with "- ".
                Organize points logically. Omit redundant or filler content.
                Output ONLY the title and bullet points. No explanation, no quotes, no prefix.
                """
        case .custom:
            return ""
        }
    }
}
