//  Hotword.swift
//  VibingSpeech

import Foundation

struct Hotword: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}
