//
//  HomeView.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import SwiftUI

struct HomeView: View {
    @Bindable var appState: AppState
    @State private var cachedMicrophones: [(id: String, name: String)] = []

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("VibingSpeech — Just Speak It!")
                        .font(.title)
                    Spacer()
                    statusIndicator
                }
            }

            Section {
                HStack(spacing: 40) {
                    VStack {
                        Label("\(appState.history.todayWordCount) words", systemImage: "pen")
                        Text("Words today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Label("\(appState.history.totalWordCount) words", systemImage: "doc.text")
                        Text("Total words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Section {
                Picker(
                    "Recording Hotkey",
                    selection: Binding(
                        get: { appState.settings.recordingHotkey },
                        set: { appState.updateRecordingHotkey($0) }
                    )
                ) {
                    ForEach(SettingsStore.RecordingHotkey.allCases, id: \.self) { hotkey in
                        Text("\(hotkey.symbol) \(hotkey.displayName)").tag(hotkey)
                    }
                }

                Text("Long press = hold mode · Short press = toggle mode")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Cancel Recording")
                    Spacer()
                    Text("Esc")
                        .foregroundColor(.secondary)
                }

                if appState.isHotkeyReady {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Global hotkey is active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            appState.hotkeyErrorMessage ?? "Hotkey setup is incomplete.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundColor(.orange)
                        .font(.caption)

                        HStack {
                            Button("Open Accessibility Settings") {
                                appState.openAccessibilitySettings()
                            }
                            Button("Retry Hotkey Setup") {
                                appState.retryHotkeySetup()
                            }
                        }
                    }
                }
            }

            Section {
                Toggle(
                    "Text Processing (LLM)",
                    isOn: Binding(
                        get: { appState.settings.textProcessingEnabled },
                        set: { newValue in
                            Task {
                                await appState.setTextProcessingEnabled(newValue)
                            }
                        }
                    ))

                if appState.settings.textProcessingEnabled {
                    textProcessingStatusView

                    Picker(
                        "Preset",
                        selection: Binding(
                            get: { appState.settings.textProcessingPreset },
                            set: { appState.settings.textProcessingPreset = $0 }
                        )
                    ) {
                        ForEach(TextProcessingPreset.allCases) { preset in
                            Text("\(preset.displayName) (\(preset.localizedDisplayName))")
                                .tag(preset)
                        }
                    }

                    if appState.settings.textProcessingPreset == .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom Prompt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(
                                text: Binding(
                                    get: { appState.settings.customTextProcessingPrompt },
                                    set: { appState.settings.customTextProcessingPrompt = $0 }
                                )
                            )
                            .frame(minHeight: 60, maxHeight: 120)
                            .font(.body)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    HStack {
                        Text("Model")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Qwen3.5-4B (4-bit, thinking off)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Toggle(
                    "Sound Feedback",
                    isOn: Binding(
                        get: { appState.settings.soundFeedbackEnabled },
                        set: { appState.settings.soundFeedbackEnabled = $0 }
                    ))

                Picker(
                    "Language",
                    selection: Binding(
                        get: { appState.settings.language },
                        set: { appState.settings.language = $0 }
                    )
                ) {
                    Text("Auto").tag("auto")
                    Text("English").tag("en")
                    Text("Japanese").tag("ja")
                    Text("Chinese").tag("zh")
                }

                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { appState.settings.appearanceMode },
                        set: { appState.settings.appearanceMode = $0 }
                    )
                ) {
                    ForEach(SettingsStore.AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker(
                    "ASR Model",
                    selection: Binding(
                        get: { appState.selectedModelForUI },
                        set: { newVariant in
                            Task {
                                await appState.switchModel(newVariant)
                            }
                        }
                    )
                ) {
                    ForEach(ASRModelVariant.allCases, id: \.self) { variant in
                        Text("\(variant.displayName) (\(variant.estimatedSize))").tag(variant)
                    }
                }
                .disabled(
                    appState.recordingState != .idle || appState.transcriptionEngine.isLoading)

                Picker(
                    "Microphone",
                    selection: Binding(
                        get: { appState.settings.selectedMicrophoneID },
                        set: { appState.settings.selectedMicrophoneID = $0 }
                    )
                ) {
                    Text("System Default").tag(nil as String?)
                    ForEach(cachedMicrophones, id: \.id) { mic in
                        Text(mic.name).tag(mic.id as String?)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            cachedMicrophones = AudioCaptureManager.availableMicrophones()
        }
    }

    @ViewBuilder
    private var textProcessingStatusView: some View {
        if appState.textProcessingEngine.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(appState.textProcessingEngine.loadingProgress)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        } else if appState.textProcessingEngine.isModelLoaded {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("Text processing ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        if appState.transcriptionEngine.isLoading {
            return .orange
        } else if !appState.isHotkeyReady {
            return .orange
        } else if appState.transcriptionEngine.isModelLoaded {
            return .green
        } else {
            return .gray
        }
    }

    private var statusText: String {
        if appState.transcriptionEngine.isLoading {
            return appState.transcriptionEngine.loadingProgress
        } else if !appState.isHotkeyReady {
            return "Hotkey setup required"
        } else if appState.transcriptionEngine.isModelLoaded {
            return "Ready to record"
        } else {
            return "Model not loaded"
        }
    }
}
