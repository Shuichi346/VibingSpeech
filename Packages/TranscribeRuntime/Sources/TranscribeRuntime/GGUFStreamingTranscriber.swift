import CTranscribe
import Foundation

public struct GGUFStreamSnapshot: Equatable, Sendable {
    public let committedText: String
    public let pendingText: String

    public init(committedText: String, pendingText: String) {
        self.committedText = committedText
        self.pendingText = pendingText
    }
}

/// Runs a persistent native stream on an ordered worker chain, separate from final ASR.
public actor GGUFStreamingTranscriber {
    private let storage = NativeStreamingStorage()
    private var pending: Task<Void, Never>?
    private var operations: [UUID: StreamCancellation] = [:]
    private var generation = UUID()

    public init() {}

    public func load(modelURL: URL) async throws {
        invalidateOperations()
        try await enqueue { storage, cancellation in
            try storage.load(modelURL: modelURL, cancellation: cancellation)
        }
    }

    public func start(language: String) async throws {
        invalidateOperations()
        try await enqueue { storage, cancellation in
            try storage.start(language: language, cancellation: cancellation)
        }
    }

    public func feed(samples: [Float]) async throws -> GGUFStreamSnapshot {
        try await enqueue { storage, cancellation in
            try storage.feed(samples: samples, cancellation: cancellation)
        }
    }

    /// Flushes lookahead and the remaining audio before copying the final display snapshot.
    public func finish() async throws -> GGUFStreamSnapshot {
        try await enqueue { storage, cancellation in
            try storage.finish(cancellation: cancellation)
        }
    }

    /// Abandons the stream without decoding its tail, then waits for native work to stop.
    public func cancel() async {
        invalidateOperations()
        await drain { $0.reset() }
    }

    public func unload() async {
        invalidateOperations()
        await drain { $0.unload() }
    }

    private func invalidateOperations() {
        generation = UUID()
        for cancellation in operations.values {
            cancellation.cancel()
        }
    }

    private func drain(_ cleanup: @escaping @Sendable (NativeStreamingStorage) -> Void) async {
        let previous = pending
        let storage = storage
        let task = Task.detached {
            await previous?.value
            cleanup(storage)
        }
        pending = task
        // A canceled caller must still keep the session alive until the worker returns.
        await task.value
    }

    private func enqueue<Result: Sendable>(
        _ operation: @escaping @Sendable (NativeStreamingStorage, StreamCancellation) throws -> Result
    ) async throws -> Result {
        let requestID = generation
        let id = UUID()
        let cancellation = StreamCancellation()
        operations[id] = cancellation
        let previous = pending
        let storage = storage
        let task = Task.detached {
            await previous?.value
            try cancellation.check()
            return try operation(storage, cancellation)
        }
        pending = Task { _ = try? await task.value }
        defer { operations[id] = nil }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try cancellation.check()
            try Task.checkCancellation()
            guard generation == requestID else { throw CancellationError() }
            return result
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private final class StreamCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false

    var isCanceled: Bool { lock.withLock { canceled } }

    func cancel() {
        lock.withLock { canceled = true }
    }

    func check() throws {
        if isCanceled { throw CancellationError() }
    }
}

/// Only the actor's ordered detached tasks may access these native pointers.
private final class NativeStreamingStorage: @unchecked Sendable {
    private var model: OpaquePointer?
    private var session: OpaquePointer?
    private var modelURL: URL?

    deinit {
        transcribe_session_free(session)
        transcribe_model_free(model)
    }

    func load(modelURL: URL, cancellation: StreamCancellation) throws {
        try cancellation.check()
        if self.modelURL == modelURL, model != nil {
            reset()
            return
        }
        unload()
        var loaded: OpaquePointer?
        var parameters = transcribe_model_load_params()
        transcribe_model_load_params_init(&parameters)
        let status = modelURL.path.withCString {
            transcribe_model_load_file($0, &parameters, &loaded)
        }
        guard status == TRANSCRIBE_OK, let loaded else {
            transcribe_model_free(loaded)
            try cancellation.check()
            throw nativeError(status)
        }
        if cancellation.isCanceled {
            transcribe_model_free(loaded)
            throw CancellationError()
        }
        model = loaded
        self.modelURL = modelURL
    }

    func start(language: String, cancellation: StreamCancellation) throws {
        try cancellation.check()
        guard let model else { throw GGUFTranscriptionError.modelNotLoaded }
        guard !language.isEmpty else {
            throw GGUFTranscriptionError.nativeFailure("The streaming language must be explicit, including auto.")
        }
        if session == nil {
            var created: OpaquePointer?
            let status = transcribe_session_init(model, nil, &created)
            guard status == TRANSCRIBE_OK, let created else { throw nativeError(status) }
            session = created
        }
        guard let session else { throw GGUFTranscriptionError.modelNotLoaded }
        transcribe_stream_reset(session)
        guard transcribe_model_accepts_ext_kind(
            model, TRANSCRIBE_EXT_SLOT_STREAM, TRANSCRIBE_EXT_KIND_PARAKEET_STREAM
        ) else {
            throw GGUFTranscriptionError.nativeFailure("The selected model does not support Nemotron streaming.")
        }
        var runParameters = transcribe_run_params()
        transcribe_run_params_init(&runParameters)
        runParameters.timestamps = TRANSCRIBE_TIMESTAMPS_NONE
        runParameters.keep_special_tags = false
        var streamParameters = transcribe_stream_params()
        transcribe_stream_params_init(&streamParameters)
        streamParameters.commit_policy = TRANSCRIBE_STREAM_COMMIT_AUTO
        var family = transcribe_parakeet_stream_ext()
        transcribe_parakeet_stream_ext_init(&family)
        // Nemotron 3.5 is trained for R=3: 240 ms lookahead and a 320 ms encoder chunk.
        family.att_context_right = 3
        let status = try withAbort(session: session, cancellation: cancellation) {
            language.withCString { languagePointer in
                // v0.4.2 selects Nemotron's auto prompt through a null language hint.
                // The literal "auto" is rejected by the generic supported-language gate.
                runParameters.language = language == "auto" ? nil : languagePointer
                return withUnsafePointer(to: &family) { familyPointer in
                    // The C ABI reads the complete family extension through its base header.
                    streamParameters.family = UnsafeRawPointer(familyPointer)
                        .assumingMemoryBound(to: transcribe_ext.self)
                    return transcribe_stream_begin(session, &runParameters, &streamParameters)
                }
            }
        }
        guard status == TRANSCRIBE_OK else { throw nativeError(status) }
    }

    func feed(samples: [Float], cancellation: StreamCancellation) throws -> GGUFStreamSnapshot {
        guard let session else { throw GGUFTranscriptionError.modelNotLoaded }
        try cancellation.check()
        guard !samples.isEmpty, samples.count <= Int(Int32.max), samples.allSatisfy(\.isFinite) else {
            throw GGUFTranscriptionError.invalidAudio
        }
        var update = transcribe_stream_update()
        transcribe_stream_update_init(&update)
        let status = try withAbort(session: session, cancellation: cancellation) {
            samples.withUnsafeBufferPointer {
                transcribe_stream_feed(session, $0.baseAddress, Int32($0.count), &update)
            }
        }
        guard status == TRANSCRIBE_OK else { throw nativeError(status) }
        return try snapshot(session: session)
    }

    func finish(cancellation: StreamCancellation) throws -> GGUFStreamSnapshot {
        guard let session else { throw GGUFTranscriptionError.modelNotLoaded }
        var update = transcribe_stream_update()
        transcribe_stream_update_init(&update)
        let status = try withAbort(session: session, cancellation: cancellation) {
            transcribe_stream_finalize(session, &update)
        }
        guard status == TRANSCRIBE_OK else { throw nativeError(status) }
        return try snapshot(session: session)
    }

    func reset() {
        guard let session else { return }
        transcribe_stream_reset(session)
    }

    func unload() {
        transcribe_session_free(session)
        session = nil
        transcribe_model_free(model)
        model = nil
        modelURL = nil
    }

    private func withAbort<Result>(
        session: OpaquePointer, cancellation: StreamCancellation, _ operation: () -> Result
    ) throws -> Result {
        try cancellation.check()
        transcribe_set_abort_callback(
            session,
            { pointer in
                guard let pointer else { return false }
                return Unmanaged<StreamCancellation>.fromOpaque(pointer).takeUnretainedValue().isCanceled
            }, Unmanaged.passUnretained(cancellation).toOpaque()
        )
        defer { transcribe_set_abort_callback(session, nil, nil) }
        let result = operation()
        try cancellation.check()
        return result
    }

    private func snapshot(session: OpaquePointer) throws -> GGUFStreamSnapshot {
        var text = transcribe_stream_text()
        transcribe_stream_text_init(&text)
        let status = transcribe_stream_get_text(session, &text)
        guard status == TRANSCRIBE_OK else { throw nativeError(status) }
        // Copy both borrowed views before the next native call can replace their storage.
        return GGUFStreamSnapshot(
            committedText: text.committed_text.map { String(cString: $0) } ?? "",
            pendingText: text.tentative_text.map { String(cString: $0) } ?? ""
        )
    }

    private func nativeError(_ status: transcribe_status) -> GGUFTranscriptionError {
        .nativeFailure(String(cString: transcribe_status_string(Int32(status.rawValue))))
    }
}
