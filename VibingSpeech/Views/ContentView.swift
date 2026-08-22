import SwiftUI

enum AppLayout {
    static let windowWidth: CGFloat = 760
    static let windowHeight: CGFloat = 560
    static let sidebarWidth: CGFloat = 146
    static let collapsedSidebarWidth: CGFloat = 46
}

struct ContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var settings: SettingsStore
    @State private var isSidebarVisible = true

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _settings = ObservedObject(wrappedValue: coordinator.settings)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView(settings: settings, isSidebarVisible: $isSidebarVisible)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                CollapsedSidebarView(isSidebarVisible: $isSidebarVisible)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Divider()
            ZStack(alignment: .topLeading) {
                detail
                    .id(settings.selectedSidebar)
                    .transition(.opacity)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: AppLayout.windowWidth, height: AppLayout.windowHeight)
        .clipped()
        .animation(.easeInOut(duration: 0.12), value: settings.selectedSidebar)
        .animation(.easeInOut(duration: 0.16), value: isSidebarVisible)
    }

    @ViewBuilder
    private var detail: some View {
        switch settings.selectedSidebar {
        case .home:
            HomeView(coordinator: coordinator, settings: settings, history: coordinator.history)
        case .hotwords:
            HotwordsView(repository: coordinator.hotwords)
        case .history:
            HistoryView(coordinator: coordinator, repository: coordinator.history, settings: settings)
        case .other:
            OtherView(coordinator: coordinator, settings: settings, launchAtLogin: coordinator.launchAtLogin)
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var isSidebarVisible: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button {
                    isSidebarVisible = false
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Hide Sidebar")
            }
            .padding(.top, 14)
            .padding(.trailing, 14)

            ForEach(SidebarSelection.allCases) { item in
                SidebarRow(
                    item: item,
                    isSelected: settings.selectedSidebar == item,
                    select: { settings.selectedSidebar = item }
                )
            }

            Spacer()
        }
        .frame(width: AppLayout.sidebarWidth)
        .background {
            Color(nsColor: .controlBackgroundColor)
            Rectangle().fill(.bar)
        }
    }
}

private struct CollapsedSidebarView: View {
    @Binding var isSidebarVisible: Bool

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    isSidebarVisible = true
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Show Sidebar")
                Spacer()
            }
            .padding(.top, 14)

            Spacer()
        }
        .frame(width: AppLayout.collapsedSidebarWidth)
        .background {
            Color(nsColor: .controlBackgroundColor)
            Rectangle().fill(.bar)
        }
    }
}

private struct SidebarRow: View {
    let item: SidebarSelection
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
            } icon: {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
            }
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

private struct HomeView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: SettingsStore
    @ObservedObject var history: HistoryRepository

    private var wordsToday: Int {
        history.records
            .filter { Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.wordCount }
    }

    private var totalWords: Int {
        history.records.reduce(0) { $0 + $1.wordCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("VibingSpeech")
                    .font(.headline)
                    .padding(.top, 18)

                HStack {
                    Text("VibingSpeech — Just Speak It!")
                        .font(.system(size: 22, weight: .semibold))
                    Spacer()
                    StatusBadge(coordinator: coordinator)
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 0) {
                    StatBlock(systemImage: "pencil", value: "\(wordsToday) words", caption: "Words today")
                    Divider().frame(height: 36)
                    StatBlock(systemImage: "doc.text", value: "\(totalWords) words", caption: "Total words")
                }
                .frame(height: 54)
                .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))

                ModelActivityPanel(coordinator: coordinator, settings: settings, textProcessing: coordinator.textProcessing)

                SettingsCard(coordinator: coordinator, settings: settings, textProcessing: coordinator.textProcessing)

                if let error = coordinator.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 660, alignment: .leading)
        }
    }
}

private struct StatusBadge: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 7) {
            if coordinator.asrModelIsLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var statusColor: Color {
        if !coordinator.permissions.accessibilityGranted { return .orange }
        if !coordinator.asrModelLoaded { return .orange }
        return .green
    }

    private var statusText: String {
        if !coordinator.permissions.accessibilityGranted { return "Hotkey setup required" }
        return coordinator.asrStatusMessage
    }
}

private struct ModelActivityPanel: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: SettingsStore
    @ObservedObject var textProcessing: TextProcessingService

    private var isVisible: Bool {
        coordinator.asrModelIsLoading || textProcessing.isLoading
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing models")
                        .font(.callout.weight(.medium))
                    Spacer()
                }

                if coordinator.asrModelIsLoading {
                    ModelActivityRow(
                        title: "ASR",
                        message: "Downloading or loading \(settings.asrModelVariant.displayName) (\(settings.asrModelVariant.estimatedDownloadSize))"
                    )
                }

                if textProcessing.isLoading {
                    ModelActivityRow(
                        title: "LLM",
                        message: "Preparing \(TextProcessingService.modelIdentifier)"
                    )
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.18))
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

private struct ModelActivityRow: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private struct StatBlock: View {
    let systemImage: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(spacing: 3) {
                Text(value)
                    .font(.callout)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsCard: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: SettingsStore
    @ObservedObject var textProcessing: TextProcessingService

    var body: some View {
        VStack(spacing: 14) {
            SettingsSection {
                SettingsRow("Recording Hotkey") {
                    Picker("", selection: $settings.recordingHotkey) {
                        ForEach(RecordingHotkey.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settings.recordingHotkey) {
                        coordinator.configureHotkey()
                    }
                } footer: {
                    Text("Long press = hold mode · Short press = toggle mode")
                }

                Divider()

                SettingsRow("Cancel Recording") {
                    Text("Esc").foregroundStyle(.secondary)
                }

                if !coordinator.permissions.accessibilityGranted {
                    Divider()
                    AccessibilityWarning(coordinator: coordinator)
                }

                Divider()

                SettingsRow("Microphone") {
                    Picker("", selection: $settings.microphoneID) {
                        ForEach(coordinator.availableMicrophones) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider()

                SettingsRow("Sound Feedback") {
                    Toggle("", isOn: $settings.soundFeedbackEnabled)
                        .toggleStyle(.switch)
                }

                Divider()

                SettingsRow("Live Transcription") {
                    Toggle("", isOn: $settings.liveTranscriptionEnabled)
                        .toggleStyle(.switch)
                        .disabled(coordinator.phase != .idle)
                } footer: {
                    Text("Shows live text in the overlay and still pastes once when recording stops.")
                }
            }

            SettingsSection {
                SettingsRow("Text Processing (LLM)") {
                    Toggle("", isOn: Binding(
                        get: { settings.textProcessingEnabled },
                        set: { coordinator.setTextProcessingEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                }

                if settings.textProcessingEnabled {
                    HStack(spacing: 7) {
                        if textProcessing.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                        } else {
                            Circle()
                                .fill(textProcessing.isReady ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                        }
                        Text(textProcessing.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 11)

                    Divider()

                    SettingsRow("Preset") {
                        Picker("", selection: $settings.textProcessingPreset) {
                            ForEach(TextProcessingPreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Divider()
                    SettingsRow("Model") {
                        Text(TextProcessingService.modelIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if settings.textProcessingPreset == .custom {
                        TextEditor(text: $settings.customPrompt)
                            .font(.body)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 7))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                    }
                }

                Divider()

                SettingsRow("Language") {
                    Picker("", selection: $settings.languageMode) {
                        ForEach(LanguageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider()

                SettingsRow("ASR Model") {
                    Picker("", selection: $settings.asrModelVariant) {
                        ForEach(ASRModelVariant.allCases) { variant in
                            Text("\(variant.displayName) (\(variant.estimatedDownloadSize))").tag(variant)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(coordinator.phase != .idle || coordinator.asrModelIsLoading)
                    .onChange(of: settings.asrModelVariant) {
                        Task { await coordinator.loadASRModel() }
                    }
                }
                if coordinator.asrModelIsLoading || !coordinator.asrModelLoaded {
                    HStack(spacing: 7) {
                        if coordinator.asrModelIsLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                        } else {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                        Text(coordinator.asrStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 11)
                }
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06))
        }
    }
}

private struct SettingsRow<Accessory: View, Footer: View>: View {
    private let title: String
    private let accessory: Accessory
    private let footer: Footer

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.accessory = accessory()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                accessory
            }
            footer
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct AccessibilityWarning: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Accessibility permission is required for the global hotkey. Enable it in System Settings, then retry setup.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Open Accessibility Settings") {
                    coordinator.permissions.openAccessibilitySettings()
                }
                Button("Retry Hotkey Setup") {
                    coordinator.retryHotkeySetup()
                }
            }
        }
        .padding(10)
    }
}

private struct HotwordsView: View {
    @ObservedObject var repository: HotwordRepository
    @State private var newHotword = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hotwords")
                .font(.headline)
                .padding(.top, 18)

            HStack(spacing: 10) {
                Image(systemName: "text.badge.plus")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hotword Enhancement")
                        .font(.headline)
                    Text("Add proper nouns, terms, names to improve recognition accuracy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Text("Enter new hotword...")
                TextField("", text: $newHotword)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    if repository.add(newHotword) {
                        newHotword = ""
                    }
                }
                .disabled(newHotword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))

            if repository.hotwords.isEmpty {
                ContentUnavailableView("No manual hotwords", systemImage: "text.badge.plus", description: Text("Add proper nouns in the field above"))
                    .frame(maxWidth: .infinity, minHeight: 190)
                    .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            } else {
                List {
                    ForEach(repository.hotwords) { hotword in
                        HStack {
                            Text(hotword.text)
                            Spacer()
                            Button {
                                repository.delete(hotword.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete { indexSet in
                        let ids = Set(indexSet.map { repository.hotwords[$0].id })
                        repository.delete(ids: ids)
                    }
                }
                .listStyle(.inset)
                .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 660, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct HistoryView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var repository: HistoryRepository
    @ObservedObject var settings: SettingsStore
    @State private var searchText = ""
    @State private var showingClearConfirmation = false

    private var historyRetentionBinding: Binding<HistoryRetention> {
        Binding(
            get: { settings.historyRetention },
            set: { coordinator.setHistoryRetention($0) }
        )
    }

    private var filteredRecords: [TranscriptionRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return repository.records }
        return repository.records.filter {
            $0.finalText.localizedCaseInsensitiveContains(query) ||
            ($0.originalASRText?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var groupedRecords: [(String, [TranscriptionRecord])] {
        let groups = Dictionary(grouping: filteredRecords) { DateGrouping.title(for: $0.timestamp) }
        return groups
            .map { ($0.key, $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { left, right in
                (left.1.first?.timestamp ?? .distantPast) > (right.1.first?.timestamp ?? .distantPast)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    showingClearConfirmation = true
                }
                .disabled(repository.records.isEmpty)
            }
            .padding(.top, 18)

            SettingsRow("Save History") {
                Picker("", selection: historyRetentionBinding) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("How long to keep dictation history on device?")
            }
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))

            TextField("Search history", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredRecords.isEmpty {
                ContentUnavailableView("No history", systemImage: "clock", description: Text("Dictation history appears here"))
                    .frame(maxWidth: .infinity, minHeight: 190)
                    .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedRecords, id: \.0) { title, records in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(title)
                                    .font(.headline)
                                    .padding([.horizontal, .top], 10)
                                    .padding(.bottom, 8)
                                ForEach(records) { record in
                                    HistoryRow(
                                        record: record,
                                        copy: coordinator.copyToClipboard,
                                        delete: { coordinator.deleteHistoryRecord(record) }
                                    )
                                    if record.id != records.last?.id {
                                        Divider().padding(.leading, 72)
                                    }
                                }
                            }
                            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: 660, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Clear all history?", isPresented: $showingClearConfirmation) {
            Button("Clear History", role: .destructive) {
                Task { await repository.clear() }
            }
        }
    }
}

private struct HistoryRow: View {
    let record: TranscriptionRecord
    let copy: (String) -> Void
    let delete: () -> Void
    @State private var copiedKind: HistoryCopyKind?

    private var finalCopyOption: HistoryCopyOption {
        HistoryCopyOption(
            kind: record.wasProcessedByLLM ? .llmEdit : .transcription,
            text: record.finalText
        )
    }

    private var originalCopyOption: HistoryCopyOption? {
        guard record.wasProcessedByLLM, let original = record.originalASRText else { return nil }
        return HistoryCopyOption(kind: .originalTranscription, text: original)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(DateGrouping.timeFormatter.string(from: record.timestamp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(record.finalText)
                        .lineLimit(4)

                    HistoryCopyButton(
                        option: finalCopyOption,
                        isCopied: copiedKind == finalCopyOption.kind,
                        action: { performCopy(finalCopyOption) }
                    )
                }
                Text("\(record.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if record.wasProcessedByLLM, let original = record.originalASRText {
                    DisclosureGroup("Original ASR text") {
                        HStack(alignment: .top, spacing: 8) {
                            Text(original)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)

                            if let originalCopyOption {
                                HistoryCopyButton(
                                    option: originalCopyOption,
                                    isCopied: copiedKind == originalCopyOption.kind,
                                    action: { performCopy(originalCopyOption) }
                                )
                                .padding(.top, 1)
                            }
                        }
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(10)
        .contextMenu {
            Button {
                performCopy(finalCopyOption)
            } label: {
                Label(finalCopyOption.copyMenuTitle, systemImage: finalCopyOption.systemImage)
            }

            if let originalCopyOption {
                Button {
                    performCopy(originalCopyOption)
                } label: {
                    Label(originalCopyOption.copyMenuTitle, systemImage: originalCopyOption.systemImage)
                }
            }

            Button("Delete", role: .destructive) { delete() }
        }
    }

    private func performCopy(_ option: HistoryCopyOption) {
        copy(option.text)
        copiedKind = option.kind

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                if copiedKind == option.kind {
                    copiedKind = nil
                }
            }
        }
    }
}

private struct OtherView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: SettingsStore
    @ObservedObject var launchAtLogin: LaunchAtLoginService

    private var modelUnloadDelayBinding: Binding<Int> {
        Binding(
            get: { settings.modelUnloadDelayMinutes },
            set: { coordinator.setModelUnloadDelayMinutes($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { coordinator.setLaunchAtLoginEnabled($0) }
        )
    }

    private var modelUnloadDelayLabel: String {
        settings.modelUnloadDelayMinutes == 0 ? "Off" : "\(settings.modelUnloadDelayMinutes) min"
    }

    private var modelUnloadFooter: String {
        if settings.textProcessingEnabled {
            "After this many idle minutes with no recording or transcription, unload ASR and Text Processing (LLM)."
        } else {
            "After this many idle minutes with no recording or transcription, unload ASR."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Other")
                    .font(.headline)
                    .padding(.top, 18)

                SettingsSection {
                    SettingsRow("Appearance") {
                        Picker("", selection: $settings.appearanceMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider()

                    SettingsRow("Model Auto-Unload") {
                        HStack(spacing: 8) {
                            Text(modelUnloadDelayLabel)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                            Stepper("", value: modelUnloadDelayBinding, in: 0...SettingsStore.maximumModelUnloadDelayMinutes)
                                .labelsHidden()
                        }
                    } footer: {
                        Text(modelUnloadFooter)
                    }

                    Divider()

                    SettingsRow("Launch at Login") {
                        Toggle("", isOn: launchAtLoginBinding)
                            .toggleStyle(.switch)
                    } footer: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(launchAtLogin.statusMessage)
                            if let error = launchAtLogin.lastError {
                                Text(error)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 660, alignment: .leading)
        }
    }
}

private enum HistoryCopyKind: Hashable {
    case llmEdit
    case transcription
    case originalTranscription
}

private struct HistoryCopyOption {
    let kind: HistoryCopyKind
    let text: String

    var title: String {
        switch kind {
        case .llmEdit:
            "LLM edit"
        case .transcription:
            "Transcription"
        case .originalTranscription:
            "Original"
        }
    }

    var copyMenuTitle: String {
        switch kind {
        case .llmEdit:
            "Copy LLM edit"
        case .transcription:
            "Copy transcription"
        case .originalTranscription:
            "Copy original transcription"
        }
    }

    var copiedTitle: String {
        switch kind {
        case .llmEdit:
            "Copied edit"
        case .transcription:
            "Copied transcription"
        case .originalTranscription:
            "Copied original"
        }
    }

    var systemImage: String {
        switch kind {
        case .llmEdit:
            "wand.and.stars"
        case .transcription:
            "waveform"
        case .originalTranscription:
            "text.quote"
        }
    }
}

private struct HistoryCopyButton: View {
    let option: HistoryCopyOption
    let isCopied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                isCopied ? option.copiedTitle : option.title,
                systemImage: isCopied ? "checkmark" : option.systemImage
            )
            .font(.caption)
            .labelStyle(.titleAndIcon)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isCopied ? Color.green : Color.secondary)
        .help(isCopied ? option.copiedTitle : option.copyMenuTitle)
        .accessibilityLabel(option.copyMenuTitle)
    }
}
