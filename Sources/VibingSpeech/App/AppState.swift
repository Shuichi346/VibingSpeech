//
//  AppState.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import Foundation
import Observation

@MainActor
@Observable final class AppState {
    enum RecordingState {
        case idle
        case recording
        case transcribing
    }

    let settings: SettingsStore
    let history: HistoryStore
    let hotwords: HotwordStore
    let audioCapture = AudioCaptureManager()
    let transcriptionEngine = TranscriptionEngine()
    let hotkeyManager = GlobalHotkeyManager()

    private(set) var recordingState: RecordingState = .idle
    private(set) var lastError: String?

    private var hotkeyPressedAt: Date?
    private var isToggleMode = false
    private let longPressThreshold: TimeInterval = 0.3

    var onRecordingStateChanged: ((RecordingState) -> Void)?

    init() {
        self.settings = SettingsStore()
        self.history = HistoryStore()
        self.hotwords = HotwordStore()
        setupHotkeyCallbacks()
    }

    func setup() async {
        PermissionChecker.requestAccessibilityIfNeeded()

        let micGranted = await PermissionChecker.requestMicrophoneAccess()
        if !micGranted {
            lastError = "Microphone permission is required to use this app."
        }

        hotkeyManager.start(keyCode: KeyCode.rightOption.rawValue)

        do {
            try await transcriptionEngine.loadModel(settings.selectedModel)
        } catch {
            lastError = "Failed to load model: \(error.localizedDescription)"
        }
    }

    private func setupHotkeyCallbacks() {
        hotkeyManager.onHotkeyDown = { [weak self] in
            guard let self = self else { return }
            self.handleHotkeyDown()
        }

        hotkeyManager.onHotkeyUp = { [weak self] in
            guard let self = self else { return }
            self.handleHotkeyUp()
        }

        hotkeyManager.onEscapePressed = { [weak self] in
            guard let self = self else { return }
            self.handleEscapePressed()
        }
    }

    private func handleHotkeyDown() {
        if recordingState == .idle {
            hotkeyPressedAt = Date()
            startRecording()
        } else if recordingState == .recording && isToggleMode {
            stopRecordingAndTranscribe()
        }
    }

    private func handleHotkeyUp() {
        guard recordingState == .recording else { return }

        if isToggleMode {
            return
        }

        guard let pressedAt = hotkeyPressedAt else { return }
        let elapsed = Date().timeIntervalSince(pressedAt)

        if elapsed >= longPressThreshold {
            stopRecordingAndTranscribe()
        } else {
            isToggleMode = true
        }
    }

    private func handleEscapePressed() {
        if recordingState == .recording {
            cancelRecording()
        }
    }

    private func startRecording() {
        do {
            try audioCapture.startRecording(microphoneID: settings.selectedMicrophoneID)
            recordingState = .recording
            isToggleMode = false
            SoundFeedback.playStartSound(isEnabled: settings.soundFeedbackEnabled)
            onRecordingStateChanged?(.recording)
        } catch {
            lastError = "Failed to start recording: \(error.localizedDescription)"
            recordingState = .idle
        }
    }

    private func stopRecordingAndTranscribe() {
        let audioSamples = audioCapture.stopRecording()
        SoundFeedback.playStopSound(isEnabled: settings.soundFeedbackEnabled)
        recordingState = .transcribing
        onRecordingStateChanged?(.transcribing)

        Task { [weak self] in
            guard let self = self else { return }

            let text = self.transcriptionEngine.transcribe(audio: audioSamples)

            if !text.isEmpty {
                // Apply text polish if enabled
                let processedText = self.settings.textPolishEnabled ? self.polishText(text) : text

                TextInsertionService.insertText(processedText)

                let record = TranscriptionRecord(
                    text: processedText,
                    durationSeconds: Date().timeIntervalSince(self.hotkeyPressedAt ?? Date()),
                    modelVariant: self.transcriptionEngine.currentVariant ?? .defaultVariant
                )
                self.history.add(record)
                self.history.pruneIfNeeded(retention: self.settings.historyRetention)
            }

            self.recordingState = .idle
            self.onRecordingStateChanged?(.idle)
        }
    }

    private func cancelRecording() {
        audioCapture.cancelRecording()
        SoundFeedback.playErrorSound(isEnabled: settings.soundFeedbackEnabled)
        recordingState = .idle
        isToggleMode = false
        onRecordingStateChanged?(.idle)
    }

    private func polishText(_ text: String) -> String {
        var processed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        processed = processed.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize first letter if it's English
        if let first = processed.first, first.isASCII && first.isLowercase {
            processed = processed.prefix(1).uppercased() + processed.dropFirst()
        }

        return processed
    }

    func switchModel(_ variant: ASRModelVariant) async throws {
        guard recordingState == .idle else { return }
        settings.selectedModel = variant
        try await transcriptionEngine.loadModel(variant)
    }
}
