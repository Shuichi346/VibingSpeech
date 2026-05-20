import AppKit
import AppIntents
import XCTest
@testable import VibingSpeech

final class CoreTests: XCTestCase {
    func testASRModelVariantMetadata() {
        XCTAssertEqual(ASRModelVariant.qwen3_0_6b_8bit.displayName, "Qwen3-ASR 0.6B (8-bit)")
        XCTAssertEqual(ASRModelVariant.qwen3_1_7b_4bit.huggingFaceModelID, "aufklarer/Qwen3-ASR-1.7B-MLX-4bit")
        XCTAssertEqual(ASRModelVariant.qwen3_1_7b_8bit.estimatedDownloadSize, "~2.3 GB")
        XCTAssertEqual(ASRModelVariant.qwen3_1_7b_8bit.estimatedMemory, "~3.5 GB")
    }

    func testPromptGenerationUsesSelectedLanguage() {
        let prompt = TextProcessingPreset.fixTypos.systemPrompt(detectedLanguage: "ja", selectedLanguage: .english)
        XCTAssertTrue(prompt.contains("Write the output in English."))
        XCTAssertFalse(prompt.contains("Write the output in Japanese."))
        XCTAssertTrue(prompt.contains("Fix misrecognized words"))
    }

    func testPromptGenerationUsesDetectedLanguageOnlyForAuto() {
        let prompt = TextProcessingPreset.bulletPoints.systemPrompt(detectedLanguage: "language ja", selectedLanguage: .auto)
        XCTAssertTrue(prompt.contains("Write the output in Japanese."))
    }

    func testPromptGenerationFallsBackWhenAutoDetectionIsUnavailable() {
        let prompt = TextProcessingPreset.fixTypos.systemPrompt(detectedLanguage: nil, selectedLanguage: .auto)
        XCTAssertTrue(prompt.contains("Use the same language as the input transcription."))
    }

    func testLanguageNormalization() {
        XCTAssertEqual(LanguageMode.normalized("en"), .english)
        XCTAssertEqual(LanguageMode.normalized("ja"), .japanese)
        XCTAssertEqual(LanguageMode.normalized("zh"), .chinese)
        XCTAssertEqual(LanguageMode.normalized("language ja"), .japanese)
        XCTAssertEqual(LanguageMode.normalized("unknown"), .auto)
    }

    func testASRLanguageHints() {
        XCTAssertNil(LanguageMode.auto.asrLanguageHint)
        XCTAssertEqual(LanguageMode.english.asrLanguageHint, "en")
        XCTAssertEqual(LanguageMode.japanese.asrLanguageHint, "ja")
        XCTAssertEqual(LanguageMode.chinese.asrLanguageHint, "zh")
    }

    func testWordCountingWhitespaceAndCJK() {
        XCTAssertEqual(WordCounter.count("The weather is sunny"), 4)
        XCTAssertEqual(WordCounter.count("今日は晴れです"), 7)
        XCTAssertEqual(WordCounter.count("明日は雨?"), 4)
    }

    func testThinkingBlocksAreStripped() {
        XCTAssertEqual(TextProcessingService.stripThinkingBlocks(from: "A<think>hidden</think>B"), "AB")
        XCTAssertEqual(TextProcessingService.stripThinkingBlocks(from: "<THINK>x</think> Visible"), " Visible")
    }

    func testUnsupportedQwen35DeltaNetConfigIsRejectedBeforeGeneration() throws {
        let configData = Data("""
        {
          "model_type": "qwen3_5",
          "quantization": { "bits": 4 },
          "text_config": {
            "hidden_size": 2560,
            "num_hidden_layers": 32,
            "num_attention_heads": 16,
            "num_key_value_heads": 4,
            "head_dim": 256,
            "intermediate_size": 9216,
            "vocab_size": 248320,
            "max_position_embeddings": 262144,
            "rms_norm_eps": 0.000001,
            "eos_token_id": 248044,
            "full_attention_interval": 4,
            "layer_types": ["linear_attention", "full_attention"],
            "linear_num_key_heads": 16,
            "linear_key_head_dim": 128,
            "linear_num_value_heads": 32,
            "linear_value_head_dim": 128,
            "linear_conv_kernel_dim": 4,
            "rope_parameters": {
              "rope_theta": 10000000,
              "partial_rotary_factor": 0.25
            },
            "tie_word_embeddings": true
          }
        }
        """.utf8)

        XCTAssertThrowsError(
            try TextProcessingModelDirectory.normalizedConfigData(from: configData)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Qwen3Chat currently supports the 0.8B DeltaNet layout"))
        }
    }

    func testSupportedNestedQwen35ConfigIsNormalizedForTextProcessing() throws {
        let configData = Data("""
        {
          "model_type": "qwen3_5",
          "quantization": { "bits": 4 },
          "text_config": {
            "hidden_size": 1024,
            "num_hidden_layers": 24,
            "num_attention_heads": 8,
            "num_key_value_heads": 2,
            "head_dim": 256,
            "intermediate_size": 3584,
            "vocab_size": 248320,
            "max_position_embeddings": 262144,
            "rms_norm_eps": 0.000001,
            "eos_token_id": 248044,
            "full_attention_interval": 4,
            "layer_types": ["linear_attention", "full_attention"],
            "linear_num_key_heads": 16,
            "linear_key_head_dim": 128,
            "linear_num_value_heads": 16,
            "linear_value_head_dim": 128,
            "linear_conv_kernel_dim": 4,
            "rope_parameters": {
              "rope_theta": 10000000,
              "partial_rotary_factor": 0.25
            },
            "tie_word_embeddings": true
          }
        }
        """.utf8)
        let tokenizerData = Data("""
        {
          "added_tokens": [
            { "id": 248044, "content": "<|endoftext|>" },
            { "id": 248046, "content": "<|im_end|>" }
          ]
        }
        """.utf8)

        let normalizedData = try XCTUnwrap(
            TextProcessingModelDirectory.normalizedConfigData(from: configData, tokenizerData: tokenizerData)
        )
        let normalized = try XCTUnwrap(
            JSONSerialization.jsonObject(with: normalizedData) as? [String: Any]
        )

        XCTAssertEqual(normalized["model_type"] as? String, "qwen3_5_text")
        XCTAssertEqual(normalized["hidden_size"] as? Int, 1024)
        XCTAssertEqual(normalized["num_hidden_layers"] as? Int, 24)
        XCTAssertEqual(normalized["max_seq_len"] as? Int, 262144)
        XCTAssertEqual(normalized["quantization"] as? String, "int4")
        XCTAssertEqual(normalized["eos_token_id"] as? Int, 248046)
        XCTAssertEqual(normalized["pad_token_id"] as? Int, 248044)
        XCTAssertEqual(normalized["partial_rotary_factor"] as? Double, 0.25)
    }

    func testFlatQwen35ConfigDoesNotNeedRuntimeNormalization() throws {
        let configData = Data("""
        {
          "hidden_size": 1024,
          "num_hidden_layers": 24
        }
        """.utf8)

        XCTAssertNil(try TextProcessingModelDirectory.normalizedConfigData(from: configData))
    }

    func testShortAudioIsRejectedBeforeASRModelUse() async {
        let service = ASRService()
        do {
            _ = try await service.transcribe(samples: [0], languageMode: .auto)
            XCTFail("Expected short audio to be rejected")
        } catch ASRServiceError.shortAudio {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
