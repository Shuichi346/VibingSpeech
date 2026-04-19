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
    private(set) var appState: AppState?
    private var isSetupComplete = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        self.appState = state

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

        overlayPanel = RecordingOverlayPanel()

        overlayPanel?.setAudioLevelProvider { [weak state] in
            return state?.audioCapture.audioLevel ?? 0
        }

        showWindow()

        Task { @MainActor in
            await state.setup()
            self.isSetupComplete = true

            state.onRecordingStateChanged = { [weak self] newState in
                guard let self = self else { return }
                self.overlayPanel?.recordingState = newState
                if newState == .idle {
                    self.overlayPanel?.hideOverlay()
                } else {
                    self.overlayPanel?.showOverlay()
                }
            }
        }
    }

    @objc @MainActor private func showWindow() {
        guard let appState else { return }

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
