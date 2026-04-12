//
//  TextInsertionService.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import AppKit
import CoreGraphics

enum TextInsertionService {
    static func insertText(_ text: String) {
        guard !text.isEmpty else { return }

        // Save current clipboard contents
        let previousContents = NSPasteboard.general.pasteboardItems?.compactMap { item in
            item.types.reduce(into: [String: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type.rawValue] = data
                }
            }
        }

        // Set new text to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Simulate Cmd+V
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // Key down
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: KeyCode.v.rawValue,
            keyDown: true
        ) else { return }
        keyDown.flags.insert(KeyCode.commandMask)
        keyDown.post(tap: .cghidEventTap)

        // Key up
        guard let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: KeyCode.v.rawValue,
            keyDown: false
        ) else { return }
        keyUp.flags.insert(KeyCode.commandMask)
        keyUp.post(tap: .cghidEventTap)

        // Restore clipboard after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previousContents = previousContents {
                NSPasteboard.general.clearContents()
                for item in previousContents {
                    let pasteboardItem = NSPasteboardItem()
                    for (type, data) in item {
                        pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(rawValue: type))
                    }
                    NSPasteboard.general.writeObjects([pasteboardItem])
                }
            }
        }
    }
}
