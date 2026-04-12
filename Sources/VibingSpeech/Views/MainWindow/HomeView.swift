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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recording Hotkey")
                        Spacer()
                        Text("⌥ \(appState.settings.recordingHotkey.displayName)")
                            .foregroundColor(.secondary)
                    }
                    Text("Long press = hold mode · Short press = toggle mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Translation")
                    Spacer()
                    Text("Off")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Cancel Recording")
                    Spacer()
                    Text("Esc")
                        .foregroundColor(.secondary)
                }

                Toggle("Text Polish", isOn: Binding(
                    get: { appState.settings.textPolishEnabled },
                    set: { appState.settings.textPolishEnabled = $0 }
                ))
                Toggle("Sound Feedback", isOn: Binding(
                    get: { appState.settings.soundFeedbackEnabled },
                    set: { appState.settings.soundFeedbackEnabled = $0 }
                ))

                Picker("Language", selection: Binding(
                    get: { appState.settings.language },
                    set: { appState.settings.language = $0 }
                )) {
                    Text("Auto").tag("auto")
                    Text("English").tag("en")
                    Text("Japanese").tag("ja")
                    Text("Chinese").tag("zh")
                }

                Picker("Appearance", selection: Binding(
                    get: { appState.settings.appearanceMode },
                    set: { appState.settings.appearanceMode = $0 }
                )) {
                    ForEach(SettingsStore.AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("ASR Model", selection: Binding(
                    get: { appState.settings.selectedModel },
                    set: {
                        appState.settings.selectedModel = $0
                    }
                )) {
                    ForEach(ASRModelVariant.allCases, id: \.self) { variant in
                        Text("\(variant.displayName) (\(variant.estimatedSize))").tag(variant)
                    }
                }
                .onChange(of: appState.settings.selectedModel) { _, newVariant in
                    Task {
                        try? await appState.switchModel(newVariant)
                    }
                }

                Picker("Microphone", selection: Binding(
                    get: { appState.settings.selectedMicrophoneID },
                    set: { appState.settings.selectedMicrophoneID = $0 }
                )) {
                    Text("System Default").tag(nil as String?)
                    ForEach(AudioCaptureManager.availableMicrophones(), id: \.id) { mic in
                        Text(mic.name).tag(mic.id as String?)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
        } else if appState.transcriptionEngine.isModelLoaded {
            return .green
        } else {
            return .gray
        }
    }

    private var statusText: String {
        if appState.transcriptionEngine.isLoading {
            return appState.transcriptionEngine.loadingProgress
        } else if appState.transcriptionEngine.isModelLoaded {
            return "Ready to record"
        } else {
            return "Model not loaded"
        }
    }
}
