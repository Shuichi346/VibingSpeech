//
//  AppDelegate.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var overlayPanel: RecordingOverlayPanel?
    private(set) var appState: AppState!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            self.appState = AppState()

            ArchitectureCheck.ensureAppleSilicon()

            NSApp.setActivationPolicy(.accessory)

            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.image = NSImage(
                systemSymbolName: "mic.fill", accessibilityDescription: "VibingSpeech")

            let menu = NSMenu()
            menu.addItem(
                NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(
                NSMenuItem(title: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q"))

            statusItem?.menu = menu

            // Setup overlay panel
            overlayPanel = RecordingOverlayPanel()

            // Wire audio level: the panel's internal timer reads this on each tick.
            // No separate polling timer needed in AppDelegate.
            overlayPanel?.setAudioLevelProvider { [weak self] in
                // audioLevel is @MainActor, but this closure is called from MainActor context
                // (OverlayState's timer dispatches to MainActor before calling updateBars)
                return self?.appState.audioCapture.audioLevel ?? 0
            }

            // Setup app state
            await appState.setup()

            // Show main window on launch
            showWindow()

            // Setup state observation
            appState.onRecordingStateChanged = { [weak self] state in
                guard let self = self else { return }
                self.overlayPanel?.recordingState = state
                if state == .idle {
                    self.overlayPanel?.hideOverlay()
                } else {
                    self.overlayPanel?.showOverlay()
                }
            }
        }
    }

    @objc @MainActor private func showWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "VibingSpeech"
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: MainContentView(appState: appState))
            mainWindow = window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
