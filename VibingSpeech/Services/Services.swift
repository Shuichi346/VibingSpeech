import AppKit
import AudioToolbox
@preconcurrency import AVFoundation
import Carbon
import CoreAudio
import Foundation
import ServiceManagement
import TranscribeRuntime

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
    case audioUnitFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .inputUnavailable: "No microphone input is available."
        case .conversionFailed: "Audio could not be converted to 16 kHz mono Float32."
        case .selectedDeviceUnavailable:
            "The selected microphone is unavailable."
        case let .deviceSelectionFailed(status):
            "The selected microphone could not be activated. Core Audio status: \(status)."
        case let .audioUnitFailed(operation, status):
            "Microphone \(operation) failed. Core Audio status: \(status)."
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

    static func resolveDeviceID(_ selection: String) throws -> AudioDeviceID {
        if selection != MicrophoneDevice.systemDefault.id {
            guard let deviceID = audioDeviceID(for: selection) else {
                throw MicrophoneRecorderError.selectedDeviceUnavailable(selection)
            }
            return deviceID
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            throw MicrophoneRecorderError.inputUnavailable
        }
        return deviceID
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

/// Delivers converted recording batches to one asynchronous consumer in capture order.
/// Create this before `MicrophoneRecorder.start(selectedDeviceID:sampleDelivery:)`, then let
/// `MicrophoneRecorder.stop()` or `cancel()` close and drain it before stopping live ASR.
final class LiveSampleDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<[Float]>.Continuation
    private let consumer: Task<Void, Never>
    private var isClosed = false

    init(consume: @escaping @Sendable ([Float]) async -> Void) {
        var capturedContinuation: AsyncStream<[Float]>.Continuation?
        let stream = AsyncStream<[Float]> { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
        consumer = Task.detached {
            for await samples in stream {
                await consume(samples)
            }
        }
    }

    func enqueue(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        let canDeliver = !isClosed
        lock.unlock()
        guard canDeliver else { return }
        continuation.yield(samples)
    }

    func closeAndDrain() async {
        if closeSynchronously() {
            continuation.finish()
        }
        await consumer.value
    }

    deinit {
        continuation.finish()
    }

    private func closeSynchronously() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return false }
        isClosed = true
        return true
    }
}

private final class AudioConverterInputProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var inputBuffer: AVAudioPCMBuffer?

    init(inputBuffer: AVAudioPCMBuffer) {
        self.inputBuffer = inputBuffer
    }

    func takeInputBuffer() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        defer { inputBuffer = nil }
        return inputBuffer
    }
}

private final class MicrophoneAudioTap: @unchecked Sendable {
    private weak var recorder: MicrophoneRecorder?
    private let sessionID: UUID
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let sampleDelivery: LiveSampleDelivery?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var isClosed = false

    init?(
        recorder: MicrophoneRecorder,
        inputFormat: AVAudioFormat,
        sessionID: UUID,
        sampleDelivery: LiveSampleDelivery?
    ) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        self.recorder = recorder
        self.sessionID = sessionID
        self.converter = converter
        self.outputFormat = outputFormat
        self.sampleDelivery = sampleDelivery
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        let newSamples = convertedSamples(from: buffer)
        samples.append(contentsOf: newSamples)
        sampleDelivery?.enqueue(newSamples)
        let level = MicrophoneRecorder.rmsLevel(for: newSamples)
        Task { @MainActor [weak recorder, sessionID] in
            recorder?.updateRMSLevel(level, sessionID: sessionID)
        }
    }

    func finish() async -> [Float] {
        let capturedSamples = closeAndCaptureSynchronously()
        await sampleDelivery?.closeAndDrain()
        return capturedSamples
    }

    private func closeAndCaptureSynchronously() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return [] }
        isClosed = true
        let flushedSamples = flushConverter()
        samples.append(contentsOf: flushedSamples)
        sampleDelivery?.enqueue(flushedSamples)
        let capturedSamples = samples
        samples.removeAll(keepingCapacity: false)
        return capturedSamples
    }

    private func convertedSamples(from inputBuffer: AVAudioPCMBuffer) -> [Float] {
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(512, Int(ceil(Double(inputBuffer.frameLength) * ratio)) + 512))
        let inputProvider = AudioConverterInputProvider(inputBuffer: inputBuffer)
        var converted: [Float] = []

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                return converted
            }
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
                guard let input = inputProvider.takeInputBuffer() else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputStatus.pointee = .haveData
                return input
            }
            guard error == nil else { return converted }
            appendSamples(from: outputBuffer, to: &converted)
            guard status == .haveData, outputBuffer.frameLength > 0 else { break }
        }
        return converted
    }

    private func flushConverter() -> [Float] {
        var flushed: [Float] = []
        let capacity = AVAudioFrameCount(4_096)

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { break }
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard error == nil else { break }
            appendSamples(from: outputBuffer, to: &flushed)
            switch status {
            case .haveData:
                continue
            case .inputRanDry, .endOfStream, .error:
                break
            @unknown default:
                break
            }
            break
        }
        converter.reset()
        return flushed
    }

    private func appendSamples(from buffer: AVAudioPCMBuffer, to output: inout [Float]) {
        guard let channel = buffer.floatChannelData?.pointee else { return }
        output.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}

/// Owns an input-only AUHAL so Bluetooth playback cannot replace the selected microphone.
/// Configuration and teardown run on the recorder's actor; the C callback is nonisolated.
private final class MicrophoneInputUnit {
    let format: AVAudioFormat
    private var unit: AudioUnit?
    private let buffer: AVAudioPCMBuffer
    private var audioTap: MicrophoneAudioTap?

    init(deviceID: AudioDeviceID) throws {
        let configured = try Self.configure(deviceID: deviceID)
        unit = configured.unit
        format = configured.format
        buffer = configured.buffer
    }

    deinit { stop() }

    func start(audioTap: MicrophoneAudioTap) throws {
        guard let unit else { throw MicrophoneRecorderError.inputUnavailable }
        self.audioTap = audioTap
        var callback = AURenderCallbackStruct(
            inputProc: Self.inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try Self.check(AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
            &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        ), operation: "callback setup")
        try Self.check(AudioOutputUnitStart(unit), operation: "start")
    }

    func stop() {
        guard let unit else { return }
        // Stop and dispose the unit before releasing anything referenced by its callback.
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
        audioTap = nil
    }

    private static let inputCallback: AURenderCallback = { context, flags, timestamp, _, frameCount, _ in
        let capture = Unmanaged<MicrophoneInputUnit>.fromOpaque(context).takeUnretainedValue()
        guard let unit = capture.unit else { return kAudioUnitErr_Uninitialized }
        guard frameCount <= capture.buffer.frameCapacity else { return kAudioUnitErr_TooManyFramesToProcess }
        capture.buffer.frameLength = frameCount
        let status = AudioUnitRender(unit, flags, timestamp, 1, frameCount, capture.buffer.mutableAudioBufferList)
        if status == noErr {
            capture.audioTap?.process(capture.buffer)
        }
        return status
    }

    private static func configure(deviceID: AudioDeviceID) throws -> (
        unit: AudioUnit, format: AVAudioFormat, buffer: AVAudioPCMBuffer
    ) {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw MicrophoneRecorderError.inputUnavailable
        }
        var instance: AudioUnit?
        try check(AudioComponentInstanceNew(component, &instance), operation: "creation")
        guard let unit = instance else { throw MicrophoneRecorderError.inputUnavailable }
        do {
            var enabled: UInt32 = 1
            try check(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                &enabled, UInt32(MemoryLayout<UInt32>.size)
            ), operation: "input setup")
            enabled = 0
            try check(AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                &enabled, UInt32(MemoryLayout<UInt32>.size)
            ), operation: "output setup")
            var selectedDevice = deviceID
            let selectionStatus = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &selectedDevice, UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard selectionStatus == noErr else {
                throw MicrophoneRecorderError.deviceSelectionFailed(selectionStatus)
            }

            var hardwareFormat = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioUnitGetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardwareFormat, &size
            ), operation: "format lookup")
            guard hardwareFormat.mSampleRate > 0, hardwareFormat.mChannelsPerFrame > 0,
                  let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: hardwareFormat.mSampleRate,
                    channels: hardwareFormat.mChannelsPerFrame,
                    interleaved: false
                  ) else { throw MicrophoneRecorderError.inputUnavailable }
            var clientFormat = format.streamDescription.pointee
            try check(AudioUnitSetProperty(
                unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                &clientFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ), operation: "format setup")
            try check(AudioUnitInitialize(unit), operation: "initialization")
            var maximumFrames: UInt32 = 0
            size = UInt32(MemoryLayout<UInt32>.size)
            try check(AudioUnitGetProperty(
                unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                &maximumFrames, &size
            ), operation: "buffer size lookup")
            guard maximumFrames > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFrames)
            else { throw MicrophoneRecorderError.inputUnavailable }
            return (unit, format, buffer)
        } catch {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else { throw MicrophoneRecorderError.audioUnitFailed(operation, status) }
    }
}

@MainActor
final class MicrophoneRecorder: ObservableObject {
    nonisolated static let minimumSamplesForASR = 800

    @Published private(set) var rmsLevel: Double = 0

    var onRMSLevel: ((Double) -> Void)?
    private var inputUnit: MicrophoneInputUnit?
    private var sessionID = UUID()
    private var startTime: Date?
    private var audioTap: MicrophoneAudioTap?

    func availableInputDevices() -> [MicrophoneDevice] {
        let devices = CoreAudioInputDevices.availableDevices()
        return [MicrophoneDevice.systemDefault] + devices
    }

    func start(selectedDeviceID: String, sampleDelivery: LiveSampleDelivery? = nil) async throws {
        await cancel()
        do {
            let deviceID = try CoreAudioInputDevices.resolveDeviceID(selectedDeviceID)
            let inputUnit = try MicrophoneInputUnit(deviceID: deviceID)
            let activeSessionID = UUID()
            guard let audioTap = MicrophoneAudioTap(
                recorder: self,
                inputFormat: inputUnit.format,
                sessionID: activeSessionID,
                sampleDelivery: sampleDelivery
            ) else { throw MicrophoneRecorderError.conversionFailed }
            sessionID = activeSessionID
            startTime = Date()
            self.inputUnit = inputUnit
            self.audioTap = audioTap
            try inputUnit.start(audioTap: audioTap)
        } catch {
            await cancel()
            await sampleDelivery?.closeAndDrain()
            throw error
        }
    }

    func stop() async -> (samples: [Float], duration: Double) {
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        inputUnit?.stop()
        inputUnit = nil
        let captured = await audioTap?.finish() ?? []
        audioTap = nil
        startTime = nil
        sessionID = UUID()
        rmsLevel = 0
        onRMSLevel?(0)
        return (captured, duration)
    }

    func cancel() async {
        inputUnit?.stop()
        inputUnit = nil
        _ = await audioTap?.finish()
        audioTap = nil
        startTime = nil
        sessionID = UUID()
        rmsLevel = 0
        onRMSLevel?(0)
    }

    fileprivate func updateRMSLevel(_ level: Double, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        rmsLevel = level
        onRMSLevel?(level)
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
            "The speech recognition model could not be loaded."
        case .shortAudio:
            "The recording is too short to transcribe safely."
        case .emptyResult:
            "The model returned no text."
        }
    }
}

enum ASRContextBuilder {
    private static let maximumHotwordLength = 96
    private static let maximumContextLength = 512
    private static let prefix = "Vocabulary hints (use only when supported by the audio): "

    static func context(for hotwords: [String]) -> String {
        var seen = Set<String>()
        var terms: [String] = []
        var remainingLength = maximumContextLength - prefix.count

        for hotword in hotwords {
            let normalized = normalizedHotword(hotword)
            guard !normalized.isEmpty else { continue }
            let deduplicationKey = normalized.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seen.insert(deduplicationKey).inserted else { continue }

            let separatorLength = terms.isEmpty ? 0 : 2
            guard remainingLength > separatorLength else { break }
            let allowedLength = min(maximumHotwordLength, remainingLength - separatorLength)
            let capped = String(normalized.prefix(allowedLength))
            guard !capped.isEmpty else { break }
            terms.append(capped)
            remainingLength -= capped.count + separatorLength
        }

        guard !terms.isEmpty else { return "" }
        return prefix + terms.joined(separator: ", ")
    }

    private static func normalizedHotword(_ hotword: String) -> String {
        let collapsedWhitespace = hotword
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        let neutralizedControls = collapsedWhitespace
            .replacingOccurrences(of: "<|", with: "＜｜")
            .replacingOccurrences(of: "|>", with: "｜＞")
        return String(neutralizedControls.prefix(maximumHotwordLength))
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
            "Qwen3.5 text processing could not be loaded."
        case .emptyPrompt:
            "A custom text processing prompt is required."
        case .emptyResult:
            "The text processor returned no text."
        case .generationFailed(let reason):
            "Text processing failed: \(reason)"
        }
    }
}

actor ASRService {
    private(set) var loadedVariant: ASRModelVariant?
    private let native = GGUFTranscriber()
    private var loadRequestID = UUID()
    private var loadTask: (id: UUID, variant: ASRModelVariant, task: Task<Void, Error>)?
    private var unloadTask: Task<Void, Never>?
    private var inferenceRequestID = UUID()

    private let liveNative = GGUFStreamingTranscriber()
    private var liveModelLoaded = false
    private var liveLoadGeneration = UUID()
    private var liveLoadTask: (id: UUID, task: Task<Void, Error>)?
    private var liveSessionRequestID = UUID()
    private var liveSessionActive = false
    private var liveOnUpdate: (@Sendable (LiveTranscriptSnapshot) -> Void)?
    private var lastLiveSnapshot: LiveTranscriptSnapshot?

    func load(variant: ASRModelVariant) async throws {
        if loadedVariant == variant { return }
        if let pending = loadTask, pending.variant == variant {
            try await pending.task.value
            guard loadRequestID == pending.id else { throw CancellationError() }
            loadedVariant = variant
            return
        }
        let requestID = UUID()
        loadRequestID = requestID
        inferenceRequestID = UUID()
        loadedVariant = nil
        let previousUnload = unloadTask
        let previous = loadTask?.task
        previous?.cancel()
        let task = Task { [native] in
            _ = await previous?.result
            await previousUnload?.value
            try Task.checkCancellation()
            await self.finishLiveTranscription()
            try Task.checkCancellation()
            await native.unload()
            let url = try await GGUFCache.shared.download(model: GGUFModel(
                repository: variant.huggingFaceModelID, filename: variant.filename
            ))
            try Task.checkCancellation()
            try await native.load(modelURL: url)
            try Task.checkCancellation()
        }
        loadTask = (requestID, variant, task)
        do {
            try await task.value
            guard loadRequestID == requestID else { throw CancellationError() }
            loadTask = nil
            loadedVariant = variant
        } catch {
            if loadRequestID == requestID { loadTask = nil }
            throw error
        }
    }

    func unload() async {
        let requestID = UUID()
        loadRequestID = requestID
        inferenceRequestID = UUID()
        loadedVariant = nil
        let pending = loadTask?.task
        loadTask = nil
        pending?.cancel()
        let previousUnload = unloadTask
        let task = Task { [native] in
            await previousUnload?.value
            _ = await pending?.result
            await native.unload()
            await self.releaseLiveModels()
        }
        unloadTask = task
        await task.value
    }

    private func releaseLiveModels() async {
        await cancelLiveTranscription()
        await liveNative.unload()
        liveModelLoaded = false
    }

    func startLiveTranscription(
        languageMode: LanguageMode,
        onUpdate: @escaping @Sendable (LiveTranscriptSnapshot) -> Void
    ) async throws {
        let requestID = UUID()
        liveSessionRequestID = requestID
        liveSessionActive = false
        liveOnUpdate = nil
        await unloadTask?.value
        guard liveSessionRequestID == requestID else { throw CancellationError() }
        await liveNative.cancel()
        guard liveSessionRequestID == requestID else { throw CancellationError() }
        onUpdate(LiveTranscriptSnapshot(finalizedText: "", partialText: "", statusMessage: "Preparing Nemotron 3.5..."))
        try await loadLiveModelIfNeeded()
        guard liveSessionRequestID == requestID else { throw CancellationError() }
        try await liveNative.start(language: LiveASRModel.language(for: languageMode))
        guard liveSessionRequestID == requestID else { throw CancellationError() }
        liveSessionActive = true
        liveOnUpdate = onUpdate
        let initial = LiveTranscriptSnapshot(finalizedText: "", partialText: "", statusMessage: "Listening...")
        lastLiveSnapshot = initial
        onUpdate(initial)
    }

    private func loadLiveModelIfNeeded() async throws {
        if liveModelLoaded { return }
        if let pending = liveLoadTask {
            try await pending.task.value
            guard liveLoadGeneration == pending.id else { throw CancellationError() }
            liveModelLoaded = true
            return
        }
        let generation = UUID()
        liveLoadGeneration = generation
        let task = Task { [liveNative] in
            let url = try await GGUFCache.shared.download(model: GGUFModel(
                repository: LiveASRModel.huggingFaceModelID, filename: LiveASRModel.filename
            ))
            try Task.checkCancellation()
            try await liveNative.load(modelURL: url)
            try Task.checkCancellation()
        }
        liveLoadTask = (generation, task)
        do {
            try await task.value
            guard liveLoadGeneration == generation else { throw CancellationError() }
            liveLoadTask = nil
            liveModelLoaded = true
        } catch {
            if liveLoadTask?.id == generation { liveLoadTask = nil }
            throw error
        }
    }

    func ingestLiveSamples(_ samples: [Float]) async {
        guard liveSessionActive, !samples.isEmpty else { return }
        let requestID = liveSessionRequestID
        do {
            let snapshot = try await liveNative.feed(samples: samples)
            guard liveSessionRequestID == requestID, liveSessionActive else { return }
            publishLiveSnapshot(snapshot)
        } catch {
            guard liveSessionRequestID == requestID else { return }
            liveSessionActive = false
            liveOnUpdate?(LiveTranscriptSnapshot(
                finalizedText: lastLiveSnapshot?.finalizedText ?? "",
                partialText: lastLiveSnapshot?.partialText ?? "",
                statusMessage: "Live transcription unavailable: \(error.localizedDescription)"
            ))
            liveOnUpdate = nil
        }
    }

    func finishLiveTranscription() async {
        let requestID = UUID()
        liveSessionRequestID = requestID
        guard liveSessionActive else {
            await cancelLiveTranscription()
            return
        }
        liveSessionActive = false
        do {
            let snapshot = try await liveNative.finish()
            guard liveSessionRequestID == requestID else { return }
            publishLiveSnapshot(snapshot)
        } catch {
            // Final output always comes from the separate complete-recording ASR pass.
            guard liveSessionRequestID == requestID else { return }
            await liveNative.cancel()
        }
        guard liveSessionRequestID == requestID else { return }
        liveOnUpdate = nil
        lastLiveSnapshot = nil
    }

    func cancelLiveTranscription() async {
        liveSessionRequestID = UUID()
        liveSessionActive = false
        liveOnUpdate = nil
        lastLiveSnapshot = nil
        liveLoadGeneration = UUID()
        let pending = liveLoadTask?.task
        liveLoadTask = nil
        pending?.cancel()
        await liveNative.cancel()
        _ = await pending?.result
    }

    private func publishLiveSnapshot(_ nativeSnapshot: GGUFStreamSnapshot) {
        let snapshot = LiveTranscriptSnapshot(
            finalizedText: nativeSnapshot.committedText,
            partialText: nativeSnapshot.pendingText,
            statusMessage: nil
        )
        guard snapshot != lastLiveSnapshot else { return }
        lastLiveSnapshot = snapshot
        liveOnUpdate?(snapshot)
    }

    func cancelInference() async {
        inferenceRequestID = UUID()
        await native.cancelPendingTranscription()
    }

    func transcribe(
        samples: [Float],
        languageMode: LanguageMode,
        context: String = ""
    ) async throws -> ASRResult {
        guard samples.count >= MicrophoneRecorder.minimumSamplesForASR else { throw ASRServiceError.shortAudio }
        guard let variant = loadedVariant else { throw ASRServiceError.modelUnavailable }
        let requestID = UUID()
        inferenceRequestID = requestID
        await finishLiveTranscription()
        guard inferenceRequestID == requestID else { throw CancellationError() }
        let usesPrompt = variant == .qwen3_1_7b_8bit
        let result = try await native.transcribe(
            samples: samples,
            language: usesPrompt ? languageMode.asrLanguageHint : nil,
            context: usesPrompt ? context : ""
        )
        guard inferenceRequestID == requestID else { throw CancellationError() }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "<|nospeech|>" else { throw ASRServiceError.emptyResult }
        return ASRResult(text: text, detectedLanguage: result.language)
    }
}

actor TextProcessingBackend {
    private let server = LocalLlamaServer()
    private var generation = UUID()

    func load() async throws {
        let requestID = UUID()
        generation = requestID
        let url = try await GGUFCache.shared.download(model: GGUFModel(
            repository: TextProcessingService.modelIdentifier,
            filename: TextProcessingService.modelFilename
        ))
        try Task.checkCancellation()
        guard generation == requestID else { throw CancellationError() }
        try await server.start(modelURL: url, additionalArguments: [
            "--ctx-size", "32768", "--reasoning", "off", "--parallel", "1"
        ])
        guard generation == requestID else { throw CancellationError() }
    }

    func unload() async {
        generation = UUID()
        await server.stop()
    }

    func process(_ text: String, systemPrompt: String) async throws -> String {
        let requestID = generation
        let body = try JSONSerialization.data(withJSONObject: Self.requestBody(text: text, systemPrompt: systemPrompt))
        let data = try await server.request(path: "/v1/chat/completions", body: body)
        guard generation == requestID else { throw CancellationError() }
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let output = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else { throw TextProcessingServiceError.emptyResult }
        guard response.choices.first?.finish_reason != "length" else {
            throw TextProcessingServiceError.generationFailed("The response exceeded the output limit.")
        }
        return output
    }

    nonisolated static func requestBody(text: String, systemPrompt: String) -> [String: Any] {
        [
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": text]],
            "stream": false,
            "max_tokens": TextProcessingService.maxOutputTokens,
            "temperature": TextProcessingService.generationTemperature,
            "top_p": TextProcessingService.generationTopP,
            "top_k": TextProcessingService.generationTopK,
            "min_p": TextProcessingService.generationMinP,
            "repeat_penalty": TextProcessingService.generationRepetitionPenalty,
            "presence_penalty": TextProcessingService.generationPresencePenalty,
            "chat_template_kwargs": ["enable_thinking": false]
        ]
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: Message
            let finish_reason: String?
        }
        struct Message: Decodable { let content: String? }
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
    nonisolated static let modelIdentifier = "unsloth/Qwen3.5-2B-GGUF"
    nonisolated static let modelFilename = "Qwen3.5-2B-Q8_0.gguf"
    nonisolated static let maxOutputTokens = 16_384
    // Qwen3.5's recommended non-thinking sampling for text tasks.
    nonisolated static let generationTemperature: Float = 1
    nonisolated static let generationTopP: Float = 1
    nonisolated static let generationTopK = 20
    nonisolated static let generationMinP: Float = 0
    nonisolated static let generationPresencePenalty: Float = 2
    nonisolated static let generationRepetitionPenalty: Float = 1

    @Published private(set) var isReady = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "Text processor unloaded"

    var onStateChange: (() -> Void)?

    private let backend = TextProcessingBackend()
    private var loadTask: (id: UUID, task: Task<Void, Error>)?
    private var loadGeneration = UUID()
    private var enabled = false
    private var unloadTask: Task<Void, Never>?

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        loadGeneration = UUID()
        let generation = loadGeneration
        if enabled {
            Task { @MainActor in
                try? await loadIfNeeded(generation: generation)
            }
        } else {
            let pendingLoad = loadTask?.task
            pendingLoad?.cancel()
            loadTask = nil
            isLoading = false
            isReady = false
            statusMessage = "Text processor unloaded"
            let previousUnload = unloadTask
            unloadTask = Task { [backend] in
                await previousUnload?.value
                await backend.unload()
                _ = await pendingLoad?.result
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

        let generation = loadGeneration
        try await loadIfNeeded(generation: generation)
        guard enabled, loadGeneration == generation, isReady else { throw CancellationError() }
        return try await backend.process(input, systemPrompt: systemPrompt)
    }

    func unloadAfterIdle() async {
        await unload(status: "Text processor unloaded after idle timeout")
    }

    func cancelProcessing() async {
        await unload(status: "Text processor unloaded after cancellation")
    }

    private func unload(status: String) async {
        isReady = false
        isLoading = false
        loadGeneration = UUID()
        let generation = loadGeneration
        let pendingLoad = loadTask?.task
        pendingLoad?.cancel()
        loadTask = nil
        let previousUnload = unloadTask
        let task = Task { [backend] in
            await previousUnload?.value
            await backend.unload()
            _ = await pendingLoad?.result
        }
        unloadTask = task
        await task.value
        guard loadGeneration == generation else { return }
        isLoading = false
        isReady = false
        statusMessage = status
        onStateChange?()
    }

    private func loadIfNeeded(generation: UUID) async throws {
        await unloadTask?.value
        guard loadGeneration == generation, enabled else { throw CancellationError() }
        if isReady { return }
        if let loadTask {
            try await loadTask.task.value
            guard loadGeneration == generation, enabled else {
                if !enabled {
                    await backend.unload()
                }
                throw CancellationError()
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
                throw CancellationError()
            }
            isLoading = false
            isReady = true
            statusMessage = "Text processing ready"
            onStateChange?()
        } catch {
            if loadTask?.id == taskID {
                loadTask = nil
            }
            guard loadGeneration == generation, enabled else { throw CancellationError() }
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
