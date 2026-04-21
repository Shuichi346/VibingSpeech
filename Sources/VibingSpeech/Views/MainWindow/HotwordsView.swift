//  HotwordsView.swift
//  VibingSpeech

import SwiftUI

struct HotwordsView: View {
    @Bindable var appState: AppState
    @State private var newHotword = ""

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top) {
                    Image(systemName: "text.badge.plus")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hotword Enhancement")
                            .font(.headline)
                        Text("Add proper nouns, terms, names to improve recognition accuracy.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    TextField("Enter new hotword...", text: $newHotword)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        appState.hotwords.add(newHotword)
                        newHotword = ""
                    }
                    .disabled(newHotword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section {
                if appState.hotwords.hotwords.isEmpty {
                    ContentUnavailableView(
                        "No manual hotwords",
                        systemImage: "text.badge.plus",
                        description: Text("Add proper nouns in the field above")
                    )
                } else {
                    List {
                        ForEach(appState.hotwords.hotwords) { hotword in
                            HStack {
                                Text(hotword.text)
                                Spacer()
                                Button(role: .destructive) {
                                    appState.hotwords.delete(hotword)
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
        .formStyle(.grouped)
    }
}
