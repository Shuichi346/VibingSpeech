import CryptoKit
import Darwin
import Foundation

struct GGUFModel: Hashable, Sendable {
    let repository: String
    let filename: String
}

enum GGUFRuntimeError: LocalizedError {
    case invalidModel
    case downloadFailed(Int)
    case invalidDownload
    case installationFailed
    case serverFailed(String)
    case noAvailablePort
    case serverUnavailable
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidModel: "The Hugging Face model metadata is invalid or the requested file is unavailable."
        case .downloadFailed(let status):
            "Model download failed (HTTP \(status)). Check your connection and Hugging Face access."
        case .invalidDownload: "The downloaded model failed its size or SHA-256 integrity check. Please retry."
        case .installationFailed:
            "llama.cpp installation failed. Install it with curl -LsSf https://llama.app/install.sh | sh, then retry."
        case .serverFailed(let reason): "The local inference server could not start. \(reason)"
        case .noAvailablePort: "All VibingSpeech inference ports are in use. Close another instance and retry."
        case .serverUnavailable: "The local inference server is not running."
        case .requestFailed(let status): "Local inference failed (HTTP \(status))."
        }
    }
}

/// Shares the Hugging Face cache layout with other clients without replacing existing blobs.
actor GGUFCache {
    static let shared = GGUFCache()
    let root: URL
    private let session: URLSession

    init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    ) {
        self.root = root
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 7_200
        session = URLSession(configuration: configuration)
    }

    func download(model: GGUFModel) async throws -> URL {
        guard Self.isSafeRepository(model.repository), Self.isSafeFilename(model.filename) else {
            throw GGUFRuntimeError.invalidModel
        }
        let repositoryRoot = root.appendingPathComponent(
            "models--" + model.repository.replacingOccurrences(of: "/", with: "--"), isDirectory: true
        )
        // Prefer an already cached, hash-verified snapshot, including when offline.
        if let cached = try await cachedFile(model: model, repositoryRoot: repositoryRoot) {
            return cached
        }
        var metadataRequest = URLRequest(
            url: URL(
                string:
                    "https://huggingface.co/api/models/\(model.repository)/revision/main?blobs=true")!)
        authorize(&metadataRequest)
        let (metadataData, response) = try await session.data(for: metadataRequest)
        try Self.checkHTTP(response)
        let metadata = try JSONDecoder().decode(RepositoryMetadata.self, from: metadataData)
        guard Self.isHex(metadata.sha, count: 40),
            let file = metadata.siblings.first(where: { $0.rfilename == model.filename }),
            let lfs = file.lfs, Self.isHex(lfs.sha256, count: 64), lfs.size > 0
        else {
            throw GGUFRuntimeError.invalidModel
        }
        let blob = repositoryRoot.appendingPathComponent("blobs/\(lfs.sha256)")
        let snapshot = repositoryRoot.appendingPathComponent("snapshots/\(metadata.sha)/\(model.filename)")
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: blob.path) {
            guard try await Self.validate(blob, sha256: lfs.sha256, size: lfs.size) else {
                // An existing corrupt blob may be in use by another app. Do not rewrite it.
                throw GGUFRuntimeError.invalidDownload
            }
        } else {
            var request = URLRequest(
                url: URL(
                    string:
                        "https://huggingface.co/\(model.repository)/resolve/\(metadata.sha)/\(model.filename)")!)
            authorize(&request)
            let (temporary, downloadResponse) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try Self.checkHTTP(downloadResponse)
            guard try await Self.validate(temporary, sha256: lfs.sha256, size: lfs.size) else {
                throw GGUFRuntimeError.invalidDownload
            }
            try Task.checkCancellation()
            try FileManager.default.createDirectory(
                at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Stage on the same volume so the final publication is an atomic rename.
            let staging = blob.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).incomplete")
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: temporary, to: staging)
            try Task.checkCancellation()
            do {
                try FileManager.default.moveItem(at: staging, to: blob)
            } catch {
                // Another client may have published the same immutable content first.
                guard try await Self.validate(blob, sha256: lfs.sha256, size: lfs.size) else { throw error }
            }
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: snapshot.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: snapshot.path) {
            let levels = model.filename.split(separator: "/").count + 1
            let relative = String(repeating: "../", count: levels) + "blobs/\(lfs.sha256)"
            do {
                try FileManager.default.createSymbolicLink(atPath: snapshot.path, withDestinationPath: relative)
            } catch {
                guard FileManager.default.fileExists(atPath: snapshot.path) else { throw error }
            }
        }
        guard snapshot.resolvingSymlinksInPath().standardizedFileURL == blob.standardizedFileURL else {
            throw GGUFRuntimeError.invalidDownload
        }
        let refs = repositoryRoot.appendingPathComponent("refs", isDirectory: true)
        try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        try Data(metadata.sha.utf8).write(to: refs.appendingPathComponent("main"), options: .atomic)
        return snapshot
    }

    private func cachedFile(model: GGUFModel, repositoryRoot: URL) async throws -> URL? {
        let reference = repositoryRoot.appendingPathComponent("refs/main")
        guard
            let revision = try? String(contentsOf: reference, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), Self.isHex(revision, count: 40)
        else { return nil }
        let snapshot = repositoryRoot.appendingPathComponent("snapshots/\(revision)/\(model.filename)")
        guard FileManager.default.fileExists(atPath: snapshot.path) else { return nil }
        let resolved = snapshot.resolvingSymlinksInPath()
        let hash = resolved.lastPathComponent
        guard
            resolved.deletingLastPathComponent().standardizedFileURL
                == repositoryRoot
                .appendingPathComponent("blobs").standardizedFileURL,
            Self.isHex(hash, count: 64), try await Self.validate(resolved, sha256: hash, size: nil)
        else { return nil }
        return snapshot
    }

    private func authorize(_ request: inout URLRequest) {
        let environment = ProcessInfo.processInfo.environment
        let tokenPath =
            environment["HF_TOKEN_PATH"].map { URL(fileURLWithPath: $0) }
            ?? URL(
                fileURLWithPath: environment["HF_HOME"]
                    ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".cache/huggingface").path
            ).appendingPathComponent("token")
        let token = environment["HF_TOKEN"] ?? (try? String(contentsOf: tokenPath, encoding: .utf8))
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty,
            !token.contains("\n"), !token.contains("\r")
        {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func validate(_ url: URL, sha256: String, size: Int64?) async throws -> Bool {
        let task = Task.detached(priority: .utility) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                let fileSize = (attributes[.size] as? NSNumber)?.int64Value,
                fileSize > 0, size == nil || fileSize == size
            else { return false }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var digest = SHA256()
            while let chunk = try file.read(upToCount: 4 * 1_024 * 1_024), !chunk.isEmpty {
                try Task.checkCancellation()
                digest.update(data: chunk)
            }
            return digest.finalize().map { String(format: "%02x", $0) }.joined() == sha256
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func checkHTTP(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw GGUFRuntimeError.invalidDownload }
        guard (200..<300).contains(response.statusCode) else {
            throw GGUFRuntimeError.downloadFailed(response.statusCode)
        }
    }

    private static func isHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func isSafeRepository(_ value: String) -> Bool {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 2
            && components.allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
                    && $0.utf8.allSatisfy {
                        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                            || [45, 46, 95].contains($0)
                    }
            }
    }

    private static func isSafeFilename(_ value: String) -> Bool {
        !value.isEmpty
            && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
                    && $0.utf8.allSatisfy {
                        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                            || [45, 46, 95].contains($0)
                    }
            }
    }

    private struct RepositoryMetadata: Decodable {
        let sha: String
        let siblings: [FileMetadata]
    }

    private struct FileMetadata: Decodable {
        let rfilename: String
        let lfs: LFSMetadata?
    }

    private struct LFSMetadata: Decodable {
        let sha256: String
        let size: Int64
    }
}

/// A single app-owned llama.cpp instance. It never attaches to a pre-existing server.
actor LocalLlamaServer {
    static let portCandidates: [UInt16] = [49_271, 49_283, 49_307, 49_319, 49_331, 49_349]
    private var process: OwnedInferenceProcess?
    private var endpoint: URL?
    private var apiKey = ""
    private var generation = UUID()
    private let session: URLSession
    private let executableOverride: URL?
    private let ports: [UInt16]

    init(executableURL: URL? = nil, ports: [UInt16] = LocalLlamaServer.portCandidates) {
        executableOverride = executableURL
        self.ports = ports
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 1_800
        session = URLSession(configuration: configuration)
    }

    func start(modelURL: URL, additionalArguments: [String] = []) async throws {
        let requestID = UUID()
        generation = requestID
        endpoint = nil
        let previous = process
        process = nil
        await previous?.stop()
        try checkGeneration(requestID)
        let executable: URL
        if let executableOverride {
            executable = executableOverride
        } else {
            executable = try await LlamaInstallation.executable()
        }
        try checkGeneration(requestID)
        var lastFailure: String?
        for port in ports {
            try checkGeneration(requestID)
            guard Self.portIsAvailable(port) else { continue }
            let key = UUID().uuidString + UUID().uuidString
            let owned = OwnedInferenceProcess()
            let arguments =
                [
                    "serve", "--model", modelURL.path,
                    "--host", "127.0.0.1", "--port", String(port), "--api-key", key,
                    "--alias", "vibingspeech", "--parallel", "1", "--no-webui", "--log-verbosity", "1"
                ]
                + additionalArguments
            try owned.run(executable: executable, arguments: arguments)
            process = owned
            let base = URL(string: "http://127.0.0.1:\(port)")!
            do {
                try await waitUntilReady(owned, endpoint: base, key: key, requestID: requestID)
                try checkGeneration(requestID)
                endpoint = base
                apiKey = key
                return
            } catch {
                let diagnostic = owned.diagnostic.replacingOccurrences(of: key, with: "[redacted]")
                await owned.stop()
                if process === owned { process = nil }
                try checkGeneration(requestID)
                if diagnostic.localizedCaseInsensitiveContains("bind")
                    || diagnostic.localizedCaseInsensitiveContains("address already in use")
                {
                    lastFailure = diagnostic
                    continue
                }
                if error is CancellationError { throw error }
                throw GGUFRuntimeError.serverFailed(diagnostic.isEmpty ? error.localizedDescription : diagnostic)
            }
        }
        if let lastFailure { throw GGUFRuntimeError.serverFailed(lastFailure) }
        throw GGUFRuntimeError.noAvailablePort
    }

    func request(path: String, body: Data) async throws -> Data {
        guard let endpoint, let process, process.isRunning,
            path.hasPrefix("/"), !path.contains("://")
        else { throw GGUFRuntimeError.serverUnavailable }
        let requestID = generation
        var request = URLRequest(url: endpoint.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        try checkGeneration(requestID)
        guard process.isRunning else { throw GGUFRuntimeError.serverUnavailable }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw GGUFRuntimeError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    func stop() async {
        generation = UUID()
        endpoint = nil
        apiKey = ""
        let previous = process
        process = nil
        await previous?.stop()
    }

    /// Termination fallback for applicationWillTerminate; only touches registered child processes.
    nonisolated static func shutdownAll() {
        InferenceProcessRegistry.shared.shutdownAll()
    }

    private func checkGeneration(_ requestID: UUID) throws {
        try Task.checkCancellation()
        guard generation == requestID else { throw CancellationError() }
    }

    private func waitUntilReady(
        _ owned: OwnedInferenceProcess, endpoint: URL, key: String, requestID: UUID
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(180)
        while ContinuousClock.now < deadline {
            try checkGeneration(requestID)
            guard owned.isRunning else { throw GGUFRuntimeError.serverUnavailable }
            var request = URLRequest(url: endpoint.appendingPathComponent("v1/models"))
            request.timeoutInterval = 1
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if let (_, response) = try? await session.data(for: request),
                let http = response as? HTTPURLResponse, http.statusCode == 200, owned.isRunning
            {
                // A different local server may ignore Authorization entirely during a bind race.
                // Confirm that this listener rejects a key other than the one assigned to our child.
                request.setValue("Bearer invalid-vibingspeech-key", forHTTPHeaderField: "Authorization")
                if let (_, challengeResponse) = try? await session.data(for: request),
                    (challengeResponse as? HTTPURLResponse)?.statusCode == 401, owned.isRunning
                {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw GGUFRuntimeError.serverFailed("Model loading timed out after 180 seconds.")
    }

    private static func portIsAvailable(_ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var reuse: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

private enum LlamaInstallation {
    static func executable() async throws -> URL {
        if let installed = findExecutable() { return installed }
        let installer = OwnedInferenceProcess()
        try installer.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c", "curl -LsSf https://llama.app/install.sh | sh"
            ])
        do {
            let deadline = ContinuousClock.now + .seconds(300)
            while installer.isRunning, ContinuousClock.now < deadline {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(200))
            }
            guard !installer.isRunning, installer.exitStatus == 0, let installed = findExecutable() else {
                await installer.stop()
                throw GGUFRuntimeError.installationFailed
            }
            installer.forceStop()
            return installed
        } catch {
            await installer.stop()
            throw error
        }
    }

    private static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [
            "/opt/homebrew/bin/llama", "/usr/local/bin/llama",
            home.appendingPathComponent(".local/bin/llama").path,
            "/Applications/Llama.app/Contents/MacOS/llama",
            home.appendingPathComponent("Applications/Llama.app/Contents/MacOS/llama").path
        ]
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .map { String($0) + "/llama" }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }
}

/// Locking is limited to diagnostic collection and the process registry, never inference state.
private final class OwnedInferenceProcess: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()
    private let lock = NSLock()
    private var tail = Data()
    private let id = UUID()
    var isRunning: Bool { process.isRunning }
    var exitStatus: Int32 { process.terminationStatus }
    var diagnostic: String {
        lock.withLock { String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func run(executable: URL, arguments: [String]) throws {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        // Inherited llama environment must not override this app's explicit model, host, or port.
        environment = environment.filter { !$0.key.hasPrefix("LLAMA_ARG_") }
        environment["PATH"] =
            "/opt/homebrew/bin:/usr/local/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            self.lock.withLock {
                self.tail.append(data)
                if self.tail.count > 8_192 { self.tail = self.tail.suffix(8_192) }
            }
        }
        do {
            try process.run()
            InferenceProcessRegistry.shared.insert(self, id: id)
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    func requestStop() {
        if process.isRunning { process.terminate() }
    }

    func stop() async {
        requestStop()
        let deadline = ContinuousClock.now + .seconds(3)
        while process.isRunning, ContinuousClock.now < deadline {
            // Shutdown must complete even if its caller was canceled.
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { break }
        }
        forceStop()
    }

    func forceStop() {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        if process.isRunning { process.waitUntilExit() }
        output.fileHandleForReading.readabilityHandler = nil
        InferenceProcessRegistry.shared.remove(id: id)
    }
}

private final class InferenceProcessRegistry: @unchecked Sendable {
    static let shared = InferenceProcessRegistry()
    private let lock = NSLock()
    private var processes: [UUID: OwnedInferenceProcess] = [:]

    func insert(_ process: OwnedInferenceProcess, id: UUID) {
        lock.withLock { processes[id] = process }
    }

    func remove(id: UUID) {
        _ = lock.withLock { processes.removeValue(forKey: id) }
    }

    func shutdownAll() {
        let owned = lock.withLock { Array(processes.values) }
        for process in owned { process.requestStop() }
        let deadline = ContinuousClock.now + .seconds(1)
        while owned.contains(where: { $0.isRunning }), ContinuousClock.now < deadline {
            usleep(10_000)
        }
        for process in owned { process.forceStop() }
    }
}
