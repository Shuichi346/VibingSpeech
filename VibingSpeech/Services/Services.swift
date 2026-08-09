import AppKit
import AudioToolbox
@preconcurrency import AVFoundation
import Carbon
import CoreAudio
import Foundation
import ServiceManagement

#if canImport(MLX)
import MLX
#endif

#if canImport(MLXAudioSTT)
import MLXAudioSTT
#endif

#if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(HuggingFace) && canImport(Tokenizers)
import HuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

@MainActor
final class AppearanceService {
    func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

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
    case selectedDeviceUnavailable(String)
    case deviceSelectionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .inputUnavailable: "No microphone input is available."
        case .conversionFailed: "Audio could not be converted to 16 kHz mono Float32."
        case .selectedDeviceUnavailable:
            "The selected microphone is unavailable."
        case let .deviceSelectionFailed(status):
            "The selected microphone could not be activated. Core Audio status: \(status)."
        }
    }
}

private enum CoreAudioInputDevices {
    static func availableDevices() -> [MicrophoneDevice] {
        allInputDevices().map { MicrophoneDevice(id: $0.uid, name: $0.name) }
    }

    static func audioDeviceID(for uid: String) -> AudioDeviceID? {
        allInputDevices().first { $0.uid == uid }?.id
    }

    private static func allInputDevices() -> [(id: AudioDeviceID, uid: String, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return [] }

        var deviceIDs = Array(repeating: AudioDeviceID(), count: deviceCount)
        let status = deviceIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(kAudioHardwareUnspecifiedError) }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasInputChannels(deviceID),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID),
                  let name = stringProperty(kAudioObjectPropertyName, for: deviceID)
            else {
                return nil
            }
            return (id: deviceID, uid: uid, name: name)
        }
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else {
            return false
        }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawBufferList) == noErr else {
            return false
        }

        let bufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(bufferList)
            .contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { return nil }
        return value as String
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
    var onSamples: (([Float]) -> Void)?

    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private var sessionID = UUID()
    private var startTime: Date?
    private var inputTapInstalled = false
    private var audioTap: MicrophoneAudioTap?

    func availableInputDevices() -> [MicrophoneDevice] {
        let devices = CoreAudioInputDevices.availableDevices()
        return [MicrophoneDevice.systemDefault] + devices
    }

    func start(selectedDeviceID: String) throws {
        cancel()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try activateSelectedInputDevice(selectedDeviceID, on: input)
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
        onSamples = nil
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
        onSamples = nil
    }

    private func removeInputTapIfNeeded() {
        guard inputTapInstalled, let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        inputTapInstalled = false
    }

    private func activateSelectedInputDevice(_ selectedDeviceID: String, on input: AVAudioInputNode) throws {
        guard selectedDeviceID != MicrophoneDevice.systemDefault.id else { return }
        guard var audioDeviceID = CoreAudioInputDevices.audioDeviceID(for: selectedDeviceID) else {
            throw MicrophoneRecorderError.selectedDeviceUnavailable(selectedDeviceID)
        }
        guard let audioUnit = input.audioUnit else {
            throw MicrophoneRecorderError.inputUnavailable
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &audioDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw MicrophoneRecorderError.deviceSelectionFailed(status)
        }
    }

    fileprivate func ingest(samples newSamples: [Float], level: Double, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        samples.append(contentsOf: newSamples)
        rmsLevel = level
        onRMSLevel?(level)
        onSamples?(newSamples)
    }

    nonisolated fileprivate static func downmixedAndResampledSamples(from buffer: AVAudioPCMBuffer, inputSampleRate: Double) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        guard frameCount > 0 else { return [] }

        func monoSample(at frame: Int) -> Float {
            var value: Float = 0
            for channel in 0..<channelCount {
                value += channels[channel][frame]
            }
            return value / Float(channelCount)
        }

        guard inputSampleRate > 0 else { return [] }
        guard inputSampleRate != 16_000 else {
            var mono = [Float]()
            mono.reserveCapacity(frameCount)
            for frame in 0..<frameCount {
                mono.append(monoSample(at: frame))
            }
            return mono
        }

        let step = inputSampleRate / 16_000
        var position = 0.0
        var output = [Float]()
        output.reserveCapacity(Int(Double(frameCount) / step) + 1)
        while Int(position) < frameCount {
            output.append(monoSample(at: Int(position)))
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
            "Qwen3.5 text processing is not linked or could not be loaded."
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

#if canImport(MLX) && canImport(MLXAudioSTT)
private final class LiveASRSession: @unchecked Sendable {
    private let session: StreamingInferenceSession
    private let eventConsumer: Task<Void, Never>

    init(
        model: Qwen3ASRModel,
        languageHint: String?,
        onUpdate: @escaping @Sendable (LiveTranscriptSnapshot) -> Void
    ) {
        let session = StreamingInferenceSession(
            model: model,
            config: StreamingConfig(language: languageHint)
        )
        self.session = session
        onUpdate(LiveTranscriptSnapshot(finalizedText: "", partialText: "", statusMessage: "Listening..."))
        eventConsumer = Task {
            for await event in session.events {
                Self.handle(event, onUpdate: onUpdate)
            }
        }
    }

    func ingest(samples: [Float]) {
        guard !samples.isEmpty else { return }
        session.feedAudio(samples: samples)
    }

    func finish() async {
        session.stop()
        await eventConsumer.value
    }

    private static func handle(
        _ event: TranscriptionEvent,
        onUpdate: @escaping @Sendable (LiveTranscriptSnapshot) -> Void
    ) {
        switch event {
        case .displayUpdate(let confirmedText, let provisionalText):
            onUpdate(LiveTranscriptSnapshot(
                finalizedText: confirmedText,
                partialText: provisionalText,
                statusMessage: nil
            ))
        case .confirmed(let text):
            onUpdate(LiveTranscriptSnapshot(finalizedText: text, partialText: "", statusMessage: nil))
        case .provisional(let text):
            onUpdate(LiveTranscriptSnapshot(finalizedText: "", partialText: text, statusMessage: nil))
        case .ended(let fullText):
            onUpdate(LiveTranscriptSnapshot(finalizedText: fullText, partialText: "", statusMessage: nil))
        case .stats:
            break
        }
    }
}
#endif

actor ASRService {
    private(set) var loadedVariant: ASRModelVariant?
    private var loadRequestID = UUID()

    #if canImport(MLX) && canImport(MLXAudioSTT)
    private var model: Qwen3ASRModel?
    #endif

    #if canImport(MLX) && canImport(MLXAudioSTT)
    private var liveSession: LiveASRSession?
    private var liveSessionRequestID = UUID()
    #endif

    func load(variant: ASRModelVariant) async throws {
        #if canImport(MLX) && canImport(MLXAudioSTT)
        if loadedVariant == variant, model != nil { return }
        let requestID = UUID()
        loadRequestID = requestID
        liveSessionRequestID = UUID()
        await unloadLoadedModels()
        var loadedModel: Qwen3ASRModel? = try await Qwen3ASRModel.fromPretrained(variant.huggingFaceModelID)
        guard loadRequestID == requestID else {
            loadedModel = nil
            MLX.Memory.clearCache()
            return
        }
        model = loadedModel
        loadedModel = nil
        loadedVariant = variant
        #else
        loadedVariant = nil
        throw ASRServiceError.modelUnavailable
        #endif
    }

    func unload() async {
        loadRequestID = UUID()
        #if canImport(MLX) && canImport(MLXAudioSTT)
        liveSessionRequestID = UUID()
        #endif
        await unloadLoadedModels()
    }

    private func unloadLoadedModels() async {
        #if canImport(MLX) && canImport(MLXAudioSTT)
        let sessionToFinish = liveSession
        model = nil
        if let sessionToFinish {
            await sessionToFinish.finish()
            if liveSession === sessionToFinish {
                liveSession = nil
            }
        }
        MLX.Memory.clearCache()
        #endif
        loadedVariant = nil
    }

    func startLiveTranscription(
        languageMode: LanguageMode,
        onUpdate: @escaping @Sendable (LiveTranscriptSnapshot) -> Void
    ) async throws {
        #if canImport(MLX) && canImport(MLXAudioSTT)
        let requestID = UUID()
        liveSessionRequestID = requestID
        guard let model else { throw ASRServiceError.modelUnavailable }
        if let sessionToFinish = liveSession {
            await sessionToFinish.finish()
            guard liveSessionRequestID == requestID else { throw CancellationError() }
            if liveSession === sessionToFinish {
                liveSession = nil
            } else if liveSession != nil {
                throw CancellationError()
            }
        }
        guard liveSessionRequestID == requestID else { throw CancellationError() }
        liveSession = LiveASRSession(
            model: model,
            languageHint: languageMode.asrLanguageHint,
            onUpdate: onUpdate
        )
        #else
        throw ASRServiceError.modelUnavailable
        #endif
    }

    func ingestLiveSamples(_ samples: [Float]) {
        #if canImport(MLX) && canImport(MLXAudioSTT)
        liveSession?.ingest(samples: samples)
        #endif
    }

    func finishLiveTranscription() async {
        #if canImport(MLX) && canImport(MLXAudioSTT)
        liveSessionRequestID = UUID()
        if let sessionToFinish = liveSession {
            await sessionToFinish.finish()
            if liveSession === sessionToFinish {
                liveSession = nil
            }
        }
        #endif
    }

    func cancelLiveTranscription() async {
        #if canImport(MLX) && canImport(MLXAudioSTT)
        liveSessionRequestID = UUID()
        if let sessionToFinish = liveSession {
            await sessionToFinish.finish()
            if liveSession === sessionToFinish {
                liveSession = nil
            }
        }
        #endif
    }

    func transcribe(samples: [Float], languageMode: LanguageMode) async throws -> ASRResult {
        guard samples.count >= MicrophoneRecorder.minimumSamplesForASR else { throw ASRServiceError.shortAudio }
        #if canImport(MLX) && canImport(MLXAudioSTT)
        guard let model else { throw ASRServiceError.modelUnavailable }
        let languageHint = languageMode.asrLanguageHint
        let transcription = model.generate(audio: MLXArray(samples), language: languageHint)
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
            temperature: TextProcessingService.generationTemperature,
            topP: TextProcessingService.generationTopP,
            topK: TextProcessingService.generationTopK,
            minP: TextProcessingService.generationMinP,
            repetitionPenalty: TextProcessingService.generationRepetitionPenalty,
            presencePenalty: TextProcessingService.generationPresencePenalty
        )
        let output: String
        do {
            let session = ChatSession(
                modelContainer,
                instructions: systemPrompt,
                generateParameters: parameters,
                additionalContext: TextProcessingService.chatTemplateContext
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
    nonisolated static let modelIdentifier = "mlx-community/Qwen3.5-4B-MLX-4bit"
    nonisolated static let maxOutputTokens = 16_384
    nonisolated static let generationTemperature: Float = 0.7
    nonisolated static let generationTopP: Float = 0.8
    nonisolated static let generationTopK = 20
    nonisolated static let generationMinP: Float = 0
    nonisolated static let generationPresencePenalty: Float = 1.5
    nonisolated static let generationRepetitionPenalty: Float = 1
    nonisolated static let chatTemplateContext: [String: any Sendable] = ["enable_thinking": false]

    @Published private(set) var isReady = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "Text processor unloaded"

    var onStateChange: (() -> Void)?

    private let backend = TextProcessingBackend()
    private var loadTask: (id: UUID, task: Task<Void, Error>)?
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
            loadTask?.task.cancel()
            loadTask = nil
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
        loadTask?.task.cancel()
        loadTask = nil
        await backend.unload()
        isLoading = false
        isReady = false
        statusMessage = "Text processor unloaded after idle timeout"
        onStateChange?()
    }

    private func loadIfNeeded(generation: UUID) async throws {
        if isReady { return }
        if let loadTask {
            try await loadTask.task.value
            guard loadGeneration == generation, enabled else {
                if !enabled {
                    await backend.unload()
                }
                return
            }
            return
        }

        isLoading = true
        statusMessage = "Loading text processor..."
        onStateChange?()
        let taskID = UUID()
        let task = Task { [backend] in
            try await backend.load()
        }
        loadTask = (taskID, task)
        do {
            try await task.value
            if loadTask?.id == taskID {
                loadTask = nil
            }
            guard loadGeneration == generation, enabled else {
                if !enabled {
                    await backend.unload()
                }
                return
            }
            isLoading = false
            isReady = true
            statusMessage = "Text processing ready"
            onStateChange?()
        } catch {
            if loadTask?.id == taskID {
                loadTask = nil
            }
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
