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

        let pasteboard = NSPasteboard.general
        let previousSnapshot = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let insertedChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            restorePasteboard(
                previousSnapshot,
                on: pasteboard,
                onlyIfChangeCountMatches: insertedChangeCount
            )
            return
        }

        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: KeyCode.v.rawValue,
                keyDown: true
            )
        else {
            restorePasteboard(
                previousSnapshot,
                on: pasteboard,
                onlyIfChangeCountMatches: insertedChangeCount
            )
            return
        }
        keyDown.flags.insert(KeyCode.commandMask)
        keyDown.post(tap: .cghidEventTap)

        guard
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: KeyCode.v.rawValue,
                keyDown: false
            )
        else {
            restorePasteboard(
                previousSnapshot,
                on: pasteboard,
                onlyIfChangeCountMatches: insertedChangeCount
            )
            return
        }
        keyUp.flags.insert(KeyCode.commandMask)
        keyUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            restorePasteboard(
                previousSnapshot,
                on: pasteboard,
                onlyIfChangeCountMatches: insertedChangeCount
            )
        }
    }

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[String: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [String: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type.rawValue] = data
                }
            }
        }
    }

    private static func restorePasteboard(
        _ snapshot: [[String: Data]],
        on pasteboard: NSPasteboard,
        onlyIfChangeCountMatches expectedChangeCount: Int
    ) {
        guard pasteboard.changeCount == expectedChangeCount else { return }

        pasteboard.clearContents()

        guard !snapshot.isEmpty else { return }

        let restoredItems = snapshot.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: type))
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
