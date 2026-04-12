//
//  GlobalHotkeyManager.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import AppKit
import CoreGraphics
import Observation

@Observable final class GlobalHotkeyManager: @unchecked Sendable {
    @MainActor var onHotkeyDown: (() -> Void)?
    @MainActor var onHotkeyUp: (() -> Void)?
    @MainActor var onEscapePressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeyCode: UInt16 = KeyCode.rightOption.rawValue
    private var isHotkeyHeld = false

    init() {}

    func start(keyCode: UInt16) {
        self.hotkeyCode = keyCode

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
                        CGEventMask(1 << CGEventType.keyDown.rawValue) |
                        CGEventMask(1 << CGEventType.keyUp.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Accessibility permission required.")
            return
        }

        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    func updateHotkey(_ keyCode: UInt16) {
        self.hotkeyCode = keyCode
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .flagsChanged {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            if keyCode == hotkeyCode {
                let flags = event.flags
                let isOptionPressed = flags.contains(.maskAlternate)
                let isControlPressed = flags.contains(.maskControl)

                let isHotkeyActive: Bool
                if hotkeyCode == KeyCode.rightOption.rawValue {
                    isHotkeyActive = isOptionPressed
                } else if hotkeyCode == KeyCode.leftControl.rawValue {
                    isHotkeyActive = isControlPressed
                } else {
                    isHotkeyActive = false
                }

                if isHotkeyActive && !isHotkeyHeld {
                    isHotkeyHeld = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onHotkeyDown?()
                    }
                } else if !isHotkeyActive && isHotkeyHeld {
                    isHotkeyHeld = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onHotkeyUp?()
                    }
                }
            }
        } else if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == KeyCode.escape.rawValue {
                DispatchQueue.main.async { [weak self] in
                    self?.onEscapePressed?()
                }
            }
        }
    }

    deinit {
        stop()
    }
}
