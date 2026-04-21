//  TranscriptionEngine.swift
//  VibingSpeech

import Foundation
import Observation
import Qwen3ASR

/// ASRモデルの保持と推論をMainActorから分離するアクター
private actor TranscriptionModelStore {
    private var model: Qwen3ASRModel?

    func loadModel(_ variant: ASRModelVariant) async throws {
        let loadedModel = try await Qwen3ASRModel.fromPretrained(modelId: variant.modelId)
        model = loadedModel
    }

    /// 音声を文字起こしし、テキストとASRが検出した言語を返す
    func transcribe(
        audio: [Float],
        sampleRate: Int,
        languageHint: String?,
        context: String?
    ) -> (text: String, detectedLanguage: String?) {
        guard let model else {
            return (text: "", detectedLanguage: nil)
        }

        let result = model.transcribeWithLanguage(
            audio: audio,
            sampleRate: sampleRate,
            language: languageHint
        )
        return (text: result.text, detectedLanguage: result.language)
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

    /// 音声を文字起こしし、テキストとASR検出言語を返す
    func transcribe(
        audio: [Float],
        sampleRate: Int = 16000,
        languageHint: String? = nil,
        context: String? = nil
    ) async -> (text: String, detectedLanguage: String?) {
        let result = await modelStore.transcribe(
            audio: audio,
            sampleRate: sampleRate,
            languageHint: languageHint,
            context: context
        )
        return (
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: result.detectedLanguage
        )
    }
}
