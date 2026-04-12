//
//  TranscriptionRecord.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import Foundation

struct TranscriptionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let wordCount: Int
    let durationSeconds: Double
    let modelVariant: ASRModelVariant

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        durationSeconds: Double,
        modelVariant: ASRModelVariant
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.modelVariant = modelVariant

        // Calculate word count: for CJK use character count, otherwise word count
        let cjkCharacterSet = CharacterSet(charactersIn: "\u{4e00}"..."\u{9fff}")
            .union(CharacterSet(charactersIn: "\u{3040}"..."\u{30ff}"))
            .union(CharacterSet(charactersIn: "\u{ac00}"..."\u{d7af}"))
        if text.rangeOfCharacter(from: cjkCharacterSet) != nil {
            self.wordCount = text.count
        } else {
            self.wordCount = text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .count
        }
    }

    var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) {
            return "Today"
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else {
            return Self.dateFormatter.string(from: timestamp)
        }
    }
}
