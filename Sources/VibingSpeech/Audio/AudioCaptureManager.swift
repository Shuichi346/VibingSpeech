//  AudioCaptureManager.swift
//  VibingSpeech

@preconcurrency import AVFoundation
import CoreAudio
import Observation

@Observable final class AudioCaptureManager: @unchecked Sendable {
    private(set) var isRecording = false
    @MainActor private(set) var audioLevel: Float = 0.0
    private var audioBuffer: [Float] = []
    private let targetSampleRate: Double = 16000.0
    private let lock = NSLock()

    /// 録音セッションごとにインクリメントする世代カウンター。
    /// tap コールバック内で自分が現役セッションかどうかを判定するために使う。
    private var sessionGeneration: UInt64 = 0

    /// 録音の開始・停止・キャンセルを直列化するためのシリアルキュー。
    /// AVAudioEngine の操作が同時に走ることを防ぐ。
    private let engineQueue = DispatchQueue(
        label: "com.vibingspeech.audioengine", qos: .userInteractive)

    /// 現在の録音セッションで使用中の AVAudioEngine。
    /// 録音ごとに新規生成し、停止時に破棄する。
    private var audioEngine: AVAudioEngine?
    private var hasInstalledTap = false

    /// ASR の WhisperFeatureExtractor が安全に処理できる最小サンプル数。
    /// nFFT(400) + hopLength(160) 以上のサンプルが必要。余裕を持って 800 サンプル(50ms)を閾値にする。
    static let minimumSamplesForASR = 800

    init() {}

    func startRecording(microphoneID: String?) throws {
        try engineQueue.sync {
            try self._startRecording(microphoneID: microphoneID)
        }
    }

    func stopRecording() -> [Float] {
        return engineQueue.sync {
            self._stopRecording()
        }
    }

    func cancelRecording() {
        engineQueue.sync {
            self._cancelRecording()
        }
    }

    // MARK: - 内部実装（すべて engineQueue 上で実行される）

    private func _startRecording(microphoneID: String?) throws {
        // 前回のセッションが残っていれば確実にクリーンアップする
        _teardownEngine()

        sessionGeneration &+= 1
        let currentGeneration = sessionGeneration

        lock.lock()
        audioBuffer.removeAll()
        lock.unlock()

        // 録音ごとに新しい AVAudioEngine を生成する。
        // 使い回しによるライフサイクル競合を根本的に排除する。
        let engine = AVAudioEngine()
        self.audioEngine = engine

        try configureInputDevice(engine: engine, microphoneID: microphoneID)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            self.audioEngine = nil
            throw NSError(
                domain: "AudioCaptureManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create output audio format"])
        }

        // converter を tap クロージャにキャプチャするローカル変数として生成する。
        // self のプロパティとして共有しないことで、古い tap コールバックが
        // 新しいセッション用の converter を掴む問題を根本的に排除する。
        guard let localConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            self.audioEngine = nil
            throw NSError(
                domain: "AudioCaptureManager", code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }

        let targetSampleRate = self.targetSampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            // 自分が現役セッションでなければ即座にリターンする
            guard self.sessionGeneration == currentGeneration else { return }

            let capacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetSampleRate / inputFormat.sampleRate
            )
            guard capacity > 0 else { return }
            guard
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: capacity
                )
            else { return }

            var error: NSError?
            var inputConsumed = false
            localConverter.convert(to: convertedBuffer, error: &error) { _, status in
                if inputConsumed {
                    status.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                status.pointee = .haveData
                return buffer
            }

            if let error = error {
                print("Audio conversion error: \(error)")
                return
            }

            guard let channelData = convertedBuffer.floatChannelData else { return }
            let frameCount = Int(convertedBuffer.frameLength)
            guard frameCount > 0 else { return }
            let samples = Array(
                UnsafeBufferPointer(
                    start: channelData[0],
                    count: frameCount
                ))

            // 書き込み前に再度世代を確認する（変換処理中に stop された可能性がある）
            guard self.sessionGeneration == currentGeneration else { return }

            self.lock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.lock.unlock()

            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            let normalizedLevel = min(max(rms * 5.0, 0.0), 1.0)

            Task { @MainActor [weak self] in
                self?.audioLevel = normalizedLevel
            }
        }
        hasInstalledTap = true

        engine.prepare()
        try engine.start()
        isRecording = true
        Task { @MainActor [weak self] in
            self?.audioLevel = 0.0
        }
    }

    private func _stopRecording() -> [Float] {
        sessionGeneration &+= 1

        _teardownEngine()
        isRecording = false
        Task { @MainActor [weak self] in
            self?.audioLevel = 0.0
        }

        lock.lock()
        let buffer = audioBuffer
        audioBuffer.removeAll()
        lock.unlock()

        return buffer
    }

    private func _cancelRecording() {
        sessionGeneration &+= 1

        _teardownEngine()
        isRecording = false
        Task { @MainActor [weak self] in
            self?.audioLevel = 0.0
        }

        lock.lock()
        audioBuffer.removeAll()
        lock.unlock()
    }

    /// AVAudioEngine の tap 除去・停止・破棄を安全に行うヘルパー
    private func _teardownEngine() {
        guard let engine = audioEngine else { return }

        if hasInstalledTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        engine.stop()
        engine.reset()
        audioEngine = nil
    }

    private func configureInputDevice(engine: AVAudioEngine, microphoneID: String?) throws {
        let deviceID: AudioDeviceID

        if let microphoneID, !microphoneID.isEmpty {
            guard let parsedDeviceID = AudioDeviceID(microphoneID) else {
                throw NSError(
                    domain: "AudioCaptureManager",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "The selected microphone is invalid."]
                )
            }
            deviceID = parsedDeviceID
        } else {
            deviceID = try Self.defaultInputDeviceID()
        }

        do {
            try engine.inputNode.auAudioUnit.setDeviceID(deviceID)
        } catch {
            throw NSError(
                domain: "AudioCaptureManager",
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to switch the recording device. Reconnect the microphone and try again."
                ]
            )
        }
    }

    private static func defaultInputDeviceID() throws -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != AudioDeviceID(0) else {
            throw NSError(
                domain: "AudioCaptureManager",
                code: -4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to resolve the system default microphone."
                ]
            )
        }

        return deviceID
    }

    static func availableMicrophones() -> [(id: String, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return [] }

        var microphones: [(id: String, name: String)] = []

        for deviceID in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(
                deviceID,
                &streamAddress,
                0,
                nil,
                &streamSize
            )

            guard status == noErr, streamSize > 0 else { continue }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var cfName: CFString? = nil

            status = withUnsafeMutablePointer(to: &cfName) { ptr in
                AudioObjectGetPropertyData(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize,
                    ptr
                )
            }

            guard status == noErr, let deviceName = cfName as String? else { continue }

            microphones.append((id: "\(deviceID)", name: deviceName))
        }

        return microphones
    }
}
