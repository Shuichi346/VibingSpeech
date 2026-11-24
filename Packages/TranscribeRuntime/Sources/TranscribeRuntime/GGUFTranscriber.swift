import CTranscribe
import Foundation

public enum GGUFTranscriptionError: LocalizedError {
    case modelNotLoaded
    case invalidAudio
    case nativeFailure(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "The GGUF speech model is not loaded."
        case .invalidAudio:
            "Speech recognition requires nonempty, finite mono 16 kHz audio."
        case .nativeFailure(let message):
            "transcribe.cpp: \(message)"
        }
    }
}

/// Owns one native model and serializes every native operation away from the main actor.
public actor GGUFTranscriber {
    private let storage = NativeModelStorage()
    private var pending: Task<Void, Never>?
    private var operations: [UUID: NativeCancellation] = [:]

    public init() {}

    public func load(modelURL: URL) async throws {
        cancelOperations()
        try await enqueue { storage, cancellation in
            try storage.load(modelURL: modelURL, cancellation: cancellation)
        }
    }

    /// Passes the entire captured mono 16 kHz buffer to one native inference call.
    public func transcribe(
        samples: [Float], language: String? = nil, context: String = ""
    ) async throws -> (text: String, language: String?) {
        try await enqueue { storage, cancellation in
            try storage.transcribe(samples: samples, language: language, context: context, cancellation: cancellation)
        }
    }

    public func unload() async {
        cancelOperations()
        let previous = pending
        let storage = storage
        let task = Task.detached {
            await previous?.value
            storage.unload()
        }
        pending = task
        // Native resources remain alive until any interrupted computation has returned.
        await task.value
    }

    /// Interrupts and drains pending work without releasing an already loaded model.
    public func cancelPendingTranscription() async {
        cancelOperations()
        await pending?.value
    }

    private func cancelOperations() {
        for cancellation in operations.values {
            cancellation.cancel()
        }
    }

    private func enqueue<Result: Sendable>(
        _ operation: @escaping @Sendable (NativeModelStorage, NativeCancellation) throws -> Result
    ) async throws -> Result {
        let id = UUID()
        let cancellation = NativeCancellation()
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
            return result
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private final class NativeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false

    var isCanceled: Bool {
        lock.withLock { canceled }
    }

    func cancel() {
        lock.withLock { canceled = true }
    }

    func check() throws {
        if isCanceled { throw CancellationError() }
    }
}

/// Access is confined to the actor's ordered chain of detached tasks.
private final class NativeModelStorage: @unchecked Sendable {
    private var model: OpaquePointer?
    private var modelURL: URL?

    deinit {
        transcribe_model_free(model)
    }

    func load(modelURL: URL, cancellation: NativeCancellation) throws {
        try cancellation.check()
        if self.modelURL == modelURL, model != nil { return }
        unload()
        var loaded: OpaquePointer?
        var parameters = transcribe_model_load_params()
        transcribe_model_load_params_init(&parameters)
        // AUTO selects Metal on Apple Silicon and the native CPU fallback if needed.
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

    func unload() {
        transcribe_model_free(model)
        model = nil
        modelURL = nil
    }

    func transcribe(
        samples: [Float], language: String?, context: String, cancellation: NativeCancellation
    ) throws -> (text: String, language: String?) {
        try cancellation.check()
        guard let model else { throw GGUFTranscriptionError.modelNotLoaded }
        guard !samples.isEmpty, samples.count <= Int(Int32.max), samples.allSatisfy(\.isFinite) else {
            throw GGUFTranscriptionError.invalidAudio
        }
        var session: OpaquePointer?
        let sessionStatus = transcribe_session_init(model, nil, &session)
        guard sessionStatus == TRANSCRIBE_OK, let session else {
            throw nativeError(sessionStatus)
        }
        defer { transcribe_session_free(session) }
        let cancellationPointer = Unmanaged.passUnretained(cancellation).toOpaque()
        transcribe_set_abort_callback(
            session,
            { pointer in
                guard let pointer else { return false }
                return Unmanaged<NativeCancellation>.fromOpaque(pointer).takeUnretainedValue().isCanceled
            }, cancellationPointer)
        var parameters = transcribe_run_params()
        transcribe_run_params_init(&parameters)
        parameters.keep_special_tags = false
        let supportsContext = transcribe_model_supports(model, TRANSCRIBE_FEATURE_CONTEXT_PROMPT)
        let status = (language ?? "").withCString { languagePointer in
            context.withCString { contextPointer in
                parameters.language = language == nil ? nil : languagePointer
                parameters.prompt = supportsContext && !context.isEmpty ? contextPointer : nil
                return samples.withUnsafeBufferPointer {
                    transcribe_run(session, $0.baseAddress, Int32($0.count), &parameters)
                }
            }
        }
        try cancellation.check()
        guard status == TRANSCRIBE_OK else { throw nativeError(status) }
        let text = String(cString: transcribe_full_text(session))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedLanguage = String(cString: transcribe_detected_language(session))
        return (text, detectedLanguage.isEmpty ? nil : detectedLanguage)
    }

    private func nativeError(_ status: transcribe_status) -> GGUFTranscriptionError {
        .nativeFailure(String(cString: transcribe_status_string(Int32(status.rawValue))))
    }
}
