//
//  KeyCodeConstants.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import CoreGraphics

enum KeyCode: UInt16 {
    case rightOption = 61
    case leftControl = 59
    case escape = 53
    case v = 9

    static let commandMask: CGEventFlags = .maskCommand
}
