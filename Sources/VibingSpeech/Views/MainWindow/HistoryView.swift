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
    /// Tracks which record IDs have their original text expanded.
    @State private var expandedOriginalIDs: Set<UUID> = []

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

                    Picker(
                        "",
                        selection: Binding(
                            get: { appState.settings.historyRetention },
                            set: { appState.settings.historyRetention = $0 }
                        )
                    ) {
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
                    let grouped = Dictionary(
                        grouping: appState.history.records, by: { $0.formattedDate })
                    ForEach(grouped.keys.sorted(by: >), id: \.self) { date in
                        Section(header: Text(date)) {
                            ForEach(grouped[date] ?? []) { record in
                                historyRow(for: record)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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

    @ViewBuilder
    private func historyRow(for record: TranscriptionRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(record.formattedTime)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                // Main text (LLM-processed if applicable, otherwise raw)
                Text(record.text)
                    .lineLimit(nil)
                    .textSelection(.enabled)

                // Show original text toggle when LLM processing was applied
                if let originalText = record.originalText {
                    let isExpanded = expandedOriginalIDs.contains(record.id)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedOriginalIDs.remove(record.id)
                            } else {
                                expandedOriginalIDs.insert(record.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Text("Original transcription")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.borderless)

                    if isExpanded {
                        Text(originalText)
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                            .padding(.vertical, 2)
                            .overlay(
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.3))
                                    .frame(width: 2),
                                alignment: .leading
                            )
                    }
                }

                HStack(spacing: 8) {
                    Text("\(record.wordCount) words")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if record.wasProcessedByLLM {
                        Text("LLM")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.7))
                            )
                    }
                }
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
