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
import MLXHuggingFace
import HuggingFace
import Tokenizers
import Observation

@Observable @MainActor final class TextProcessingEngine {
    private var modelContainer: ModelContainer?
    private(set) var isModelLoaded = false
    private(set) var isLoading = false
    private(set) var loadingProgress = ""

    static let modelId = "mlx-community/Qwen3.5-4B-MLX-4bit"
    static let estimatedSize = "~2.9 GB"
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
            // mlx-swift-lm v3: use MLXHuggingFace macros for downloader and tokenizer
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
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
    /// Uses Qwen3.5-4B with thinking disabled (enable_thinking=false).
    /// Non-thinking optimal parameters:
    ///   temperature=0.7, topP=0.8, topK=20, minP=0.0,
    ///   presencePenalty=1.5, repetitionPenalty=1.0 (disabled)
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

        // Qwen3.5-4B non-thinking optimal parameters:
        // Temperature=0.7, TopP=0.8, TopK=20, MinP=0.0
        // presence_penalty=1.5, repetition_penalty=1.0 (no repetition penalty)
        let generateParameters = GenerateParameters(
            maxTokens: 2048,
            temperature: 0.7,
            topP: 0.8,
            topK: 20,
            minP: 0.0,
            presencePenalty: 1.5,
            presenceContextSize: 64
        )

        // Disable thinking mode via additionalContext
        // The Qwen3.5 chat template checks: enable_thinking is defined and enable_thinking is false
        // When false, it outputs <think>\n\n</think>\n\n which effectively skips reasoning
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: generateParameters,
            additionalContext: ["enable_thinking": false]
        )

        let result = try await session.respond(to: text)

        // Clean up the result: remove any leading/trailing whitespace
        // Also strip any residual <think>...</think> tags that might appear
        let cleaned = stripThinkTags(result.trimmingCharacters(in: .whitespacesAndNewlines))
        return cleaned.isEmpty ? text : cleaned
    }

    /// Remove <think>...</think> tags from the output, in case the model
    /// still produces them despite enable_thinking=false.
    private func stripThinkTags(_ text: String) -> String {
        // Pattern: <think> ... </think> followed by optional whitespace
        var result = text
        while let thinkStart = result.range(of: "<think>") {
            if let thinkEnd = result.range(of: "</think>", range: thinkStart.upperBound..<result.endIndex) {
                // Remove everything from <think> to </think> inclusive, plus trailing whitespace
                let endIdx = thinkEnd.upperBound
                let afterEnd = result[endIdx...].drop(while: { $0.isWhitespace || $0.isNewline })
                result = String(result[result.startIndex..<thinkStart.lowerBound]) + String(afterEnd)
            } else {
                // Unclosed <think> tag — remove from <think> to end
                result = String(result[result.startIndex..<thinkStart.lowerBound])
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
