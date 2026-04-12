//
//  HistoryView.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import SwiftUI

struct HistoryView: View {
    @Bindable var appState: AppState
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save History")
                            .font(.headline)
                        Text("How long to keep dictation history on device?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Picker("", selection: Binding(
                        get: { appState.settings.historyRetention },
                        set: { appState.settings.historyRetention = $0 }
                    )) {
                        ForEach(SettingsStore.HistoryRetention.allCases, id: \.self) { retention in
                            Text(retention.displayName).tag(retention)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }

            Section {
                if appState.history.records.isEmpty {
                    ContentUnavailableView(
                        "No transcription history",
                        systemImage: "clock",
                        description: Text("Your transcriptions will appear here")
                    )
                } else {
                    let grouped = Dictionary(grouping: appState.history.records, by: { $0.formattedDate })
                    ForEach(grouped.keys.sorted(by: >), id: \.self) { date in
                        Section(header: Text(date)) {
                            ForEach(grouped[date] ?? []) { record in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(record.formattedTime)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 50, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.text)
                                            .lineLimit(nil)
                                            .textSelection(.enabled)
                                        Text("\(record.wordCount) words")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        appState.history.delete(record)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") {
                    showClearConfirmation = true
                }
                .disabled(appState.history.records.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear all history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                appState.history.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
