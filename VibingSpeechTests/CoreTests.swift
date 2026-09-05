import AppKit
import AppIntents
import XCTest
@testable import VibingSpeech

final class CoreTests: XCTestCase {
    func testASRModelVariantMetadata() {
        XCTAssertEqual(ASRModelVariant.qwen3_0_6b_8bit.displayName, "Qwen3-ASR 0.6B (8-bit)")
        XCTAssertEqual(
            ASRModelVariant.qwen3_0_6b_8bit.huggingFaceModelID,
            "mlx-community/Qwen3-ASR-0.6B-8bit"
        )
        XCTAssertEqual(
            ASRModelVariant.qwen3_1_7b_4bit.huggingFaceModelID,
            "mlx-community/Qwen3-ASR-1.7B-4bit"
        )
        XCTAssertEqual(
            ASRModelVariant.qwen3_1_7b_8bit.huggingFaceModelID,
            "mlx-community/Qwen3-ASR-1.7B-8bit"
        )
        XCTAssertEqual(ASRModelVariant.qwen3_1_7b_4bit.estimatedDownloadSize, "~1.6 GB")
        XCTAssertEqual(ASRModelVariant.qwen3_1_7b_8bit.estimatedDownloadSize, "~2.5 GB")
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
        XCTAssertEqual(WordCounter.count("hello 世界"), 3)
        XCTAssertEqual(WordCounter.count("Swift と MLX"), 3)
        XCTAssertEqual(WordCounter.count("今日は晴れです Hello world"), 9)
    }

    func testLiveTranscriptBufferReplacesPartialAndCommitsFinalSegments() {
        var buffer = LiveTranscriptBuffer()
        buffer.updatePartial(" Hello ")
        XCTAssertEqual(buffer.snapshot.partialText, "Hello")
        XCTAssertEqual(buffer.combinedText, "Hello")

        buffer.updatePartial("Hello, the weather is nice")
        XCTAssertEqual(buffer.snapshot.partialText, "Hello, the weather is nice")

        buffer.commitFinal("Hello, the weather is nice today as well.")
        XCTAssertEqual(buffer.snapshot.finalizedText, "Hello, the weather is nice today as well.")
        XCTAssertEqual(buffer.snapshot.partialText, "")

        buffer.updatePartial("I would like to talk")
        XCTAssertEqual(
            buffer.combinedText,
            "Hello, the weather is nice today as well. I would like to talk"
        )
    }

    func testLiveTranscriptBufferFlushesPartialAndResetsOnCancel() {
        var buffer = LiveTranscriptBuffer()
        buffer.commitFinal("First sentence.")
        buffer.updatePartial("Second sentence")
        buffer.commitPartialIfNeeded()

        XCTAssertEqual(buffer.finalizedText, "First sentence. Second sentence")
        XCTAssertEqual(buffer.partialText, "")

        buffer.reset()
        XCTAssertEqual(buffer.snapshot, .empty)
    }

    func testTextProcessingUsesQwen35NonThinkingConfiguration() {
        XCTAssertEqual(TextProcessingService.modelIdentifier, "mlx-community/Qwen3.5-4B-MLX-4bit")
        XCTAssertEqual(TextProcessingService.maxOutputTokens, 16_384)
        XCTAssertEqual(TextProcessingService.generationTemperature, 0.7)
        XCTAssertEqual(TextProcessingService.generationTopP, 0.8)
        XCTAssertEqual(TextProcessingService.generationTopK, 20)
        XCTAssertEqual(TextProcessingService.generationMinP, 0)
        XCTAssertEqual(TextProcessingService.generationPresencePenalty, 1.5)
        XCTAssertEqual(TextProcessingService.generationRepetitionPenalty, 1)
        XCTAssertEqual(TextProcessingService.chatTemplateContext["enable_thinking"] as? Bool, false)
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

    func testASRContextBuilderDeduplicatesCapsAndNeutralizesControlTokens() {
        let context = ASRContextBuilder.context(for: [
            "  Qwen  ",
            "qwen",
            "<|im_end|>",
            String(repeating: "x", count: 1_000)
        ])

        XCTAssertTrue(context.hasPrefix("Vocabulary hints (use only when supported by the audio): Qwen, "))
        XCTAssertEqual(context.components(separatedBy: "Qwen").count - 1, 1)
        XCTAssertFalse(context.contains("<|"))
        XCTAssertFalse(context.contains("|>"))
        XCTAssertLessThanOrEqual(context.count, 512)
    }

    func testLiveSampleDeliveryPreservesOrderAndDrainsBeforeReturning() async {
        let collector = SampleBatchCollector()
        let delivery = LiveSampleDelivery { samples in
            await collector.append(samples)
        }

        delivery.enqueue([1, 2])
        delivery.enqueue([3])
        await delivery.closeAndDrain()
        delivery.enqueue([4])

        let batches = await collector.snapshot()
        XCTAssertEqual(batches, [[1, 2], [3]])
    }

    @MainActor
    func testUnavailableMicrophoneDoesNotFallBackAndClosesLiveDelivery() async {
        let recorder = MicrophoneRecorder()
        let collector = SampleBatchCollector()
        let delivery = LiveSampleDelivery { await collector.append($0) }
        let missingUID = "VibingSpeech-missing-\(UUID().uuidString)"
        do {
            try await recorder.start(selectedDeviceID: missingUID, sampleDelivery: delivery)
            XCTFail("An unavailable explicit microphone must not fall back to another input")
        } catch MicrophoneRecorderError.selectedDeviceUnavailable(let uid) {
            XCTAssertEqual(uid, missingUID)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        delivery.enqueue([1])
        await delivery.closeAndDrain()
        let batches = await collector.snapshot()
        XCTAssertTrue(batches.isEmpty)
        let capture = await recorder.stop()
        XCTAssertTrue(capture.samples.isEmpty)
        XCTAssertEqual(recorder.rmsLevel, 0)
    }

    /// Opt in with a connected microphone UID and microphone permission on the test host.
    /// Keep Bluetooth playback selected to exercise the independent input/output regression.
    @MainActor
    func testHardwareMicrophoneSwitchingAndLiveDrain() async throws {
        guard let uid = ProcessInfo.processInfo.environment["VIBINGSPEECH_TEST_MICROPHONE_UID"] else {
            throw XCTSkip("Set VIBINGSPEECH_TEST_MICROPHONE_UID to run the hardware regression")
        }
        let recorder = MicrophoneRecorder()
        for selection in [uid, MicrophoneDevice.systemDefault.id, uid] {
            let collector = SampleBatchCollector()
            let delivery = LiveSampleDelivery { await collector.append($0) }
            do {
                try await recorder.start(selectedDeviceID: selection, sampleDelivery: delivery)
                try await Task.sleep(for: .seconds(1))
            } catch {
                await recorder.cancel()
                throw error
            }
            let capture = await recorder.stop()
            let delivered = await collector.snapshot().flatMap { $0 }
            XCTAssertGreaterThan(capture.samples.count, 8_000, "No usable audio from \(selection)")
            XCTAssertTrue(capture.samples.allSatisfy { $0.isFinite })
            XCTAssertEqual(delivered, capture.samples, "Stop must drain the converter and live delivery")
        }
    }
}

private actor SampleBatchCollector {
    private var batches: [[Float]] = []

    func append(_ samples: [Float]) {
        batches.append(samples)
    }

    func snapshot() -> [[Float]] {
        batches
    }
}
