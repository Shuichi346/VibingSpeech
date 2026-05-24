import AppKit
import AppIntents
import XCTest
@testable import VibingSpeech

@MainActor
final class PersistenceTests: XCTestCase {
    func testSettingsDefaultsAndRoundTrip() {
        let suiteName = "VibingSpeechTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.recordingHotkey, .rightOption)
        XCTAssertEqual(store.languageMode, .auto)
        XCTAssertEqual(store.modelUnloadDelayMinutes, 5)

        store.recordingHotkey = .leftControl
        store.languageMode = .japanese
        store.modelUnloadDelayMinutes = 17

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.recordingHotkey, .leftControl)
        XCTAssertEqual(reloaded.languageMode, .japanese)
        XCTAssertEqual(reloaded.modelUnloadDelayMinutes, 17)
    }

    func testModelUnloadDelayBounds() {
        XCTAssertEqual(SettingsStore.clampedModelUnloadDelayMinutes(-1), 0)
        XCTAssertEqual(SettingsStore.clampedModelUnloadDelayMinutes(0), 0)
        XCTAssertEqual(SettingsStore.clampedModelUnloadDelayMinutes(60), 60)
        XCTAssertEqual(SettingsStore.clampedModelUnloadDelayMinutes(61), 60)
    }

    func testHistoryNeverRetentionWritesNoRecords() throws {
        let directory = try temporaryDirectory()
        let repository = HistoryRepository(directoryURL: directory)
        repository.add(sampleRecord(text: "hello"), retention: .never)
        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
    }

    func testCorruptedHistoryIsPreserved() throws {
        let directory = try temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        try Data("not-json".utf8).write(to: file)

        let repository = HistoryRepository(directoryURL: directory)
        XCTAssertTrue(repository.records.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.contains("corrupt") })
    }

    func testHotwordTrimmingDuplicateRejectionAndOrdering() throws {
        let repository = HotwordRepository(directoryURL: try temporaryDirectory())
        XCTAssertFalse(repository.add("   "))
        XCTAssertTrue(repository.add("  Qwen  "))
        XCTAssertFalse(repository.add("qwen"))
        XCTAssertTrue(repository.add("VibingSpeech"))
        XCTAssertEqual(repository.hotwords.map(\.text), ["VibingSpeech", "Qwen"])
    }

    func testPasteboardConditionalRestore() {
        let pasteboard = NSPasteboard(name: .init("VibingSpeechTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let service = TextInsertionService()
        let snapshot = service.snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("inserted", forType: .string)
        service.restore(snapshot, ifPasteboardStillContains: "inserted", pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")

        pasteboard.clearContents()
        pasteboard.setString("user-change", forType: .string)
        service.restore(snapshot, ifPasteboardStillContains: "inserted", pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "user-change")
    }

    private func sampleRecord(text: String) -> TranscriptionRecord {
        TranscriptionRecord(
            finalText: text,
            durationSeconds: 1,
            modelVariant: .qwen3_0_6b_8bit,
            wasProcessedByLLM: false
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VibingSpeechTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
