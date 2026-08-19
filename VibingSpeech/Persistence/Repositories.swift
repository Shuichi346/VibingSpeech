import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var recordingHotkey: RecordingHotkey { didSet { save() } }
    @Published var liveTranscriptionEnabled: Bool { didSet { save() } }
    @Published var textProcessingEnabled: Bool { didSet { save() } }
    @Published var textProcessingPreset: TextProcessingPreset { didSet { save() } }
    @Published var customPrompt: String { didSet { defaults.set(customPrompt, forKey: "customPrompt") } }
    @Published var soundFeedbackEnabled: Bool { didSet { save() } }
    @Published var languageMode: LanguageMode { didSet { save() } }
    @Published var appearanceMode: AppearanceMode { didSet { save() } }
    @Published var asrModelVariant: ASRModelVariant { didSet { save() } }
    @Published var microphoneID: String { didSet { save() } }
    @Published var selectedSidebar: SidebarSelection { didSet { save() } }
    @Published var historyRetention: HistoryRetention { didSet { save() } }
    @Published var modelUnloadDelayMinutes: Int { didSet { save() } }

    private let defaults: UserDefaults
    static let defaultModelUnloadDelayMinutes = 5
    static let maximumModelUnloadDelayMinutes = 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recordingHotkey = defaults.codableEnum("recordingHotkey") ?? .rightOption
        liveTranscriptionEnabled = defaults.object(forKey: "liveTranscriptionEnabled") as? Bool ?? false
        textProcessingEnabled = defaults.object(forKey: "textProcessingEnabled") as? Bool ?? false
        textProcessingPreset = defaults.codableEnum("textProcessingPreset") ?? .fixTypos
        customPrompt = defaults.string(forKey: "customPrompt") ?? ""
        soundFeedbackEnabled = defaults.object(forKey: "soundFeedbackEnabled") as? Bool ?? true
        languageMode = defaults.codableEnum("languageMode") ?? .auto
        appearanceMode = defaults.codableEnum("appearanceMode") ?? .system
        asrModelVariant = defaults.codableEnum("asrModelVariant") ?? .defaultVariant
        microphoneID = defaults.string(forKey: "microphoneID") ?? MicrophoneDevice.systemDefault.id
        selectedSidebar = defaults.codableEnum("selectedSidebar") ?? .home
        historyRetention = defaults.codableEnum("historyRetention") ?? .forever
        modelUnloadDelayMinutes = Self.clampedModelUnloadDelayMinutes(defaults.integer(forKey: "modelUnloadDelayMinutes"))
        if defaults.object(forKey: "modelUnloadDelayMinutes") == nil {
            modelUnloadDelayMinutes = Self.defaultModelUnloadDelayMinutes
        }
    }

    func save() {
        defaults.set(recordingHotkey.rawValue, forKey: "recordingHotkey")
        defaults.set(liveTranscriptionEnabled, forKey: "liveTranscriptionEnabled")
        defaults.set(textProcessingEnabled, forKey: "textProcessingEnabled")
        defaults.set(textProcessingPreset.rawValue, forKey: "textProcessingPreset")
        defaults.set(customPrompt, forKey: "customPrompt")
        defaults.set(soundFeedbackEnabled, forKey: "soundFeedbackEnabled")
        defaults.set(languageMode.rawValue, forKey: "languageMode")
        defaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
        defaults.set(asrModelVariant.rawValue, forKey: "asrModelVariant")
        defaults.set(microphoneID, forKey: "microphoneID")
        defaults.set(selectedSidebar.rawValue, forKey: "selectedSidebar")
        defaults.set(historyRetention.rawValue, forKey: "historyRetention")
        defaults.set(Self.clampedModelUnloadDelayMinutes(modelUnloadDelayMinutes), forKey: "modelUnloadDelayMinutes")
    }

    static func clampedModelUnloadDelayMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), maximumModelUnloadDelayMinutes)
    }
}

private extension UserDefaults {
    func codableEnum<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
        string(forKey: key).flatMap(T.init(rawValue:))
    }
}

@MainActor
final class HistoryRepository: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []

    private let storage: HistoryStorage
    private var retentionPruneTask: Task<Void, Never>?

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        let base = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibingSpeech", isDirectory: true)
        storage = HistoryStorage(fileURL: base.appendingPathComponent("history.json"))
    }

    deinit {
        retentionPruneTask?.cancel()
    }

    func load(retention: HistoryRetention) async {
        var loadedRecords = await storage.load()
        loadedRecords.sort {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp > $1.timestamp
            }
            return $0.id.uuidString > $1.id.uuidString
        }
        let repairedWordCounts = normalizeWordCounts(&loadedRecords)
        records = loadedRecords

        if retention == .never {
            records = []
            await storage.remove()
            return
        }

        let pruned = pruneIfNeeded(retention: retention)
        if repairedWordCounts || pruned {
            await storage.compact(records)
        }
        scheduleTimedPruning(for: retention)
    }

    func add(_ record: TranscriptionRecord, retention: HistoryRetention) async {
        guard retention != .never else {
            records = []
            await storage.remove()
            return
        }

        records.insert(record, at: 0)
        if pruneIfNeeded(retention: retention) {
            await storage.compact(records)
        } else {
            await storage.append(record)
        }
        scheduleTimedPruning(for: retention)
    }

    func applyRetention(_ retention: HistoryRetention) async {
        switch retention {
        case .forever:
            retentionPruneTask?.cancel()
            retentionPruneTask = nil
            return
        case .never:
            records = []
            retentionPruneTask?.cancel()
            retentionPruneTask = nil
            await storage.remove()
        case .oneWeek, .oneDay:
            if pruneIfNeeded(retention: retention) {
                await storage.compact(records)
            }
            scheduleTimedPruning(for: retention)
        }
    }

    func delete(_ id: UUID) async {
        await delete(ids: [id])
    }

    func delete(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        records.removeAll { ids.contains($0.id) }
        await storage.compact(records)
    }

    func clear() async {
        records = []
        await storage.compact(records)
    }

    @discardableResult
    func pruneIfNeeded(retention: HistoryRetention) -> Bool {
        guard let cutoff = retention.cutoffDate else { return false }
        let originalCount = records.count
        records.removeAll { $0.timestamp < cutoff }
        return records.count != originalCount
    }

    private func normalizeWordCounts(_ records: inout [TranscriptionRecord]) -> Bool {
        var repaired = false
        for index in records.indices {
            let wordCount = WordCounter.count(records[index].finalText)
            if records[index].wordCount != wordCount {
                records[index].wordCount = wordCount
                repaired = true
            }
        }
        return repaired
    }

    private func scheduleTimedPruning(for retention: HistoryRetention) {
        retentionPruneTask?.cancel()
        retentionPruneTask = nil

        guard retention.cutoffDate != nil,
              let nextExpiry = records
                .compactMap({ retention.expirationDate(for: $0.timestamp) })
                .min()
        else {
            return
        }

        let delay = max(0, nextExpiry.timeIntervalSinceNow)
        retentionPruneTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyRetention(retention)
        }
    }
}

private actor HistoryStorage {
    private let fileURL: URL
    private let fileManager = FileManager.default
    private var persistenceBlocked = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [TranscriptionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            if data.firstNonWhitespaceByte == UInt8(ascii: "[") {
                let records = try JSONDecoder.vibingSpeech.decode([TranscriptionRecord].self, from: data)
                try compactThrowing(records)
                return records
            }
            return try data.jsonLines().map { try JSONDecoder.vibingSpeech.decode(TranscriptionRecord.self, from: $0) }
        } catch {
            persistenceBlocked = !preserveCorruptFile()
            NSLog("History persistence load failed: \(error.localizedDescription)")
            return []
        }
    }

    func append(_ record: TranscriptionRecord) {
        guard !persistenceBlocked else { return }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try JSONEncoder.historyJournal.encode(record)
            data.append(0x0A)
            if !fileManager.fileExists(atPath: fileURL.path) {
                guard fileManager.createFile(atPath: fileURL.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            NSLog("History journal append failed: \(error.localizedDescription)")
        }
    }

    func compact(_ records: [TranscriptionRecord]) {
        guard !persistenceBlocked else { return }
        do {
            try compactThrowing(records)
        } catch {
            NSLog("History persistence compaction failed: \(error.localizedDescription)")
        }
    }

    func remove() {
        guard !persistenceBlocked, fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            NSLog("History persistence cleanup failed: \(error.localizedDescription)")
        }
    }

    private func compactThrowing(_ records: [TranscriptionRecord]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for record in records {
            data.append(try JSONEncoder.historyJournal.encode(record))
            data.append(0x0A)
        }
        try AtomicFileWriter.write(data, to: fileURL, fileManager: fileManager)
    }

    private func preserveCorruptFile() -> Bool {
        let preserved = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(UUID().uuidString).\(fileURL.pathExtension)")
        do {
            try fileManager.moveItem(at: fileURL, to: preserved)
            return true
        } catch {
            NSLog("History corrupt-file preservation failed: \(error.localizedDescription)")
            return false
        }
    }
}

@MainActor
final class HotwordRepository: ObservableObject {
    @Published private(set) var hotwords: [Hotword] = []

    private let fileURL: URL
    private let fileManager: FileManager
    private var persistenceBlocked = false

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibingSpeech", isDirectory: true)
        fileURL = base.appendingPathComponent("hotwords.json")
        load()
    }

    @discardableResult
    func add(_ text: String) -> Bool {
        guard let hotword = Hotword(text: text) else { return false }
        guard !hotwords.contains(where: { $0.text.compare(hotword.text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            return false
        }
        hotwords.insert(hotword, at: 0)
        persist()
        return true
    }

    func delete(_ id: UUID) {
        delete(ids: [id])
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        hotwords.removeAll { ids.contains($0.id) }
        persist()
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            hotwords = try JSONDecoder.vibingSpeech.decode([Hotword].self, from: data)
        } catch {
            hotwords = []
            persistenceBlocked = !preserveCorruptFile()
        }
    }

    private func persist() {
        guard !persistenceBlocked else { return }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.vibingSpeech.encode(hotwords)
            try AtomicFileWriter.write(data, to: fileURL, fileManager: fileManager)
        } catch {
            NSLog("Hotword persistence failed: \(error.localizedDescription)")
        }
    }

    private func preserveCorruptFile() -> Bool {
        let preserved = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(UUID().uuidString).\(fileURL.pathExtension)")
        do {
            try fileManager.moveItem(at: fileURL, to: preserved)
            return true
        } catch {
            NSLog("Hotword corrupt-file preservation failed: \(error.localizedDescription)")
            return false
        }
    }
}

enum AtomicFileWriter {
    static func write(_ data: Data, to url: URL, fileManager: FileManager = .default) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }
}

extension JSONEncoder {
    static var vibingSpeech: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var historyJournal: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var vibingSpeech: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Data {
    var firstNonWhitespaceByte: UInt8? {
        first { !$0.isASCIIWhitespace }
    }

    func jsonLines() -> [Data] {
        var lines: [Data] = []
        for bytes in [UInt8](self).split(separator: 0x0A) {
            let line = Data(bytes)
            if line.contains(where: { !$0.isASCIIWhitespace }) {
                lines.append(line)
            }
        }
        return lines
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x09 || self == 0x0A || self == 0x0D || self == 0x20
    }
}

private extension HistoryRetention {
    func expirationDate(for timestamp: Date) -> Date? {
        switch self {
        case .oneWeek:
            Calendar.current.date(byAdding: .day, value: 7, to: timestamp)
        case .oneDay:
            Calendar.current.date(byAdding: .day, value: 1, to: timestamp)
        case .forever, .never:
            nil
        }
    }
}
