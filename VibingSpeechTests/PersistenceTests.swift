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
        XCTAssertFalse(store.liveTranscriptionEnabled)
        XCTAssertEqual(store.languageMode, .auto)
        XCTAssertEqual(store.modelUnloadDelayMinutes, 5)

        store.recordingHotkey = .leftControl
        store.liveTranscriptionEnabled = true
        store.languageMode = .japanese
        store.modelUnloadDelayMinutes = 17

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.recordingHotkey, .leftControl)
        XCTAssertTrue(reloaded.liveTranscriptionEnabled)
        XCTAssertEqual(reloaded.languageMode, .japanese)
        XCTAssertEqual(reloaded.modelUnloadDelayMinutes, 17)
    }

    func testModelUnloadDelayBounds() {
        XCTAssertEqual(SettingsStore.clampedModelUnloadDelayMinutes(-1), 0)
        XCTAssertEqual(SettingsStore.clampedModelUnloadDelayMinutes(0), 0)
        XCTAssertEqual(SettingsStore.clampedModelUnloadDelayMinutes(60), 60)
        XCTAssertEqual(SettingsStore.clampedModelUnloadDelayMinutes(61), 60)
    }

    func testHistoryNeverRetentionWritesNoRecords() async throws {
        let directory = try temporaryDirectory()
        let repository = HistoryRepository(directoryURL: directory)
        await repository.add(sampleRecord(text: "hello"), retention: .never)
        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
    }

    func testHistoryNeverRetentionRemovesExistingHistoryFile() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("history.json")
        let repository = HistoryRepository(directoryURL: directory)
        await repository.add(sampleRecord(text: "kept"), retention: .forever)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        await repository.add(sampleRecord(text: "discarded"), retention: .never)

        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let reloaded = HistoryRepository(directoryURL: directory)
        await reloaded.load(retention: .forever)
        XCTAssertTrue(reloaded.records.isEmpty)
    }

    func testApplyingNeverRetentionRemovesExistingHistoryFile() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("history.json")
        let repository = HistoryRepository(directoryURL: directory)
        await repository.add(sampleRecord(text: "kept"), retention: .forever)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        await repository.applyRetention(.never)

        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let reloaded = HistoryRepository(directoryURL: directory)
        await reloaded.load(retention: .forever)
        XCTAssertTrue(reloaded.records.isEmpty)
    }

    func testApplyingTimedRetentionPrunesExistingHistory() async throws {
        let directory = try temporaryDirectory()
        let repository = HistoryRepository(directoryURL: directory)
        await repository.add(sampleRecord(text: "recent", timestamp: Date()), retention: .forever)
        await repository.add(
            sampleRecord(
                text: "old",
                timestamp: Calendar.current.date(byAdding: .day, value: -2, to: Date())!
            ),
            retention: .forever
        )

        await repository.applyRetention(.oneDay)

        XCTAssertEqual(repository.records.map(\.finalText), ["recent"])
        let reloaded = HistoryRepository(directoryURL: directory)
        await reloaded.load(retention: .forever)
        XCTAssertEqual(reloaded.records.map(\.finalText), ["recent"])
    }

    func testHistoryArrayMigratesToJournalAndRepairsWordCount() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("history.json")
        var legacy = sampleRecord(text: "two words")
        legacy.wordCount = 999
        try JSONEncoder.vibingSpeech.encode([legacy]).write(to: file)

        let repository = HistoryRepository(directoryURL: directory)
        await repository.load(retention: .forever)

        XCTAssertEqual(repository.records.map(\.finalText), ["two words"])
        XCTAssertEqual(repository.records.first?.wordCount, 2)
        let journalData = try Data(contentsOf: file)
        XCTAssertEqual([UInt8](journalData).first { $0 != 0x09 && $0 != 0x0A && $0 != 0x0D && $0 != 0x20 }, UInt8(ascii: "{"))
        let journalLine = try XCTUnwrap([UInt8](journalData).split(separator: 0x0A).first)
        XCTAssertEqual(
            try JSONDecoder.vibingSpeech.decode(TranscriptionRecord.self, from: Data(journalLine)),
            repository.records.first
        )
    }

    func testHistoryJournalAppendsAndSurvivesReload() async throws {
        let directory = try temporaryDirectory()
        let repository = HistoryRepository(directoryURL: directory)
        await repository.load(retention: .forever)
        await repository.add(sampleRecord(text: "first", timestamp: Date(timeIntervalSince1970: 1_000)), retention: .forever)
        await repository.add(sampleRecord(text: "second", timestamp: Date(timeIntervalSince1970: 1_001)), retention: .forever)

        let reloaded = HistoryRepository(directoryURL: directory)
        await reloaded.load(retention: .forever)
        XCTAssertEqual(reloaded.records.map(\.finalText), ["second", "first"])
    }

    func testStartupRetentionPrunesPersistedRecords() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("history.json")
        let recent = sampleRecord(text: "recent", timestamp: Date())
        let old = sampleRecord(text: "old", timestamp: Calendar.current.date(byAdding: .day, value: -2, to: Date())!)
        try JSONEncoder.vibingSpeech.encode([recent, old]).write(to: file)

        let repository = HistoryRepository(directoryURL: directory)
        await repository.load(retention: .oneDay)
        XCTAssertEqual(repository.records.map(\.finalText), ["recent"])

        let reloaded = HistoryRepository(directoryURL: directory)
        await reloaded.load(retention: .forever)
        XCTAssertEqual(reloaded.records.map(\.finalText), ["recent"])
    }

    func testCorruptedHistoryIsPreserved() async throws {
        let directory = try temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        try Data("not-json".utf8).write(to: file)

        let repository = HistoryRepository(directoryURL: directory)
        await repository.load(retention: .forever)
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

    func testHotwordBatchDeletePersistsOneResult() throws {
        let directory = try temporaryDirectory()
        let repository = HotwordRepository(directoryURL: directory)
        XCTAssertTrue(repository.add("first"))
        XCTAssertTrue(repository.add("second"))
        XCTAssertTrue(repository.add("third"))
        let removedIDs = Set(repository.hotwords.prefix(2).map(\.id))

        repository.delete(ids: removedIDs)

        XCTAssertEqual(repository.hotwords.map(\.text), ["first"])
        XCTAssertEqual(HotwordRepository(directoryURL: directory).hotwords.map(\.text), ["first"])
    }

    func testCorruptedHotwordFileIsPreservedBeforeWritingNewData() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("hotwords.json")
        try Data("not-json".utf8).write(to: file)

        let repository = HotwordRepository(directoryURL: directory)
        XCTAssertTrue(repository.hotwords.isEmpty)
        XCTAssertTrue(repository.add("Qwen"))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let preservedName = try XCTUnwrap(files.first { $0.hasPrefix("hotwords.corrupt-") })
        let preservedData = try Data(contentsOf: directory.appendingPathComponent(preservedName))
        XCTAssertEqual(preservedData, Data("not-json".utf8))
        XCTAssertEqual(HotwordRepository(directoryURL: directory).hotwords.map(\.text), ["Qwen"])
    }

    func testCorruptedHotwordFileIsNotOverwrittenWhenPreservationFails() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("hotwords.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: file)

        let repository = HotwordRepository(directoryURL: directory, fileManager: FailingMoveFileManager())
        XCTAssertTrue(repository.add("Qwen"))

        XCTAssertEqual(try Data(contentsOf: file), corruptData)
        XCTAssertEqual(repository.hotwords.map(\.text), ["Qwen"])
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

    private func sampleRecord(text: String, timestamp: Date = Date()) -> TranscriptionRecord {
        TranscriptionRecord(
            finalText: text,
            timestamp: timestamp,
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

private final class FailingMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}
