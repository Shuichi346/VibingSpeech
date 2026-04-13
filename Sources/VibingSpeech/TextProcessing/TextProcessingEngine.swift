//
//  TextProcessingEngine.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/13.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import Foundation
import MLXLLM
import MLXLMCommon
import Observation

@Observable @MainActor final class TextProcessingEngine {
    private var modelContainer: ModelContainer?
    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var loadingProgress = ""

    static let modelId = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    static let estimatedSize = "~2.5 GB"
    static let estimatedMemory = "~3.5 GB"

    init() {}

    func loadModel() async throws {
        if isModelLoaded { return }

        isLoading = true
        loadingProgress = "Loading text processing model..."

        defer {
            isLoading = false
        }

        do {
            let configuration = ModelConfiguration(id: Self.modelId)
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { progress in
                Task { @MainActor [weak self] in
                    let pct = Int(progress.fractionCompleted * 100)
                    self?.loadingProgress = "Downloading text processing model... \(pct)%"
                }
            }
            isModelLoaded = true
            loadingProgress = "Text processing ready"
        } catch {
            loadingProgress = "Failed to load text processing model"
            throw error
        }
    }

    func unloadModel() {
        modelContainer = nil
        isModelLoaded = false
        loadingProgress = ""
    }

    /// Process text using the LLM with the given preset and detected language.
    ///
    /// - Parameters:
    ///   - text: The transcribed text to process
    ///   - preset: The processing preset to use
    ///   - detectedLanguage: Language code detected from transcription (e.g. "ja", "en", "zh")
    ///   - customPrompt: Custom system prompt (used only when preset is .custom)
    /// - Returns: The processed text
    func processText(
        _ text: String,
        preset: TextProcessingPreset,
        detectedLanguage: String,
        customPrompt: String = ""
    ) async throws -> String {
        guard let container = modelContainer else {
            return text
        }

        let systemPrompt: String
        if preset == .custom {
            if customPrompt.isEmpty {
                return text
            }
            systemPrompt = customPrompt
        } else {
            systemPrompt = preset.systemPrompt(detectedLanguage: detectedLanguage)
        }

        // Qwen3-4B-Instruct-2507 recommended parameters:
        // Temperature=0.7, TopP=0.8, TopK=20, MinP=0
        let generateParameters = GenerateParameters(
            maxTokens: 2048,
            temperature: 0.7,
            topP: 0.8,
            topK: 20,
            minP: 0.0,
            repetitionPenalty: 1.05,
            repetitionContextSize: 64
        )

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: generateParameters
        )

        let result = try await session.respond(to: text)

        // Clean up the result: remove any leading/trailing whitespace
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }
}
