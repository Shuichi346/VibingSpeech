import AppKit
import AppIntents
import XCTest
@testable import VibingSpeech

final class CoreTests: XCTestCase {
    func testASRModelVariantMetadata() {
        XCTAssertEqual(ASRModelVariant.allCases.count, 2)
        XCTAssertEqual(ASRModelVariant.graniteSpeech5.huggingFaceModelID,
                       "vladers/granite-speech-5.0-470m-turboctc-GGUF")
        XCTAssertEqual(ASRModelVariant.graniteSpeech5.filename,
                       "granite-speech-5.0-470m-turboctc-Q8_0.gguf")
        XCTAssertEqual(ASRModelVariant.qwen3_1_7b_8bit.huggingFaceModelID,
                       "handy-computer/Qwen3-ASR-1.7B-gguf")
        XCTAssertEqual(ASRModelVariant.qwen3_1_7b_8bit.filename, "Qwen3-ASR-1.7B-Q8_0.gguf")
        XCTAssertEqual(LiveASRModel.huggingFaceModelID,
                       "handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf")
        XCTAssertEqual(LiveASRModel.filename, "nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf")
    }

    @MainActor
    func testSettingsPreserveFinalModelAndLiveTranscription() {
        let name = "VibingSpeech-model-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("qwen3_1_7b_8bit", forKey: "asrModelVariant")
        defaults.set(true, forKey: "liveTranscriptionEnabled")
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.asrModelVariant, .qwen3_1_7b_8bit)
        XCTAssertTrue(settings.liveTranscriptionEnabled)
        settings.save()
        XCTAssertEqual(defaults.string(forKey: "asrModelVariant"), "qwen3_1_7b_8bit")
    }

    func testPromptGenerationUsesSelectedLanguage() {
        let prompt = TextProcessingPreset.fixTypos.systemPrompt(detectedLanguage: "ja", selectedLanguage: .english)
        XCTAssertTrue(prompt.contains("Write the output in English."))
        XCTAssertFalse(prompt.contains("Write the output in Japanese."))
        XCTAssertTrue(prompt.contains("Correct only obvious transcription errors"))
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

    func testBulletPointFormattingMarksPlainNotesWithoutAddingHeading() {
        let output = BulletPointFormatter.normalized("Maybe next week.  \n\nOnly if the images are ready.\nKeep the price unchanged.")
        XCTAssertEqual(output, "- Maybe next week.\n- Only if the images are ready.\n- Keep the price unchanged.")
    }

    func testBulletPointFormattingKeepsHeadingAndNormalizesMarkers() {
        let output = BulletPointFormatter.normalized("買い物  \n\n* 牛乳2本\n\n・卵6個\n- パンは買わない  ")
        XCTAssertEqual(output, "買い物\n\n- 牛乳2本\n- 卵6個\n- パンは買わない")
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
        XCTAssertEqual(WordCounter.count("Swift と GGUF"), 3)
        XCTAssertEqual(WordCounter.count("今日は晴れです Hello world"), 9)
    }

    func testLiveLanguageUsesNemotronLocalesIncludingExplicitAuto() {
        XCTAssertEqual(LiveASRModel.language(for: .auto), "auto")
        XCTAssertEqual(LiveASRModel.language(for: .english), "en-US")
        XCTAssertEqual(LiveASRModel.language(for: .japanese), "ja-JP")
        XCTAssertEqual(LiveASRModel.language(for: .chinese), "zh-CN")
    }

    @MainActor
    func testNativeLiveSnapshotsReplaceTentativeTextAndResetWithoutAddingSpaces() {
        let state = RecordingOverlayState()
        state.resetLiveTranscript(visible: true)
        state.applyLiveTranscript(LiveTranscriptSnapshot(
            finalizedText: "ガレージ", partialText: "バント", statusMessage: nil
        ))
        state.applyLiveTranscript(LiveTranscriptSnapshot(
            finalizedText: "ガレージ", partialText: "バンド", statusMessage: nil
        ))
        XCTAssertEqual(state.liveFinalizedText + state.livePartialText, "ガレージバンド")
        state.resetLiveTranscript(visible: false)
        XCTAssertEqual(state.liveFinalizedText, "")
        XCTAssertEqual(state.livePartialText, "")
        XCTAssertFalse(state.liveTranscriptVisible)
    }

    func testTextProcessingSendsNonThinkingQwenTextRequest() throws {
        XCTAssertEqual(TextProcessingService.modelIdentifier, "unsloth/Qwen3-4B-Instruct-2507-GGUF")
        XCTAssertEqual(TextProcessingService.modelFilename, "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
        let body = TextProcessingBackend.requestBody(text: "helo", systemPrompt: "Fix typos.")
        let data = try JSONSerialization.data(withJSONObject: body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["max_tokens"] as? Int, 16_384)
        XCTAssertEqual((json["temperature"] as? NSNumber)?.floatValue, 0.7)
        XCTAssertEqual((json["top_p"] as? NSNumber)?.floatValue, 0.8)
        XCTAssertEqual(json["top_k"] as? Int, 20)
        XCTAssertEqual((json["min_p"] as? NSNumber)?.floatValue, 0)
        XCTAssertEqual((json["presence_penalty"] as? NSNumber)?.floatValue, 0)
        XCTAssertEqual((json["repeat_penalty"] as? NSNumber)?.floatValue, 1)
        XCTAssertNil(json["chat_template_kwargs"], "Instruct 2507 has no thinking mode to disable")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "system", "content": "Fix typos."], ["role": "user", "content": "helo"]])
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
