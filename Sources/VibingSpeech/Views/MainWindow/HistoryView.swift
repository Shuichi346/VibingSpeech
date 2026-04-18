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
    @State private var searchText = ""

    private var filteredRecords: [TranscriptionRecord] {
        if searchText.isEmpty {
            return appState.history.records
        }
        return appState.history.records.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedRecords: [(String, [TranscriptionRecord])] {
        let grouped = Dictionary(grouping: filteredRecords) { $0.formattedDate }
        let order = ["Today", "Yesterday"]
        return grouped.sorted { lhs, rhs in
            let lhsIdx = order.firstIndex(of: lhs.key) ?? Int.max
            let rhsIdx = order.firstIndex(of: rhs.key) ?? Int.max
            if lhsIdx != rhsIdx {
                return lhsIdx < rhsIdx
            }
            guard let lhsFirst = lhs.value.first, let rhsFirst = rhs.value.first else {
                return lhs.key < rhs.key
            }
            return lhsFirst.timestamp > rhsFirst.timestamp
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.accentColor)
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
                            set: {
                                appState.settings.historyRetention = $0
                                appState.history.pruneIfNeeded(retention: $0)
                            }
                        )
                    ) {
                        ForEach(SettingsStore.HistoryRetention.allCases, id: \.self) { retention in
                            Text(retention.displayName).tag(retention)
                        }
                    }
                    .frame(width: 120)
                }
            }

            Section {
                HStack {
                    TextField("Search history...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(appState.history.records.isEmpty)
                    .alert("Clear All History?", isPresented: $showClearConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear All", role: .destructive) {
                            appState.history.clearAll()
                        }
                    } message: {
                        Text("This action cannot be undone.")
                    }
                }
            }

            if filteredRecords.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No transcription history",
                        systemImage: "clock",
                        description: Text(
                            searchText.isEmpty
                                ? "Transcriptions will appear here after recording"
                                : "No results matching \"\(searchText)\""
                        )
                    )
                }
            } else {
                ForEach(groupedRecords, id: \.0) { dateLabel, records in
                    Section(header: Text(dateLabel)) {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.text)
                                            .lineLimit(nil)
                                            .textSelection(.enabled)

                                        if let original = record.originalText {
                                            Text("Original: \(original)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
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
                                HStack(spacing: 12) {
                                    Text(record.formattedTime)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(record.wordCount) words")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if record.wasProcessedByLLM {
                                        Text("LLM")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.15))
                                            .cornerRadius(3)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
