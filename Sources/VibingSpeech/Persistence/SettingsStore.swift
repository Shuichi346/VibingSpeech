//
//  SettingsStore.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import Foundation
import Observation

@Observable @MainActor final class SettingsStore {
    enum HistoryRetention: String, CaseIterable, Codable {
        case forever, oneWeek, oneDay, never

        var displayName: String {
            switch self {
            case .forever: return "Forever"
            case .oneWeek: return "1 Week"
            case .oneDay: return "1 Day"
            case .never: return "Never"
            }
        }
    }

    enum AppearanceMode: String, CaseIterable, Codable {
        case system, light, dark

        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    enum RecordingHotkey: String, CaseIterable, Codable {
        case rightOption, leftControl

        var displayName: String {
            switch self {
            case .rightOption: return "Right Option"
            case .leftControl: return "Left Control"
            }
        }
    }

    var selectedModel: ASRModelVariant {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel")
        }
    }

    var soundFeedbackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundFeedbackEnabled, forKey: "soundFeedbackEnabled")
        }
    }

    var textProcessingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(textProcessingEnabled, forKey: "textProcessingEnabled")
        }
    }

    var textProcessingPreset: TextProcessingPreset {
        didSet {
            UserDefaults.standard.set(textProcessingPreset.rawValue, forKey: "textProcessingPreset")
        }
    }

    var customTextProcessingPrompt: String {
        didSet {
            UserDefaults.standard.set(
                customTextProcessingPrompt, forKey: "customTextProcessingPrompt")
        }
    }

    var historyRetention: HistoryRetention {
        didSet {
            UserDefaults.standard.set(historyRetention.rawValue, forKey: "historyRetention")
        }
    }

    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
    }

    var selectedMicrophoneID: String? {
        didSet {
            UserDefaults.standard.set(selectedMicrophoneID, forKey: "selectedMicrophoneID")
        }
    }

    var recordingHotkey: RecordingHotkey {
        didSet {
            UserDefaults.standard.set(recordingHotkey.rawValue, forKey: "recordingHotkey")
        }
    }

    var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "language")
        }
    }

    init() {
        // Load saved values or use defaults
        if let rawModel = UserDefaults.standard.string(forKey: "selectedModel"),
            let model = ASRModelVariant(rawValue: rawModel)
        {
            self.selectedModel = model
        } else {
            self.selectedModel = .defaultVariant
        }

        self.soundFeedbackEnabled = UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")

        if UserDefaults.standard.object(forKey: "textProcessingEnabled") != nil {
            self.textProcessingEnabled = UserDefaults.standard.bool(forKey: "textProcessingEnabled")
        } else {
            self.textProcessingEnabled = false
        }

        if let rawPreset = UserDefaults.standard.string(forKey: "textProcessingPreset"),
            let preset = TextProcessingPreset(rawValue: rawPreset)
        {
            self.textProcessingPreset = preset
        } else {
            self.textProcessingPreset = .fixTypos
        }

        self.customTextProcessingPrompt =
            UserDefaults.standard.string(forKey: "customTextProcessingPrompt") ?? ""

        if let rawRetention = UserDefaults.standard.string(forKey: "historyRetention"),
            let retention = HistoryRetention(rawValue: rawRetention)
        {
            self.historyRetention = retention
        } else {
            self.historyRetention = .forever
        }

        if let rawAppearance = UserDefaults.standard.string(forKey: "appearanceMode"),
            let appearance = AppearanceMode(rawValue: rawAppearance)
        {
            self.appearanceMode = appearance
        } else {
            self.appearanceMode = .system
        }

        self.selectedMicrophoneID = UserDefaults.standard.string(forKey: "selectedMicrophoneID")

        if let rawHotkey = UserDefaults.standard.string(forKey: "recordingHotkey"),
            let hotkey = RecordingHotkey(rawValue: rawHotkey)
        {
            self.recordingHotkey = hotkey
        } else {
            self.recordingHotkey = .rightOption
        }

        if let savedLanguage = UserDefaults.standard.string(forKey: "language") {
            self.language = savedLanguage
        } else {
            self.language = "auto"
        }
    }
}
