import AppKit
@preconcurrency import AVFoundation
import Carbon
import Foundation
import ServiceManagement

#if canImport(Qwen3ASR)
import AudioCommon
import Qwen3ASR
#endif

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(HuggingFace) && canImport(Tokenizers)
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

@MainActor
final class PermissionService: ObservableObject {
    @Published private(set) var microphoneGranted = false
    @Published private(set) var accessibilityGranted = false

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            microphoneGranted = false
        case .denied, .restricted:
            microphoneGranted = false
        @unknown default:
            microphoneGranted = false
        }
    }

    func requestMicrophoneIfNeeded() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            refresh()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum HotkeyServiceError: LocalizedError {
    case accessibilityMissing
    case eventTapCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityMissing:
            "Accessibility permission is required for the global hotkey."
        case .eventTapCreationFailed:
            "The global hotkey event tap could not be created."
        }
    }
}

final class HotkeyService {
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onAccessibilityFailure: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkey: RecordingHotkey = .rightOption
    private var longPressWorkItem: DispatchWorkItem?
    private var isModifierDown = false
    private var isHoldModeActive = false
    private var isToggleRecordingActive = false

    func start(hotkey: RecordingHotkey) throws {
        stop()
        guard AXIsProcessTrusted() else { throw HotkeyServiceError.accessibilityMissing }
        self.hotkey = hotkey

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyEventCallback,
            userInfo: pointer
        ) else {
            throw HotkeyServiceError.eventTapCreationFailed
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        isModifierDown = false
        isHoldModeActive = false
        isToggleRecordingActive = false
    }

    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            } else {
                onAccessibilityFailure?()
            }
            return
        }

        if type == .keyDown {
            if keyCode == kVK_Escape {
                cancelActiveRecording()
            }
            return
        }

        guard type == .flagsChanged else { return }
        guard keyCode == hotkey.keyCode else { return }

        let modifierIsDown = flags.contains(flagMask(for: hotkey))
        if modifierIsDown, !isModifierDown {
            modifierPressed()
        } else if !modifierIsDown, isModifierDown {
            modifierReleased()
        }
    }

    private func modifierPressed() {
        isModifierDown = true
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isModifierDown, !self.isToggleRecordingActive else { return }
            self.isHoldModeActive = true
            self.onStartRecording?()
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func modifierReleased() {
        isModifierDown = false
        longPressWorkItem?.cancel()
        longPressWorkItem = nil

        if isHoldModeActive {
            isHoldModeActive = false
            onStopRecording?()
            return
        }

        if isToggleRecordingActive {
            isToggleRecordingActive = false
            onStopRecording?()
        } else {
            isToggleRecordingActive = true
            onStartRecording?()
        }
    }

    private func cancelActiveRecording() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        isHoldModeActive = false
        isToggleRecordingActive = false
        isModifierDown = false
        onCancelRecording?()
    }

    private func flagMask(for hotkey: RecordingHotkey) -> CGEventFlags {
        switch hotkey {
        case .rightOption:
            return .maskAlternate
        case .leftControl:
            return .maskControl
        }
    }
}

private let hotkeyEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    service.handle(type: type, keyCode: keyCode, flags: flags)
    return Unmanaged.passUnretained(event)
}

enum MicrophoneRecorderError: LocalizedError {
    case inputUnavailable
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .inputUnavailable: "No microphone input is available."
        case .conversionFailed: "Audio could not be converted to 16 kHz mono Float32."
        }
    }
}

private final class MicrophoneAudioTap {
    private weak var recorder: MicrophoneRecorder?
    private let inputSampleRate: Double
    private let sessionID: UUID

    init(recorder: MicrophoneRecorder, inputSampleRate: Double, sessionID: UUID) {
        self.recorder = recorder
        self.inputSampleRate = inputSampleRate
        self.sessionID = sessionID
    }

    func makeBlock() -> AVAudioNodeTapBlock {
        { [weak self] buffer, _ in
            self?.process(buffer)
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let newSamples = MicrophoneRecorder.downmixedAndResampledSamples(from: buffer, inputSampleRate: inputSampleRate)
        let level = MicrophoneRecorder.rmsLevel(for: newSamples)
        Task { @MainActor [weak recorder, sessionID] in
            recorder?.ingest(samples: newSamples, level: level, sessionID: sessionID)
        }
    }
}

@MainActor
final class MicrophoneRecorder: ObservableObject {
    nonisolated static let minimumSamplesForASR = 800

    @Published private(set) var rmsLevel: Double = 0

    var onRMSLevel: ((Double) -> Void)?

    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private var sessionID = UUID()
    private var startTime: Date?
    private var inputTapInstalled = false
    private var audioTap: MicrophoneAudioTap?

    func availableInputDevices() -> [MicrophoneDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices.map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
        return [MicrophoneDevice.systemDefault] + devices
    }

    func start(selectedDeviceID: String) throws {
        cancel()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else { throw MicrophoneRecorderError.inputUnavailable }
        samples = []
        sessionID = UUID()
        startTime = Date()
        let activeSessionID = sessionID
        self.engine = engine
        let audioTap = MicrophoneAudioTap(
            recorder: self,
            inputSampleRate: inputFormat.sampleRate,
            sessionID: activeSessionID
        )
        self.audioTap = audioTap

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat, block: audioTap.makeBlock())
        inputTapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeInputTapIfNeeded()
            engine.stop()
            self.engine = nil
            self.audioTap = nil
            startTime = nil
            throw error
        }
    }

    func stop() -> (samples: [Float], duration: Double) {
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        removeInputTapIfNeeded()
        engine?.stop()
        engine = nil
        audioTap = nil
        startTime = nil
        let captured = samples
        samples = []
        sessionID = UUID()
        rmsLevel = 0
        onRMSLevel?(0)
        return (captured, duration)
    }

    func cancel() {
        removeInputTapIfNeeded()
        engine?.stop()
        engine = nil
        audioTap = nil
        samples = []
        startTime = nil
        sessionID = UUID()
        rmsLevel = 0
        onRMSLevel?(0)
    }

    private func removeInputTapIfNeeded() {
        guard inputTapInstalled, let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        inputTapInstalled = false
    }

    fileprivate func ingest(samples newSamples: [Float], level: Double, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        samples.append(contentsOf: newSamples)
        rmsLevel = level
        onRMSLevel?(level)
    }

    nonisolated fileprivate static func downmixedAndResampledSamples(from buffer: AVAudioPCMBuffer, inputSampleRate: Double) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        guard frameCount > 0 else { return [] }

        var mono = [Float]()
        mono.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            var value: Float = 0
            for channel in 0..<channelCount {
                value += channels[channel][frame]
            }
            mono.append(value / Float(channelCount))
        }

        guard inputSampleRate > 0, inputSampleRate != 16_000 else { return mono }
        let step = inputSampleRate / 16_000
        var position = 0.0
        var output = [Float]()
        output.reserveCapacity(Int(Double(frameCount) / step) + 1)
        while Int(position) < mono.count {
            output.append(mono[Int(position)])
            position += step
        }
        return output
    }

    nonisolated fileprivate static func rmsLevel(for samples: [Float]) -> Double {
        let count = samples.count
        guard count > 0 else { return 0 }
        let meanSquare = samples.reduce(0.0) { partial, value in
            partial + Double(value * value)
        } / Double(count)
        let noiseFloor = 0.005
        let adjustedRMS = max(0, sqrt(meanSquare) - noiseFloor)
        return min(1, adjustedRMS * 32)
    }
}

enum ASRServiceError: LocalizedError {
    case modelUnavailable
    case shortAudio
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Qwen3-ASR is not linked or could not be loaded."
        case .shortAudio:
            "The recording is too short to transcribe safely."
        case .emptyResult:
            "The model returned no text."
        }
    }
}

enum TextProcessingServiceError: LocalizedError {
    case modelUnavailable
    case emptyPrompt
    case emptyResult
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Qwen3 text processing is not linked or could not be loaded."
        case .emptyPrompt:
            "A custom text processing prompt is required."
        case .emptyResult:
            "The text processor returned no text."
        case .generationFailed(let reason):
            "Text processing failed: \(reason)"
        }
    }
}

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(HuggingFace) && canImport(Tokenizers)
private enum TextProcessingDownloaderError: LocalizedError {
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            "Invalid Hugging Face repository ID: '\(id)'. Expected format 'namespace/name'."
        }
    }
}

private struct TextProcessingHubDownloader: MLXLMCommon.Downloader {
    private let hubClient = HuggingFace.HubClient()

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = HuggingFace.Repo.ID(rawValue: id) else {
            throw TextProcessingDownloaderError.invalidRepositoryID(id)
        }
        return try await hubClient.downloadSnapshot(
            of: repoID,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in
                progressHandler(progress)
            }
        )
    }
}

private struct TextProcessingTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TextProcessingTokenizer(tokenizer)
    }
}

private struct TextProcessingTokenizer: MLXLMCommon.Tokenizer {
    private let tokenizer: any Tokenizers.Tokenizer

    init(_ tokenizer: any Tokenizers.Tokenizer) {
        self.tokenizer = tokenizer
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        tokenizer.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        tokenizer.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        tokenizer.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        tokenizer.convertIdToToken(id)
    }

    var bosToken: String? { tokenizer.bosToken }
    var eosToken: String? { tokenizer.eosToken }
    var unknownToken: String? { tokenizer.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try tokenizer.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
#endif

actor ASRService {
    private(set) var loadedVariant: ASRModelVariant?

    #if canImport(Qwen3ASR)
    private var model: Qwen3ASRModel?
    #endif

    func load(variant: ASRModelVariant) async throws {
        #if canImport(Qwen3ASR)
        if loadedVariant == variant, model != nil { return }
        model = try await Qwen3ASRModel.fromPretrained(modelId: variant.huggingFaceModelID)
        loadedVariant = variant
        #else
        loadedVariant = nil
        throw ASRServiceError.modelUnavailable
        #endif
    }

    func unload() {
        #if canImport(Qwen3ASR)
        model?.unload()
        model = nil
        #endif
        loadedVariant = nil
    }

    func transcribe(samples: [Float], languageMode: LanguageMode) async throws -> ASRResult {
        guard samples.count >= MicrophoneRecorder.minimumSamplesForASR else { throw ASRServiceError.shortAudio }
        #if canImport(Qwen3ASR)
        guard let model else { throw ASRServiceError.modelUnavailable }
        let languageHint = languageMode.asrLanguageHint
        let transcription = model.transcribeWithLanguage(audio: samples, sampleRate: 16_000, language: languageHint)
        let text = transcription.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ASRServiceError.emptyResult }
        return ASRResult(text: text, detectedLanguage: languageHint ?? transcription.language)
        #else
        throw ASRServiceError.modelUnavailable
        #endif
    }
}

actor TextProcessingBackend {
    #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(HuggingFace) && canImport(Tokenizers)
    private var modelContainer: ModelContainer?
    #endif

    func load() async throws {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(HuggingFace) && canImport(Tokenizers)
        if modelContainer != nil { return }
        let configuration = ModelConfiguration(id: TextProcessingService.modelIdentifier)
        modelContainer = try await LLMModelFactory.shared.loadContainer(
            from: TextProcessingHubDownloader(),
            using: TextProcessingTokenizerLoader(),
            configuration: configuration
        )
        #else
        throw TextProcessingServiceError.modelUnavailable
        #endif
    }

    func unload() {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(HuggingFace) && canImport(Tokenizers)
        modelContainer = nil
        Memory.clearCache()
        #endif
    }

    func process(_ text: String, systemPrompt: String) async throws -> String {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(HuggingFace) && canImport(Tokenizers)
        guard let modelContainer else { throw TextProcessingServiceError.modelUnavailable }
        let parameters = GenerateParameters(
            maxTokens: TextProcessingService.maxOutputTokens,
            temperature: 0.7,
            topP: 0.8,
            topK: 20,
            minP: 0
        )
        let output: String
        do {
            let session = ChatSession(
                modelContainer,
                instructions: systemPrompt,
                generateParameters: parameters
            )
            output = try await session.respond(to: text)
        } catch {
            throw TextProcessingServiceError.generationFailed(error.localizedDescription)
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TextProcessingServiceError.emptyResult }
        return trimmed
        #else
        throw TextProcessingServiceError.modelUnavailable
        #endif
    }
}

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = "VibingSpeech will open when you log in."
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Enable VibingSpeech in System Settings > General > Login Items."
        case .notRegistered:
            isEnabled = false
            statusMessage = "VibingSpeech will not open automatically."
        case .notFound:
            isEnabled = false
            statusMessage = "Login item registration is unavailable for this app bundle."
        @unknown default:
            isEnabled = false
            statusMessage = "Login item status is unavailable."
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }
}

@MainActor
final class TextProcessingService: ObservableObject {
    nonisolated static let modelIdentifier = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    nonisolated static let maxOutputTokens = 16_384

    @Published private(set) var isReady = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "Text processor unloaded"

    var onStateChange: (() -> Void)?

    private let backend = TextProcessingBackend()
    private var loadGeneration = UUID()
    private var enabled = false

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        loadGeneration = UUID()
        let generation = loadGeneration
        if enabled {
            Task { @MainActor in
                try? await loadIfNeeded(generation: generation)
            }
        } else {
            isLoading = false
            isReady = false
            statusMessage = "Text processor unloaded"
            Task {
                await backend.unload()
            }
            onStateChange?()
        }
    }

    func process(_ text: String, preset: TextProcessingPreset, customPrompt: String, language: LanguageMode, detectedLanguage: String?) async throws -> String {
        guard enabled else { throw TextProcessingServiceError.modelUnavailable }
        let systemPrompt = preset.systemPrompt(
            detectedLanguage: detectedLanguage,
            selectedLanguage: language,
            customPrompt: customPrompt
        )
        guard !systemPrompt.isEmpty else { throw TextProcessingServiceError.emptyPrompt }
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw TextProcessingServiceError.emptyResult }

        try await loadIfNeeded(generation: loadGeneration)
        return try await backend.process(input, systemPrompt: systemPrompt)
    }

    func unloadAfterIdle() async {
        loadGeneration = UUID()
        await backend.unload()
        isLoading = false
        isReady = false
        statusMessage = "Text processor unloaded after idle timeout"
        onStateChange?()
    }

    private func loadIfNeeded(generation: UUID) async throws {
        if isReady { return }
        isLoading = true
        statusMessage = "Loading text processor..."
        onStateChange?()
        do {
            try await backend.load()
            guard loadGeneration == generation, enabled else { return }
            isLoading = false
            isReady = true
            statusMessage = "Text processing ready"
            onStateChange?()
        } catch {
            guard loadGeneration == generation, enabled else { return }
            isLoading = false
            isReady = false
            statusMessage = error.localizedDescription
            onStateChange?()
            throw error
        }
    }
}

@MainActor
final class TextInsertionService {
    struct PasteboardSnapshot {
        let items: [NSPasteboardItem]
    }

    func snapshotPasteboard(_ pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let copiedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
        return PasteboardSnapshot(items: copiedItems)
    }

    func insert(_ text: String, pasteboard: NSPasteboard = .general) {
        let snapshot = snapshotPasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            self.restore(snapshot, ifPasteboardStillContains: text, pasteboard: pasteboard)
        }
    }

    func restore(_ snapshot: PasteboardSnapshot, ifPasteboardStillContains insertedText: String, pasteboard: NSPasteboard = .general) {
        guard pasteboard.string(forType: .string) == insertedText else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(snapshot.items)
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

@MainActor
final class SoundService {
    func playStart() {
        NSSound(named: "Pop")?.play()
    }

    func playStop() {
        NSSound(named: "Glass")?.play()
    }

    func playCancel() {
        NSSound(named: "Tink")?.play()
    }
}
