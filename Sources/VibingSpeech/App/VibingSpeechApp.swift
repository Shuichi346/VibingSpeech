//  VibingSpeechApp.swift
//  VibingSpeech

import SwiftUI

@main
struct VibingSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
