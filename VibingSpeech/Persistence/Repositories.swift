import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var recordingHotkey: RecordingHotkey { didSet { save() } }
    @Published var liveTranscriptionEnabled: Bool { didSet { save() } }
    @Published var textProcessingEnabled: Bool { didSet { save() } }
    @Published var textProcessingPreset: TextProcessingPreset { didSet { save() } }
    @Published var customPrompt: String { didSet { save() } }
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

    private let fileURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibingSpeech", isDirectory: true)
        fileURL = base.appendingPathComponent("history.json")
        load()
    }

    func add(_ record: TranscriptionRecord, retention: HistoryRetention) {
        guard retention != .never else {
            records = []
            removePersistedFile()
            return
        }
        records.insert(record, at: 0)
        pruneIfNeeded(retention: retention)
        persist()
    }

    func applyRetention(_ retention: HistoryRetention) {
        switch retention {
        case .forever:
            return
        case .never:
            records = []
            removePersistedFile()
        case .oneWeek, .oneDay:
            let originalCount = records.count
            pruneIfNeeded(retention: retention)
            if records.count != originalCount {
                persist()
            }
        }
    }

    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        records = []
        persist()
    }

    func pruneIfNeeded(retention: HistoryRetention) {
        guard let cutoff = retention.cutoffDate else { return }
        records = records.filter { $0.timestamp >= cutoff }
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder.vibingSpeech.decode([TranscriptionRecord].self, from: data)
        } catch {
            preserveCorruptFile()
            records = []
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.vibingSpeech.encode(records)
            try AtomicFileWriter.write(data, to: fileURL, fileManager: fileManager)
        } catch {
            NSLog("History persistence failed: \(error.localizedDescription)")
        }
    }

    private func preserveCorruptFile() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let preserved = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(formatter.string(from: Date())).json")
        try? fileManager.moveItem(at: fileURL, to: preserved)
    }

    private func removePersistedFile() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            NSLog("History persistence cleanup failed: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class HotwordRepository: ObservableObject {
    @Published private(set) var hotwords: [Hotword] = []

    private let fileURL: URL
    private let fileManager: FileManager

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
        hotwords.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            hotwords = try JSONDecoder.vibingSpeech.decode([Hotword].self, from: data)
        } catch {
            hotwords = []
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.vibingSpeech.encode(hotwords)
            try AtomicFileWriter.write(data, to: fileURL, fileManager: fileManager)
        } catch {
            NSLog("Hotword persistence failed: \(error.localizedDescription)")
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
}

extension JSONDecoder {
    static var vibingSpeech: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
