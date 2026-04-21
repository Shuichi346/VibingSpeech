//  KeyCodeConstants.swift
//  VibingSpeech

import CoreGraphics

enum KeyCode: UInt16 {
    case rightOption = 61
    case leftControl = 59
    case escape = 53
    case v = 9

    static let commandMask: CGEventFlags = .maskCommand
}
