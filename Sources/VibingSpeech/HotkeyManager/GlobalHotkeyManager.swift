//  GlobalHotkeyManager.swift
//  VibingSpeech

import AppKit
import CoreGraphics
import Observation

enum GlobalHotkeyError: LocalizedError, Sendable {
    case accessibilityPermissionRequired
    case failedToCreateEventTap

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required to use the global hotkey."
        case .failedToCreateEventTap:
            return "Failed to start the global hotkey monitor."
        }
    }
}

@Observable final class GlobalHotkeyManager: @unchecked Sendable {
    @MainActor var onHotkeyDown: (() -> Void)?
    @MainActor var onHotkeyUp: (() -> Void)?
    @MainActor var onEscapePressed: (() -> Void)?

    private(set) var isRunning = false
    private(set) var lastErrorMessage: String?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeyCode: UInt16 = KeyCode.rightOption.rawValue
    private var isHotkeyHeld = false

    init() {}

    func start(keyCode: UInt16) throws {
        stop()
        self.hotkeyCode = keyCode
        lastErrorMessage = nil

        guard PermissionChecker.isAccessibilityGranted else {
            isRunning = false
            lastErrorMessage =
                GlobalHotkeyError.accessibilityPermissionRequired.localizedDescription
            throw GlobalHotkeyError.accessibilityPermissionRequired
        }

        let eventMask =
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)

        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    manager.handleEvent(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            isRunning = false
            lastErrorMessage = GlobalHotkeyError.failedToCreateEventTap.localizedDescription
            throw GlobalHotkeyError.failedToCreateEventTap
        }

        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
    }

    func stop() {
        isHotkeyHeld = false
        isRunning = false

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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoverEventTap()
            return
        }

        if type == .flagsChanged {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

            // flagsChangedイベントのkeyCodeは実際に変化したキーを示す。
            // これにより左右の修飾キーを正確に区別できる。
            // 例: 右Option = 61, 左Option = 58, 左Control = 59, 右Control = 62
            guard keyCode == hotkeyCode else { return }

            // keyCodeが一致するflagsChangedイベントが来た = そのキーの状態が変わった。
            // isHotkeyHeldのトグルで押下/離脱を判定する。
            if !isHotkeyHeld {
                isHotkeyHeld = true
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyDown?()
                }
            } else {
                isHotkeyHeld = false
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyUp?()
                }
            }
        } else if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Int64(KeyCode.escape.rawValue) {
                DispatchQueue.main.async { [weak self] in
                    self?.onEscapePressed?()
                }
            }
        }
    }

    private func recoverEventTap() {
        guard let eventTap else { return }

        if isHotkeyHeld {
            isHotkeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyUp?()
            }
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    deinit {
        stop()
    }
}
