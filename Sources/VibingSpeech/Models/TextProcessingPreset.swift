//
//  TextProcessingPreset.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/13.
//  Copyright © 2026 Shuichi. All rights reserved.
//

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

    /// Returns the system prompt for the LLM based on the detected language.
    /// The `detectedLanguage` parameter is a language code like "ja", "en", "zh", etc.
    func systemPrompt(detectedLanguage: String) -> String {
        let langInstruction: String
        switch detectedLanguage.lowercased().prefix(2) {
        case "ja":
            langInstruction = "入力テキストは日本語です。出力も日本語で返してください。"
        case "zh":
            langInstruction = "输入文本是中文。请用中文输出。"
        case "en":
            langInstruction = "The input text is in English. Respond in English."
        default:
            langInstruction = "Respond in the same language as the input text."
        }

        switch self {
        case .fixTypos:
            return """
                You are a text correction assistant. \(langInstruction)
                Fix typos, spelling errors, and grammatical mistakes in the given text.
                Keep the original meaning and tone intact. Do not add new content.
                Output ONLY the corrected text with no explanation, no quotes, no prefix.
                """
        case .bulletPoints:
            return """
                You are a text formatting assistant. \(langInstruction)
                Convert the given text into a clear bullet-point list.
                Each bullet point should start with "- " (hyphen space).
                Extract the key points and organize them logically.
                Output ONLY the bullet-point list with no explanation, no quotes, no prefix.
                """
        case .custom:
            // For custom, the system prompt is provided by the user
            return ""
        }
    }
}
