//  ArchitectureCheck.swift
//  VibingSpeech

import AppKit

enum ArchitectureCheck {
    static var isAppleSilicon: Bool {
        #if arch(arm64)
            return true
        #else
            return false
        #endif
    }

    @MainActor
    static func ensureAppleSilicon() {
        guard !isAppleSilicon else { return }

        let alert = NSAlert()
        alert.messageText = "VibingSpeech requires Apple Silicon (M1 or later)."
        alert.informativeText = "This Mac is not supported."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()

        NSApp.terminate(nil)
    }
}
