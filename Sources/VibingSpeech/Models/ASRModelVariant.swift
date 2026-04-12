//
//  ASRModelVariant.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import Foundation

enum ASRModelVariant: String, CaseIterable, Codable, Identifiable {
    case qwen3_0_6b_8bit
    case qwen3_1_7b_4bit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen3_0_6b_8bit: return "Qwen3-ASR 0.6B (8-bit)"
        case .qwen3_1_7b_4bit: return "Qwen3-ASR 1.7B (4-bit)"
        }
    }

    var modelId: String {
        switch self {
        case .qwen3_0_6b_8bit: return "aufklarer/Qwen3-ASR-0.6B-MLX-8bit"
        case .qwen3_1_7b_4bit: return "aufklarer/Qwen3-ASR-1.7B-MLX-4bit"
        }
    }

    var estimatedSize: String {
        switch self {
        case .qwen3_0_6b_8bit: return "~1.0 GB"
        case .qwen3_1_7b_4bit: return "~2.1 GB"
        }
    }

    var estimatedMemory: String {
        switch self {
        case .qwen3_0_6b_8bit: return "~1.5 GB"
        case .qwen3_1_7b_4bit: return "~3.5 GB"
        }
    }

    static var defaultVariant: ASRModelVariant { .qwen3_0_6b_8bit }
}
