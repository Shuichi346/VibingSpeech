//
//  SoundFeedback.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

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
