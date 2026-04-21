//  TextProcessingEngine.swift
//  VibingSpeech

import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Observation
import Tokenizers

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

    /// LLMでテキストを後処理する。
    /// - Parameters:
    ///   - text: 文字起こし結果のテキスト
    ///   - preset: 処理プリセット
    ///   - detectedLanguage: 正規化済み言語コード ("ja", "en", "zh", "fr", "unknown" 等)
    ///   - asrLanguage: ASRモデルが返した生の言語名 ("japanese", "french" 等)。
    ///                  ja/zh/en 以外の言語指示を生成する際に使用。
    ///   - customPrompt: カスタムプリセット用のユーザー定義プロンプト
    /// - Returns: 後処理済みテキスト
    func processText(
        _ text: String,
        preset: TextProcessingPreset,
        detectedLanguage: String,
        asrLanguage: String? = nil,
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
            systemPrompt = preset.systemPrompt(
                detectedLanguage: detectedLanguage,
                asrLanguage: asrLanguage
            )
        }

        let generateParameters = GenerateParameters(
            maxTokens: 2048,
            temperature: 0.7,
            topP: 0.8,
            topK: 20,
            minP: 0.0,
            presencePenalty: 1.5,
            presenceContextSize: 64
        )

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: generateParameters,
            additionalContext: ["enable_thinking": false]
        )

        let result = try await session.respond(to: text)

        let cleaned = stripThinkTags(result.trimmingCharacters(in: .whitespacesAndNewlines))
        return cleaned.isEmpty ? text : cleaned
    }

    /// <think>...</think> タグを除去する
    private func stripThinkTags(_ text: String) -> String {
        var result = text
        while let thinkStart = result.range(of: "<think>") {
            if let thinkEnd = result.range(
                of: "</think>", range: thinkStart.upperBound..<result.endIndex)
            {
                let endIdx = thinkEnd.upperBound
                let afterEnd = result[endIdx...].drop(while: { $0.isWhitespace || $0.isNewline })
                result =
                    String(result[result.startIndex..<thinkStart.lowerBound]) + String(afterEnd)
            } else {
                result = String(result[result.startIndex..<thinkStart.lowerBound])
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
