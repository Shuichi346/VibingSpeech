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
            HomeView(coordinator: coordinator, settings: settings)
        case .hotwords:
            HotwordsView(repository: coordinator.hotwords)
        case .history:
            HistoryView(coordinator: coordinator, repository: coordinator.history, settings: settings)
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
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }
}

private struct HomeView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var settings: SettingsStore

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
                    StatBlock(systemImage: "pencil", value: "\(coordinator.wordsToday) words", caption: "Words today")
                    Divider().frame(height: 36)
                    StatBlock(systemImage: "doc.text", value: "\(coordinator.totalWords) words", caption: "Total words")
                }
                .frame(height: 54)
                .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))

                SettingsCard(coordinator: coordinator, settings: settings)

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
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(coordinator.textProcessing.isReady ? "Text processing ready" : "Loading text processor...")
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
                    .disabled(coordinator.phase != .idle)
                    .onChange(of: settings.asrModelVariant) {
                        Task { await coordinator.loadASRModel() }
                    }
                }
            }

            SettingsSection {
                SettingsRow("Appearance") {
                    Picker("", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
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
                        for index in indexSet {
                            repository.delete(repository.hotwords[index].id)
                        }
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
                Picker("", selection: $settings.historyRetention) {
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
                                        copy: { coordinator.copyToClipboard(record.finalText) },
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
                repository.clear()
            }
        }
    }
}

private struct HistoryRow: View {
    let record: TranscriptionRecord
    let copy: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(DateGrouping.timeFormatter.string(from: record.timestamp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.finalText)
                    .lineLimit(4)
                Text("\(record.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if record.wasProcessedByLLM, let original = record.originalASRText {
                    DisclosureGroup("Original ASR text") {
                        Text(original)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Button(action: copy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(10)
        .contextMenu {
            Button("Copy") { copy() }
            Button("Delete", role: .destructive) { delete() }
        }
    }
}
