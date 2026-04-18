//
//  PermissionChecker.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import AppKit
import AVFoundation

enum PermissionChecker {
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityIfNeeded(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard prompt else {
            return false
        }

        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
