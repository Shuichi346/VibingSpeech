import Foundation
import XCTest
@testable import TranscribeRuntime

@MainActor
final class StreamingTests: XCTestCase {
    func testCancelAndUnloadAreSafeBeforeLoading() async throws {
        let stream = GGUFStreamingTranscriber()
        await stream.cancel()
        await stream.unload()
        do {
            try await stream.start(language: "ja-JP")
            XCTFail("Starting without a model must fail")
        } catch GGUFTranscriptionError.modelNotLoaded { }
    }

    func testFeedAndFinishRequireASession() async throws {
        let stream = GGUFStreamingTranscriber()
        do {
            _ = try await stream.feed(samples: [0])
            XCTFail("Feeding without a session must fail")
        } catch GGUFTranscriptionError.modelNotLoaded { }
        do {
            _ = try await stream.finish()
            XCTFail("Finishing without a session must fail")
        } catch GGUFTranscriptionError.modelNotLoaded { }
    }

    func testRealNemotronStreamEmitsBeforeEndAndFlushesTail() async throws {
        let fixture = try RealFixture()
        let stream = GGUFStreamingTranscriber()
        try await stream.load(modelURL: fixture.model)
        do {
            for language in ["ja-JP", "auto"] {
                try await stream.start(language: language)
                var firstTextOffset: Int?
                var committedCount = 0
                for offset in stride(from: 0, to: fixture.samples.count, by: 1_600) {
                    let end = min(offset + 1_600, fixture.samples.count)
                    let update = try await stream.feed(samples: Array(fixture.samples[offset..<end]))
                    let text = update.committedText + update.pendingText
                    if !text.isEmpty, firstTextOffset == nil { firstTextOffset = end }
                    committedCount = max(committedCount, update.committedText.count)
                }
                let final = try await stream.finish()
                XCTAssertNotNil(firstTextOffset)
                XCTAssertLessThan(firstTextOffset ?? fixture.samples.count, fixture.samples.count)
                XCTAssertFalse(final.committedText.isEmpty)
                XCTAssertGreaterThanOrEqual(final.committedText.count, committedCount)
                XCTAssertEqual(final.pendingText, "")
                XCTAssertFalse(final.committedText.contains("<ja-JP>"))
                XCTAssertFalse(final.committedText.contains("<lang-"))
            }
            await stream.unload()
        } catch {
            await stream.unload()
            throw error
        }
    }

    func testRealCancellationDrainsAndPreservesModelForRestart() async throws {
        let fixture = try RealFixture()
        let stream = GGUFStreamingTranscriber()
        try await stream.load(modelURL: fixture.model)
        try await stream.start(language: "ja-JP")
        let pending = Task {
            try await stream.feed(samples: Array(repeating: fixture.samples, count: 8).flatMap { $0 })
        }
        try await Task.sleep(for: .milliseconds(10))
        await stream.cancel()
        do {
            _ = try await pending.value
            XCTFail("Canceled native inference must not publish a late snapshot")
        } catch is CancellationError { }
        try await stream.start(language: "ja-JP")
        _ = try await stream.feed(samples: fixture.samples)
        let restarted = try await stream.finish()
        XCTAssertFalse(restarted.committedText.isEmpty)
        await stream.unload()
        do {
            _ = try await stream.feed(samples: [0])
            XCTFail("An unloaded stream must reject inference")
        } catch GGUFTranscriptionError.modelNotLoaded { }
    }
}

private struct RealFixture {
    let model: URL
    let samples: [Float]

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["VIBINGSPEECH_TEST_NEMOTRON_GGUF"],
              let audioPath = environment["VIBINGSPEECH_TEST_NEMOTRON_PCM"] else {
            throw XCTSkip("Set the Nemotron GGUF and mono 16 kHz float32 fixture paths to run native integration tests")
        }
        model = URL(fileURLWithPath: modelPath)
        let data = try Data(contentsOf: URL(fileURLWithPath: audioPath))
        guard !data.isEmpty, data.count.isMultiple(of: MemoryLayout<Float>.size) else {
            throw GGUFTranscriptionError.invalidAudio
        }
        samples = data.withUnsafeBytes { raw in
            stride(from: 0, to: raw.count, by: MemoryLayout<Float>.size).map {
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
            }
        }
    }
}
