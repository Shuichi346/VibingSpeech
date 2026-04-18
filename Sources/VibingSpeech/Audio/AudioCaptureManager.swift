//
//  AudioCaptureManager.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

@preconcurrency import AVFoundation
import CoreAudio
import Observation

@Observable final class AudioCaptureManager: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private(set) var isRecording = false
    @MainActor private(set) var audioLevel: Float = 0.0
    private var audioBuffer: [Float] = []
    private let targetSampleRate: Double = 16000.0
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var hasInstalledTap = false

    init() {}

    func startRecording(microphoneID: String?) throws {
        audioEngine.stop()
        audioEngine.reset()
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        lock.lock()
        audioBuffer.removeAll()
        lock.unlock()

        try configureInputDevice(microphoneID)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // 16kHz モノラル Float32 に変換する
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw NSError(
                domain: "AudioCaptureManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create output audio format"])
        }

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        let targetSampleRate = self.targetSampleRate

        // エンジン側の実入力フォーマットを使う
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let converter = self.converter else { return }

            let capacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetSampleRate / inputFormat.sampleRate
            )
            guard
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: capacity
                )
            else { return }

            var error: NSError?
            let inputBuffer = buffer
            converter.convert(to: convertedBuffer, error: &error) { _, status in
                status.pointee = .haveData
                return inputBuffer
            }

            if let error = error {
                print("Audio conversion error: \(error)")
                return
            }

            // Float 配列へ変換する
            guard let channelData = convertedBuffer.floatChannelData else { return }
            let samples = Array(
                UnsafeBufferPointer(
                    start: channelData[0],
                    count: Int(convertedBuffer.frameLength)
                ))

            self.lock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.lock.unlock()

            // 録音レベル表示用の RMS を計算する
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            let normalizedLevel = min(max(rms * 5.0, 0.0), 1.0)

            Task { @MainActor [weak self] in
                self?.audioLevel = normalizedLevel
            }
        }
        hasInstalledTap = true

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        Task { @MainActor [weak self] in
            self?.audioLevel = 0.0
        }
    }

    func stopRecording() -> [Float] {
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        audioEngine.stop()
        audioEngine.reset()
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

    func cancelRecording() {
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        audioEngine.stop()
        audioEngine.reset()
        isRecording = false
        Task { @MainActor [weak self] in
            self?.audioLevel = 0.0
        }

        lock.lock()
        audioBuffer.removeAll()
        lock.unlock()
    }

    private func configureInputDevice(_ microphoneID: String?) throws {
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
            try audioEngine.inputNode.auAudioUnit.setDeviceID(deviceID)
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
                userInfo: [NSLocalizedDescriptionKey: "Failed to resolve the system default microphone."]
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
            // 入力チャンネルを持つデバイスだけを対象にする
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

            // デバイス名を取得する
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
