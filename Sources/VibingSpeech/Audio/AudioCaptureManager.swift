//
//  AudioCaptureManager.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import AVFoundation
import Observation
import CoreAudio

@Observable final class AudioCaptureManager {
    private let audioEngine = AVAudioEngine()
    private(set) var isRecording = false
    private(set) var audioLevel: Float = 0.0
    private var audioBuffer: [Float] = []
    private let targetSampleRate: Double = 16000.0
    private let lock = NSLock()
    private var converter: AVAudioConverter?

    init() {}

    func startRecording(microphoneID: String?) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create converter to 16kHz mono Float32
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        // Install tap with nil format to use engine's default format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, time in
            guard let self = self else { return }

            guard let converter = self.converter else { return }

            let capacity = AVAudioFrameCount(
                Double(buffer.frameLength) * self.targetSampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, status in
                status.pointee = .haveData
                return buffer
            }

            if let error = error {
                print("Audio conversion error: \(error)")
                return
            }

            // Convert to [Float]
            guard let channelData = convertedBuffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(
                start: channelData[0],
                count: Int(convertedBuffer.frameLength)
            ))

            self.lock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.lock.unlock()

            // Calculate RMS level
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
            let normalizedLevel = min(max(rms * 5.0, 0.0), 1.0)

            Task { @MainActor in
                self.audioLevel = normalizedLevel
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        audioLevel = 0.0
    }

    func stopRecording() -> [Float] {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        audioLevel = 0.0

        lock.lock()
        let buffer = audioBuffer
        audioBuffer.removeAll()
        lock.unlock()

        return buffer
    }

    func cancelRecording() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        audioLevel = 0.0

        lock.lock()
        audioBuffer.removeAll()
        lock.unlock()
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
            // Check if device has input channels
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

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var name: CFString?
            var nameSize = UInt32(MemoryLayout<CFString>.size)

            status = AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                &name
            )

            guard status == noErr, let deviceName = name as String? else { continue }

            microphones.append((id: "\(deviceID)", name: deviceName))
        }

        return microphones
    }
}
