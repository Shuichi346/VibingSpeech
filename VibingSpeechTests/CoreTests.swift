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
        XCTAssertTrue(prompt.contains("English"))
        XCTAssertTrue(prompt.contains("Fix recognition mistakes"))
    }

    func testLanguageNormalization() {
        XCTAssertEqual(LanguageMode.normalized("en"), .english)
        XCTAssertEqual(LanguageMode.normalized("ja"), .japanese)
        XCTAssertEqual(LanguageMode.normalized("zh"), .chinese)
        XCTAssertEqual(LanguageMode.normalized("unknown"), .auto)
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
}
