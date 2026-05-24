import AppKit
import AppIntents
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor [coordinator] in
            await coordinator.startup()
        }
    }
}

@main
struct VibingSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var coordinator: AppCoordinator {
        appDelegate.coordinator
    }

    var body: some Scene {
        WindowGroup("VibingSpeech") {
            ContentView(coordinator: coordinator)
                .frame(width: AppLayout.windowWidth, height: AppLayout.windowHeight)
                .background(WindowAccessor { window in
                    coordinator.registerMainWindow(window)
                })
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: AppLayout.windowWidth, height: AppLayout.windowHeight)
        .windowResizability(.contentSize)
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
    @Published var launchAtLogin = LaunchAtLoginService()
    @Published var phase: RecordingPhase = .idle
    @Published var asrModelLoaded = false
    @Published var asrModelIsLoading = false
    @Published var asrStatusMessage = "Loading model..."
    @Published var lastError: String?
    @Published var availableMicrophones: [MicrophoneDevice] = [.systemDefault]
    @Published var overlayState = RecordingOverlayState()

    private let hotkeyService = HotkeyService()
    private let microphoneRecorder = MicrophoneRecorder()
    private let asrService = ASRService()
    private let textInsertionService = TextInsertionService()
    private let soundService = SoundService()
    private let appearanceService = AppearanceService()
    private let mainWindowController = MainWindowController()
    private var menuBarController: MenuBarController?
    private var overlayController: RecordingOverlayController?
    private var startupStarted = false
    private var asrLoadGeneration = UUID()
    private var modelUnloadTask: Task<Void, Never>?
    private var appearanceModeCancellable: AnyCancellable?

    init() {
        appearanceService.apply(settings.appearanceMode)
        appearanceModeCancellable = settings.$appearanceMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.appearanceService.apply(mode)
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
        textProcessing.onStateChange = { [weak self] in
            self?.scheduleModelUnloadIfNeeded()
        }
        availableMicrophones = microphoneRecorder.availableInputDevices()
        launchAtLogin.refresh()

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
        cancelModelUnloadTimer()
        let variant = settings.asrModelVariant
        let generation = UUID()
        asrLoadGeneration = generation
        asrModelLoaded = false
        asrModelIsLoading = true
        asrStatusMessage = "Preparing \(variant.displayName)..."
        do {
            try await asrService.load(variant: variant)
            guard asrLoadGeneration == generation else { return }
            asrModelLoaded = true
            asrModelIsLoading = false
            asrStatusMessage = "Ready to record"
            lastError = nil
            scheduleModelUnloadIfNeeded()
        } catch {
            guard asrLoadGeneration == generation else { return }
            asrModelLoaded = false
            asrModelIsLoading = false
            asrStatusMessage = "ASR integration unavailable"
            lastError = error.localizedDescription
        }
    }

    func beginRecording() async {
        guard phase == .idle else { return }
        cancelModelUnloadTimer()
        guard permissions.microphoneGranted else {
            lastError = "Microphone permission is required."
            scheduleModelUnloadIfNeeded()
            return
        }
        if !asrModelLoaded {
            await loadASRModel()
            cancelModelUnloadTimer()
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
            scheduleModelUnloadIfNeeded()
        }
    }

    func finishRecordingAndTranscribe() async {
        guard phase == .recording else { return }
        let capture = microphoneRecorder.stop()
        if settings.soundFeedbackEnabled {
            soundService.playStop()
        }

        guard capture.samples.count >= MicrophoneRecorder.minimumSamplesForASR else {
            phase = .idle
            overlayState.phase = .idle
            overlayController?.hide()
            lastError = nil
            scheduleModelUnloadIfNeeded()
            return
        }

        phase = .transcribing
        overlayState.phase = .transcribing

        do {
            let asrResult = try await asrService.transcribe(samples: capture.samples, languageMode: settings.languageMode)
            let finalText: String
            let originalText: String?
            let processedByLLM: Bool
            var textProcessingError: String?

            if settings.textProcessingEnabled {
                do {
                    finalText = try await textProcessing.process(
                        asrResult.text,
                        preset: settings.textProcessingPreset,
                        customPrompt: settings.customPrompt,
                        language: settings.languageMode,
                        detectedLanguage: asrResult.detectedLanguage
                    )
                    originalText = asrResult.text
                    processedByLLM = true
                } catch {
                    finalText = asrResult.text
                    originalText = nil
                    processedByLLM = false
                    textProcessingError = "Text processing failed: \(error.localizedDescription)"
                }
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
            lastError = textProcessingError
        } catch {
            lastError = error.localizedDescription
        }

        phase = .idle
        overlayState.phase = .idle
        overlayController?.hide()
        scheduleModelUnloadIfNeeded()
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
        scheduleModelUnloadIfNeeded()
    }

    func setTextProcessingEnabled(_ enabled: Bool) {
        settings.textProcessingEnabled = enabled
        textProcessing.setEnabled(enabled)
    }

    func setModelUnloadDelayMinutes(_ minutes: Int) {
        settings.modelUnloadDelayMinutes = SettingsStore.clampedModelUnloadDelayMinutes(minutes)
        scheduleModelUnloadIfNeeded()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLogin.setEnabled(enabled)
    }

    func deleteHistoryRecord(_ record: TranscriptionRecord) {
        history.delete(record.id)
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindowController.register(window)
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
        if mainWindowController.show() {
            return
        }
        showDiscoveredMainWindow()
        DispatchQueue.main.async { [weak self] in
            self?.showDiscoveredMainWindow()
        }
    }

    private func showDiscoveredMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        mainWindowController.register(window)
        mainWindowController.show()
    }

    private func scheduleModelUnloadIfNeeded() {
        cancelModelUnloadTimer()
        let delayMinutes = SettingsStore.clampedModelUnloadDelayMinutes(settings.modelUnloadDelayMinutes)
        let shouldUnloadTextProcessor = settings.textProcessingEnabled && textProcessing.isReady
        guard delayMinutes > 0,
              phase == .idle,
              !asrModelIsLoading,
              !textProcessing.isLoading,
              asrModelLoaded || shouldUnloadTextProcessor else { return }

        modelUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delayMinutes * 60))
            guard !Task.isCancelled else { return }
            await self?.unloadModelsAfterIdle()
        }
    }

    private func cancelModelUnloadTimer() {
        modelUnloadTask?.cancel()
        modelUnloadTask = nil
    }

    private func unloadModelsAfterIdle() async {
        guard phase == .idle, !asrModelIsLoading, !textProcessing.isLoading else { return }
        let shouldUnloadTextProcessor = settings.textProcessingEnabled && textProcessing.isReady
        if asrModelLoaded {
            await asrService.unload()
            asrModelLoaded = false
            asrStatusMessage = "Model unloaded after \(settings.modelUnloadDelayMinutes) minutes idle"
        }
        if shouldUnloadTextProcessor {
            await textProcessing.unloadAfterIdle()
        }
    }
}

@MainActor
private final class MainWindowController: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?

    func register(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.delegate = self
    }

    @discardableResult
    func show() -> Bool {
        guard let window else { return false }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            sender.orderOut(nil)
        }
        return false
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
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
