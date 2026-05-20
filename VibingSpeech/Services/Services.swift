import AppKit
@preconcurrency import AVFoundation
import Carbon
import Foundation
import ServiceManagement

#if canImport(Qwen3ASR)
import AudioCommon
import Qwen3ASR
#endif

#if canImport(Qwen3Chat)
import MLX
import Qwen3Chat
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
    case incompatibleModelConfig(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Qwen3.5 text processing is not linked or could not be loaded."
        case .emptyPrompt:
            "A custom text processing prompt is required."
        case .emptyResult:
            "The text processor returned no text."
        case .incompatibleModelConfig(let reason):
            "Text processor model files are not compatible: \(reason)"
        case .generationFailed(let reason):
            "Text processing failed: \(reason)"
        }
    }
}

enum TextProcessingModelDirectory {
    static func prepare(from sourceDirectory: URL) throws -> URL {
        let configURL = sourceDirectory.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)
        let tokenizerURL = sourceDirectory.appendingPathComponent("tokenizer.json")
        let tokenizerData = try? Data(contentsOf: tokenizerURL)

        guard let normalizedConfigData = try normalizedConfigData(from: configData, tokenizerData: tokenizerData) else {
            return sourceDirectory
        }

        let runtimeDirectory = sourceDirectory.appendingPathComponent(".vibingspeech-text-runtime", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try normalizedConfigData.write(to: runtimeDirectory.appendingPathComponent("config.json"), options: .atomic)

        for fileName in ["tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt"] {
            let sourceURL = sourceDirectory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            try refreshLink(from: sourceURL, to: runtimeDirectory.appendingPathComponent(fileName))
        }

        let sourceFiles = try fileManager.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
        for sourceURL in sourceFiles where sourceURL.pathExtension == "safetensors" {
            try refreshLink(from: sourceURL, to: runtimeDirectory.appendingPathComponent(sourceURL.lastPathComponent))
        }

        return runtimeDirectory
    }

    static func normalizedConfigData(from configData: Data, tokenizerData: Data? = nil) throws -> Data? {
        guard let root = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw TextProcessingServiceError.incompatibleModelConfig("config.json is not a JSON object")
        }
        if root["hidden_size"] != nil {
            return nil
        }
        guard let textConfig = root["text_config"] as? [String: Any] else {
            throw TextProcessingServiceError.incompatibleModelConfig("config.json has no text_config section")
        }

        let ropeParameters = textConfig["rope_parameters"] as? [String: Any] ?? [:]
        var normalized: [String: Any] = [
            "hidden_size": try requiredInt(textConfig, "hidden_size"),
            "num_hidden_layers": try requiredInt(textConfig, "num_hidden_layers"),
            "num_attention_heads": try requiredInt(textConfig, "num_attention_heads"),
            "num_key_value_heads": try requiredInt(textConfig, "num_key_value_heads"),
            "head_dim": try requiredInt(textConfig, "head_dim"),
            "intermediate_size": try requiredInt(textConfig, "intermediate_size"),
            "vocab_size": try requiredInt(textConfig, "vocab_size"),
            "max_seq_len": optionalInt(textConfig, "max_seq_len") ?? optionalInt(textConfig, "max_position_embeddings") ?? 2048,
            "rope_theta": optionalDouble(textConfig, "rope_theta") ?? optionalDouble(ropeParameters, "rope_theta") ?? 10_000_000.0,
            "rms_norm_eps": try requiredDouble(textConfig, "rms_norm_eps"),
            "eos_token_id": specialTokenID("<|im_end|>", in: tokenizerData) ?? optionalInt(textConfig, "eos_token_id") ?? 248046,
            "pad_token_id": specialTokenID("<|endoftext|>", in: tokenizerData) ?? optionalInt(textConfig, "pad_token_id") ?? 248044,
            "quantization": quantizationName(from: root["quantization"] ?? textConfig["quantization"]),
            "model_type": "qwen3_5_text"
        ]

        for key in [
            "layer_types",
            "full_attention_interval",
            "linear_num_key_heads",
            "linear_key_head_dim",
            "linear_num_value_heads",
            "linear_value_head_dim",
            "linear_conv_kernel_dim",
            "tie_word_embeddings"
        ] {
            if let value = textConfig[key] {
                normalized[key] = value
            }
        }
        normalized["partial_rotary_factor"] = optionalDouble(textConfig, "partial_rotary_factor")
            ?? optionalDouble(ropeParameters, "partial_rotary_factor")

        try validateSupportedQwen3ChatConfig(normalized)

        return try JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])
    }

    private static func refreshLink(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        do {
            try fileManager.linkItem(at: sourceURL, to: destinationURL)
        } catch {
            try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
        }
    }

    private static func requiredInt(_ dictionary: [String: Any], _ key: String) throws -> Int {
        guard let value = optionalInt(dictionary, key) else {
            throw TextProcessingServiceError.incompatibleModelConfig("config key \(key) is missing")
        }
        return value
    }

    private static func optionalInt(_ dictionary: [String: Any], _ key: String) -> Int? {
        if let value = dictionary[key] as? Int { return value }
        if let value = dictionary[key] as? NSNumber { return value.intValue }
        return nil
    }

    private static func requiredDouble(_ dictionary: [String: Any], _ key: String) throws -> Double {
        guard let value = optionalDouble(dictionary, key) else {
            throw TextProcessingServiceError.incompatibleModelConfig("config key \(key) is missing")
        }
        return value
    }

    private static func optionalDouble(_ dictionary: [String: Any], _ key: String) -> Double? {
        if let value = dictionary[key] as? Double { return value }
        if let value = dictionary[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func quantizationName(from value: Any?) -> String {
        if let value = value as? String {
            return value
        }
        guard let dictionary = value as? [String: Any],
              let bits = optionalInt(dictionary, "bits") else {
            return "int4"
        }
        return "int\(bits)"
    }

    private static func specialTokenID(_ token: String, in tokenizerData: Data?) -> Int? {
        guard let tokenizerData,
              let root = try? JSONSerialization.jsonObject(with: tokenizerData) as? [String: Any],
              let addedTokens = root["added_tokens"] as? [[String: Any]] else {
            return nil
        }
        return addedTokens.first { $0["content"] as? String == token }?["id"] as? Int
    }

    private static func validateSupportedQwen3ChatConfig(_ config: [String: Any]) throws {
        guard (config["model_type"] as? String) == "qwen3_5_text" else { return }
        guard let layerTypes = config["layer_types"] as? [String],
              layerTypes.contains("linear_attention") else {
            return
        }

        let hiddenSize = try requiredInt(config, "hidden_size")
        let linearKeyHeads = optionalInt(config, "linear_num_key_heads") ?? 16
        let linearKeyHeadDim = optionalInt(config, "linear_key_head_dim") ?? 128
        let linearValueHeads = optionalInt(config, "linear_num_value_heads") ?? linearKeyHeads
        let linearValueHeadDim = optionalInt(config, "linear_value_head_dim") ?? linearKeyHeadDim

        let supportedDeltaNetLayout = linearKeyHeads == linearValueHeads
            && linearKeyHeads * linearKeyHeadDim == hiddenSize * 2
            && linearValueHeads * linearValueHeadDim == hiddenSize * 2

        guard supportedDeltaNetLayout else {
            throw TextProcessingServiceError.incompatibleModelConfig(
                "Qwen3Chat currently supports the 0.8B DeltaNet layout; this model uses hidden_size=\(hiddenSize), linear_num_key_heads=\(linearKeyHeads), linear_key_head_dim=\(linearKeyHeadDim), linear_num_value_heads=\(linearValueHeads), linear_value_head_dim=\(linearValueHeadDim)."
            )
        }
    }
}

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
    #if canImport(Qwen3Chat)
    private var chat: Qwen35MLXChat?
    #endif

    func load() async throws {
        #if canImport(Qwen3Chat)
        if chat?.isLoaded == true { return }
        let cacheDirectory = try HuggingFaceDownloader.getCacheDirectory(for: TextProcessingService.modelIdentifier)
        try await HuggingFaceDownloader.downloadWeights(
            modelId: TextProcessingService.modelIdentifier,
            to: cacheDirectory,
            additionalFiles: [
                "chat_template.jinja",
                "tokenizer.json",
                "tokenizer_config.json",
                "vocab.json"
            ]
        )
        let modelDirectory = try TextProcessingModelDirectory.prepare(from: cacheDirectory)
        chat = try await Qwen35MLXChat.fromLocal(directory: modelDirectory)
        #else
        throw TextProcessingServiceError.modelUnavailable
        #endif
    }

    func unload() {
        #if canImport(Qwen3Chat)
        chat?.unload()
        chat = nil
        #endif
    }

    func process(_ text: String, systemPrompt: String) async throws -> String {
        #if canImport(Qwen3Chat)
        guard let chat, chat.isLoaded else { throw TextProcessingServiceError.modelUnavailable }
        let sampling = ChatSamplingConfig(
            temperature: 0.7,
            topK: 20,
            topP: 0.8,
            maxTokens: 512,
            repetitionPenalty: 1.0
        )
        let output: String
        do {
            output = try MLX.withError { error in
                let generated = try chat.generate(
                    messages: [
                        ChatMessage(role: .system, content: systemPrompt),
                        ChatMessage(role: .user, content: text)
                    ],
                    sampling: sampling
                )
                try error.check()
                return generated
            }
        } catch {
            throw TextProcessingServiceError.generationFailed(error.localizedDescription)
        }
        let stripped = TextProcessingService.stripThinkingBlocks(from: output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { throw TextProcessingServiceError.emptyResult }
        return stripped
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
    nonisolated static let modelIdentifier = "mlx-community/Qwen3.5-4B-MLX-4bit"

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

    nonisolated static func stripThinkingBlocks(from text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>", options: [.caseInsensitive]),
              let end = result.range(of: "</think>", options: [.caseInsensitive], range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result
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
