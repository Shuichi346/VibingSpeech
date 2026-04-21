//  HistoryStore.swift
//  VibingSpeech

import Foundation
import Observation

@Observable final class HistoryStore {
    private(set) var records: [TranscriptionRecord] = []
    private(set) var lastSaveError: String?

    private let fileURL: URL

    init(directoryURL: URL? = nil) {
        let baseURL: URL
        if let directoryURL = directoryURL {
            baseURL = directoryURL
        } else {
            baseURL = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            .appendingPathComponent("VibingSpeech")
        }

        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        self.fileURL = baseURL.appendingPathComponent("history.json")

        load()
    }

    func add(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        save()
    }

    func delete(_ record: TranscriptionRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    func pruneIfNeeded(retention: SettingsStore.HistoryRetention) {
        let now = Date()
        let calendar = Calendar.current

        switch retention {
        case .forever:
            break
        case .oneWeek:
            let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            records = records.filter { $0.timestamp > oneWeekAgo }
        case .oneDay:
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now)!
            records = records.filter { $0.timestamp > oneDayAgo }
        case .never:
            records.removeAll()
        }

        save()
    }

    var totalWordCount: Int {
        records.reduce(0) { $0 + $1.wordCount }
    }

    var todayWordCount: Int {
        let calendar = Calendar.current
        return
            records
            .filter { calendar.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.wordCount }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL)
            lastSaveError = nil
        } catch {
            lastSaveError = "Failed to save history: \(error.localizedDescription)"
            print("Failed to save history: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([TranscriptionRecord].self, from: data)
        } catch {
            records = []
        }
    }
}
