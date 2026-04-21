//  SoundFeedback.swift
//  VibingSpeech

import AppKit

enum SoundFeedback {
    static func playStartSound(isEnabled: Bool = true) {
        guard isEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    static func playStopSound(isEnabled: Bool = true) {
        guard isEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    static func playErrorSound(isEnabled: Bool = true) {
        guard isEnabled else { return }
        NSSound(named: "Basso")?.play()
    }
}
