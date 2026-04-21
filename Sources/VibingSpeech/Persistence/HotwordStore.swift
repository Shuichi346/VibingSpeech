//  HotwordStore.swift
//  VibingSpeech

import Foundation
import Observation

@Observable final class HotwordStore {
    private(set) var hotwords: [Hotword] = []
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
        self.fileURL = baseURL.appendingPathComponent("hotwords.json")

        load()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !hotwords.contains(where: { $0.text.lowercased() == trimmed.lowercased() }) else {
            return
        }

        hotwords.append(Hotword(text: trimmed))
        save()
    }

    func delete(_ hotword: Hotword) {
        hotwords.removeAll { $0.id == hotword.id }
        save()
    }

    var hotwordTexts: [String] {
        hotwords.map { $0.text }
    }

    /// Qwen3-ASRデコーダープロンプトプレフィックス用のコンテキスト文字列
    var recognitionContext: String? {
        guard !hotwordTexts.isEmpty else { return nil }
        return "Key terms: \(hotwordTexts.joined(separator: ", "))"
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(hotwords)
            try data.write(to: fileURL, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = "Failed to save hotwords: \(error.localizedDescription)"
            print("Failed to save hotwords: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            hotwords = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            hotwords = try JSONDecoder().decode([Hotword].self, from: data)
        } catch {
            // デコード失敗時はメモリ上では空配列にするが、
            // 破損ファイルを空配列で上書きしない（データ復旧の余地を残す）
            print("Failed to load hotwords (file preserved): \(error)")
            hotwords = []
        }
    }
}
