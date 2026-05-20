import AppKit
import AppIntents
import SwiftUI

@main
struct VibingSpeechApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup("VibingSpeech") {
            ContentView(coordinator: coordinator)
                .frame(minWidth: 760, minHeight: 560)
                .preferredColorScheme(coordinator.preferredColorScheme)
                .task {
                    await coordinator.startup()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("VibingSpeech") {
                Button("Start Recording") {
                    Task { await coordinator.beginRecording() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Cancel Recording") {
                    Task { await coordinator.cancelRecording() }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var settings = SettingsStore()
    @Published var history = HistoryRepository()
    @Published var hotwords = HotwordRepository()
    @Published var permissions = PermissionService()
    @Published var textProcessing = TextProcessingService()
    @Published var phase: RecordingPhase = .idle
    @Published var asrModelLoaded = false
    @Published var asrStatusMessage = "Loading model..."
    @Published var lastError: String?
    @Published var availableMicrophones: [MicrophoneDevice] = [.systemDefault]
    @Published var overlayState = RecordingOverlayState()

    private let hotkeyService = HotkeyService()
    private let microphoneRecorder = MicrophoneRecorder()
    private let asrService = ASRService()
    private let textInsertionService = TextInsertionService()
    private let soundService = SoundService()
    private var menuBarController: MenuBarController?
    private var overlayController: RecordingOverlayController?
    private var startupStarted = false

    var preferredColorScheme: ColorScheme? {
        switch settings.appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var wordsToday: Int {
        history.records
            .filter { Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.wordCount }
    }

    var totalWords: Int {
        history.records.reduce(0) { $0 + $1.wordCount }
    }

    func startup() async {
        guard !startupStarted else { return }
        startupStarted = true

        guard isRunningOnAppleSilicon else {
            presentIntelUnsupportedAlert()
            NSApp.terminate(nil)
            return
        }

        menuBarController = MenuBarController(
            showWindow: { [weak self] in self?.showMainWindow() },
            quit: { NSApp.terminate(nil) }
        )
        overlayController = RecordingOverlayController(state: overlayState)

        microphoneRecorder.onRMSLevel = { [weak self] level in
            self?.overlayState.rmsLevel = level
        }
        availableMicrophones = microphoneRecorder.availableInputDevices()

        permissions.refresh()
        await permissions.requestMicrophoneIfNeeded()
        await loadASRModel()
        configureHotkey()
        textProcessing.setEnabled(settings.textProcessingEnabled)
    }

    func configureHotkey() {
        hotkeyService.onStartRecording = { [weak self] in
            Task { await self?.beginRecording() }
        }
        hotkeyService.onStopRecording = { [weak self] in
            Task { await self?.finishRecordingAndTranscribe() }
        }
        hotkeyService.onCancelRecording = { [weak self] in
            Task { await self?.cancelRecording() }
        }
        hotkeyService.onAccessibilityFailure = { [weak self] in
            self?.permissions.refresh()
        }

        do {
            try hotkeyService.start(hotkey: settings.recordingHotkey)
            permissions.refresh()
        } catch {
            permissions.refresh()
            lastError = error.localizedDescription
        }
    }

    func retryHotkeySetup() {
        permissions.refresh()
        configureHotkey()
    }

    func loadASRModel() async {
        guard phase == .idle else { return }
        asrModelLoaded = false
        asrStatusMessage = "Loading model..."
        do {
            try await asrService.load(variant: settings.asrModelVariant)
            asrModelLoaded = true
            asrStatusMessage = "Ready to record"
            lastError = nil
        } catch {
            asrModelLoaded = false
            asrStatusMessage = "ASR integration unavailable"
            lastError = error.localizedDescription
        }
    }

    func beginRecording() async {
        guard phase == .idle else { return }
        guard permissions.microphoneGranted else {
            lastError = "Microphone permission is required."
            return
        }
        guard asrModelLoaded else {
            lastError = asrStatusMessage
            return
        }

        do {
            try microphoneRecorder.start(selectedDeviceID: settings.microphoneID)
            phase = .recording
            overlayState.phase = .recording
            overlayController?.show()
            if settings.soundFeedbackEnabled {
                soundService.playStart()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func finishRecordingAndTranscribe() async {
        guard phase == .recording else { return }
        let capture = microphoneRecorder.stop()
        phase = .transcribing
        overlayState.phase = .transcribing
        if settings.soundFeedbackEnabled {
            soundService.playStop()
        }

        do {
            let asrResult = try await asrService.transcribe(samples: capture.samples, languageMode: settings.languageMode)
            let finalText: String
            let originalText: String?
            let processedByLLM: Bool

            if settings.textProcessingEnabled, textProcessing.isReady {
                finalText = try await textProcessing.process(
                    asrResult.text,
                    preset: settings.textProcessingPreset,
                    customPrompt: settings.customPrompt,
                    language: settings.languageMode,
                    detectedLanguage: asrResult.detectedLanguage
                )
                originalText = finalText == asrResult.text ? nil : asrResult.text
                processedByLLM = true
            } else {
                finalText = asrResult.text
                originalText = nil
                processedByLLM = false
            }

            textInsertionService.insert(finalText)
            let record = TranscriptionRecord(
                finalText: finalText,
                originalASRText: originalText,
                durationSeconds: capture.duration,
                modelVariant: settings.asrModelVariant,
                wasProcessedByLLM: processedByLLM
            )
            history.add(record, retention: settings.historyRetention)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        phase = .idle
        overlayState.phase = .idle
        overlayController?.hide()
    }

    func cancelRecording() async {
        guard phase != .idle else { return }
        microphoneRecorder.cancel()
        phase = .idle
        overlayState.phase = .idle
        overlayController?.hide()
        if settings.soundFeedbackEnabled {
            soundService.playCancel()
        }
    }

    func setTextProcessingEnabled(_ enabled: Bool) {
        settings.textProcessingEnabled = enabled
        textProcessing.setEnabled(enabled)
    }

    func deleteHistoryRecord(_ record: TranscriptionRecord) {
        history.delete(record.id)
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var isRunningOnAppleSilicon: Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? ""
            }
        }
        return machine == "arm64"
    }

    private func presentIntelUnsupportedAlert() {
        let alert = NSAlert()
        alert.messageText = "Apple Silicon Required"
        alert.informativeText = "VibingSpeech requires an Apple Silicon Mac running macOS 26 or newer."
        alert.alertStyle = .critical
        alert.runModal()
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "VibingSpeech" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let showWindowHandler: () -> Void
    private let quitHandler: () -> Void

    init(showWindow: @escaping () -> Void, quit: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        showWindowHandler = showWindow
        quitHandler = quit
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VibingSpeech")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showWindowAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func showWindowAction() {
        showWindowHandler()
    }

    @objc private func quitAction() {
        quitHandler()
    }
}
