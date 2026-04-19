//  TranscriptionEngine.swift
//  VibingSpeech

import Foundation
import Observation
import Qwen3ASR

private actor TranscriptionModelStore {
    private var model: Qwen3ASRModel?

    func loadModel(_ variant: ASRModelVariant) async throws {
        let loadedModel = try await Qwen3ASRModel.fromPretrained(modelId: variant.modelId)
        model = loadedModel
    }

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        languageHint: String?,
        context: String?
    ) -> String {
        guard let model else {
            return ""
        }

        return model.transcribe(
            audio: audio,
            sampleRate: sampleRate,
            language: languageHint,
            context: context
        )
    }
}

@Observable @MainActor final class TranscriptionEngine {
    private let modelStore = TranscriptionModelStore()

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

        do {
            try await modelStore.loadModel(variant)
            currentVariant = variant
            isModelLoaded = true
            loadingProgress = "Ready"
        } catch {
            if !isModelLoaded {
                currentVariant = nil
            }
            loadingProgress = "Failed to load model: \(error.localizedDescription)"
            throw error
        }
    }

    func transcribe(
        audio: [Float],
        sampleRate: Int = 16000,
        languageHint: String? = nil,
        context: String? = nil
    ) async -> String {
        let result = await modelStore.transcribe(
            audio: audio,
            sampleRate: sampleRate,
            languageHint: languageHint,
            context: context
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
