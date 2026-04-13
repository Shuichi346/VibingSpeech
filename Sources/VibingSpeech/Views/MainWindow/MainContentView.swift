//
//  MainContentView.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import SwiftUI

struct MainContentView: View {
    @Bindable var appState: AppState
    @State private var selectedTab: Tab = .home

    enum Tab: Hashable {
        case home
        case hotwords
        case history

        var title: String {
            switch self {
            case .home: return "VibingSpeech"
            case .hotwords: return "Hotwords"
            case .history: return "History"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Home", systemImage: "house")
                    .tag(Tab.home)
                Label("Hotwords", systemImage: "text.badge.plus")
                    .tag(Tab.hotwords)
                Label("History", systemImage: "clock")
                    .tag(Tab.history)
            }
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case .home:
                HomeView(appState: appState)
            case .hotwords:
                HotwordsView(appState: appState)
            case .history:
                HistoryView(appState: appState)
            }
        }
        .navigationTitle(selectedTab.title)
        .frame(minWidth: 700, minHeight: 500)
        .preferredColorScheme(appState.settings.appearanceMode.colorScheme())
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
}

extension SettingsStore.AppearanceMode {
    func colorScheme() -> ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
