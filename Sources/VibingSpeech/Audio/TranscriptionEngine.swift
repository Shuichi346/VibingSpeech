//
//  TranscriptionEngine.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import Foundation
import Observation
import Qwen3ASR

// import MLX

@Observable @MainActor final class TranscriptionEngine {
    private var model: Qwen3ASRModel?
    private(set) var currentVariant: ASRModelVariant?
    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var loadingProgress = ""

    init() {}

    func loadModel(_ variant: ASRModelVariant) async throws {
        if currentVariant == variant && isModelLoaded {
            return
        }

        isLoading = true
        loadingProgress = "Loading \(variant.displayName)..."

        defer {
            isLoading = false
        }

        // Unload existing model first
        model = nil
        isModelLoaded = false

        do {
            model = try await Qwen3ASRModel.fromPretrained(modelId: variant.modelId)
            currentVariant = variant
            isModelLoaded = true
            loadingProgress = "Ready"
        } catch {
            loadingProgress = "Failed to load model: \(error.localizedDescription)"
            throw error
        }
    }

    func transcribe(audio: [Float], sampleRate: Int = 16000) -> String {
        guard let model = model else {
            return ""
        }

        let result = model.transcribe(audio: audio, sampleRate: sampleRate)
        return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
