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
    enum RecordingState: Sendable {
        case idle
        case recording
        case transcribing
    }

    let settings: SettingsStore
    let history: HistoryStore
    let hotwords: HotwordStore
    let audioCapture = AudioCaptureManager()
    let transcriptionEngine = TranscriptionEngine()
    let textProcessingEngine = TextProcessingEngine()
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
            lastError = "Failed to load ASR model: \(error.localizedDescription)"
        }

        // Load text processing model if enabled
        if settings.textProcessingEnabled {
            do {
                try await textProcessingEngine.loadModel()
            } catch {
                lastError = "Failed to load text processing model: \(error.localizedDescription)"
            }
        }
    }

    /// Toggle text processing on/off. Loads/unloads the LLM model accordingly.
    func setTextProcessingEnabled(_ enabled: Bool) async {
        settings.textProcessingEnabled = enabled
        if enabled {
            if !textProcessingEngine.isModelLoaded {
                do {
                    try await textProcessingEngine.loadModel()
                } catch {
                    lastError =
                        "Failed to load text processing model: \(error.localizedDescription)"
                    settings.textProcessingEnabled = false
                }
            }
        } else {
            textProcessingEngine.unloadModel()
        }
    }

    private func setupHotkeyCallbacks() {
        hotkeyManager.onHotkeyDown = { [weak self] in
            self?.handleHotkeyDown()
        }

        hotkeyManager.onHotkeyUp = { [weak self] in
            self?.handleHotkeyUp()
        }

        hotkeyManager.onEscapePressed = { [weak self] in
            self?.handleEscapePressed()
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

        let pressedAt = hotkeyPressedAt
        let textProcessingEnabled = settings.textProcessingEnabled
        let textProcessingPreset = settings.textProcessingPreset
        let customPrompt = settings.customTextProcessingPrompt
        let currentVariant = transcriptionEngine.currentVariant ?? .defaultVariant
        let configuredLanguage = settings.language

        Task { [weak self] in
            guard let self = self else { return }

            let rawText = self.transcriptionEngine.transcribe(audio: audioSamples)

            if !rawText.isEmpty {
                // Detect language from the transcription output
                let detectedLanguage = self.detectLanguage(
                    from: rawText, configured: configuredLanguage)

                var processedText = rawText

                // Apply text processing if enabled and model is loaded
                if textProcessingEnabled && self.textProcessingEngine.isModelLoaded {
                    do {
                        processedText = try await self.textProcessingEngine.processText(
                            rawText,
                            preset: textProcessingPreset,
                            detectedLanguage: detectedLanguage,
                            customPrompt: customPrompt
                        )
                    } catch {
                        // If processing fails, fall back to raw text
                        print("Text processing failed: \(error). Using raw transcription.")
                        processedText = rawText
                    }
                }

                TextInsertionService.insertText(processedText)

                let record = TranscriptionRecord(
                    text: processedText,
                    durationSeconds: Date().timeIntervalSince(pressedAt ?? Date()),
                    modelVariant: currentVariant
                )
                self.history.add(record)
                self.history.pruneIfNeeded(retention: self.settings.historyRetention)
            }

            self.recordingState = .idle
            self.onRecordingStateChanged?(.idle)
        }
    }

    /// Detect the language of transcribed text.
    /// If the user configured a specific language, use that.
    /// Otherwise, use a simple heuristic based on character analysis.
    private func detectLanguage(from text: String, configured: String) -> String {
        if configured != "auto" {
            return configured
        }

        // Simple heuristic: check for CJK characters
        let cjkRanges: [ClosedRange<Unicode.Scalar>] = [
            Unicode.Scalar(0x3040)!...Unicode.Scalar(0x309F)!,  // Hiragana
            Unicode.Scalar(0x30A0)!...Unicode.Scalar(0x30FF)!,  // Katakana
        ]
        let kanjiRange = Unicode.Scalar(0x4E00)!...Unicode.Scalar(0x9FFF)!
        let hangulRange = Unicode.Scalar(0xAC00)!...Unicode.Scalar(0xD7AF)!

        var japaneseCount = 0
        var chineseCount = 0
        var koreanCount = 0
        var latinCount = 0

        for scalar in text.unicodeScalars {
            if cjkRanges.contains(where: { $0.contains(scalar) }) {
                japaneseCount += 1
            } else if kanjiRange.contains(scalar) {
                chineseCount += 1  // Could be Japanese kanji too
            } else if hangulRange.contains(scalar) {
                koreanCount += 1
            } else if scalar.isASCII && scalar.properties.isAlphabetic {
                latinCount += 1
            }
        }

        // If Japanese kana found, it's Japanese (kanji alone is ambiguous)
        if japaneseCount > 0 {
            return "ja"
        }
        if koreanCount > 0 {
            return "ko"
        }
        if chineseCount > 3 && latinCount < chineseCount {
            return "zh"
        }
        return "en"
    }

    private func cancelRecording() {
        audioCapture.cancelRecording()
        SoundFeedback.playErrorSound(isEnabled: settings.soundFeedbackEnabled)
        recordingState = .idle
        isToggleMode = false
        onRecordingStateChanged?(.idle)
    }

    func switchModel(_ variant: ASRModelVariant) async throws {
        guard recordingState == .idle else { return }
        settings.selectedModel = variant
        try await transcriptionEngine.loadModel(variant)
    }
}
