//  AppState.swift
//  VibingSpeech

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
    private(set) var hotkeyErrorMessage: String?
    private(set) var isAccessibilityGranted = PermissionChecker.isAccessibilityGranted
    private(set) var pendingModelVariant: ASRModelVariant?

    private var hotkeyPressedAt: Date?
    private var isToggleMode = false
    private let longPressThreshold: TimeInterval = 0.3

    var onRecordingStateChanged: ((RecordingState) -> Void)?

    var selectedModelForUI: ASRModelVariant {
        pendingModelVariant ?? transcriptionEngine.currentVariant ?? settings.selectedModel
    }

    var isHotkeyReady: Bool {
        hotkeyManager.isRunning && hotkeyErrorMessage == nil
    }

    init() {
        self.settings = SettingsStore()
        self.history = HistoryStore()
        self.hotwords = HotwordStore()
        self.history.pruneIfNeeded(retention: settings.historyRetention)
        setupHotkeyCallbacks()
    }

    func setup() async {
        configureHotkeyMonitoring(promptIfNeeded: true)

        let micGranted = await PermissionChecker.requestMicrophoneAccess()
        if !micGranted {
            lastError = "Microphone permission is required to use this app."
        }

        await switchModel(settings.selectedModel)

        if settings.textProcessingEnabled {
            do {
                try await textProcessingEngine.loadModel()
            } catch {
                lastError = "Failed to load text processing model: \(error.localizedDescription)"
            }
        }
    }

    func clearLastError() {
        lastError = nil
    }

    func openAccessibilitySettings() {
        PermissionChecker.openAccessibilitySettings()
    }

    func retryHotkeySetup() {
        configureHotkeyMonitoring(promptIfNeeded: false)
    }

    func updateRecordingHotkey(_ hotkey: SettingsStore.RecordingHotkey) {
        settings.recordingHotkey = hotkey
        hotkeyManager.updateHotkey(hotkey.keyCode)

        if !hotkeyManager.isRunning && isAccessibilityGranted {
            configureHotkeyMonitoring(promptIfNeeded: false)
        }
    }

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

    func switchModel(_ variant: ASRModelVariant) async {
        guard recordingState == .idle else {
            lastError = "You can't switch the ASR model while recording or transcribing."
            return
        }

        pendingModelVariant = variant
        defer {
            pendingModelVariant = nil
        }

        do {
            try await transcriptionEngine.loadModel(variant)
            settings.selectedModel = variant
        } catch {
            lastError = "Failed to load ASR model: \(error.localizedDescription)"
        }
    }

    private func configureHotkeyMonitoring(promptIfNeeded: Bool) {
        isAccessibilityGranted = PermissionChecker.requestAccessibilityIfNeeded(
            prompt: promptIfNeeded
        )

        guard isAccessibilityGranted else {
            hotkeyManager.stop()
            hotkeyErrorMessage =
                "Accessibility permission is required for the global hotkey. Enable it in System Settings, then retry setup."
            return
        }

        do {
            try hotkeyManager.start(keyCode: settings.recordingHotkey.keyCode)
            hotkeyErrorMessage = nil
        } catch {
            hotkeyErrorMessage = error.localizedDescription
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
        let audioDuration = Double(audioSamples.count) / 16000.0
        SoundFeedback.playStopSound(isEnabled: settings.soundFeedbackEnabled)
        recordingState = .transcribing
        onRecordingStateChanged?(.transcribing)

        let textProcessingEnabled = settings.textProcessingEnabled
        let textProcessingPreset = settings.textProcessingPreset
        let customPrompt = settings.customTextProcessingPrompt
        let currentVariant = transcriptionEngine.currentVariant ?? settings.selectedModel
        let configuredLanguage = settings.language
        let asrLanguageHint = asrLanguageHint(from: configuredLanguage)
        let hotwordContext = hotwords.recognitionContext

        hotkeyPressedAt = nil
        isToggleMode = false

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let rawText = await self.transcriptionEngine.transcribe(
                audio: audioSamples,
                languageHint: asrLanguageHint,
                context: hotwordContext
            )

            if !rawText.isEmpty {
                let detectedLanguage = self.detectLanguage(
                    from: rawText,
                    configured: configuredLanguage
                )

                var finalText = rawText
                var originalText: String? = nil

                if textProcessingEnabled && self.textProcessingEngine.isModelLoaded {
                    do {
                        let processed = try await self.textProcessingEngine.processText(
                            rawText,
                            preset: textProcessingPreset,
                            detectedLanguage: detectedLanguage,
                            customPrompt: customPrompt
                        )
                        originalText = rawText
                        finalText = processed
                    } catch {
                        self.lastError =
                            "Text processing failed. The raw transcription was pasted instead."
                        finalText = rawText
                    }
                }

                TextInsertionService.insertText(finalText)

                let record = TranscriptionRecord(
                    text: finalText,
                    originalText: originalText,
                    durationSeconds: audioDuration,
                    modelVariant: currentVariant
                )
                self.history.add(record)
                self.history.pruneIfNeeded(retention: self.settings.historyRetention)
            }

            self.recordingState = .idle
            self.onRecordingStateChanged?(.idle)
        }
    }

    private func detectLanguage(from text: String, configured: String) -> String {
        if configured != "auto" {
            return configured
        }

        let hiraganaRange = Unicode.Scalar(0x3040)!...Unicode.Scalar(0x309F)!
        let katakanaRange = Unicode.Scalar(0x30A0)!...Unicode.Scalar(0x30FF)!
        let kanjiRange = Unicode.Scalar(0x4E00)!...Unicode.Scalar(0x9FFF)!
        let hangulRange = Unicode.Scalar(0xAC00)!...Unicode.Scalar(0xD7AF)!

        var japaneseCount = 0
        var chineseCount = 0
        var koreanCount = 0
        var latinCount = 0

        for scalar in text.unicodeScalars {
            if hiraganaRange.contains(scalar) || katakanaRange.contains(scalar) {
                japaneseCount += 1
            } else if kanjiRange.contains(scalar) {
                chineseCount += 1
            } else if hangulRange.contains(scalar) {
                koreanCount += 1
            } else if scalar.properties.isAlphabetic && scalar.value < 0x0250 {
                latinCount += 1
            }
        }

        if japaneseCount > 0 {
            return "ja"
        }
        if koreanCount > 0 {
            return "ko"
        }
        if chineseCount > 3 && latinCount < chineseCount {
            return "zh"
        }
        if latinCount > 0 {
            return "en"
        }
        return "unknown"
    }

    private func asrLanguageHint(from configuredLanguage: String) -> String? {
        switch configuredLanguage {
        case "auto": return nil
        case "en": return "English"
        case "ja": return "Japanese"
        case "zh": return "Chinese"
        case "ko": return "Korean"
        default: return nil
        }
    }

    private func cancelRecording() {
        audioCapture.cancelRecording()
        SoundFeedback.playErrorSound(isEnabled: settings.soundFeedbackEnabled)
        recordingState = .idle
        isToggleMode = false
        hotkeyPressedAt = nil
        onRecordingStateChanged?(.idle)
    }
}
