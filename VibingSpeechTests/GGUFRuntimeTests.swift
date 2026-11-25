import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import VibingSpeech

final class GGUFRuntimeTests: XCTestCase {
    func testVerifiedHuggingFaceSnapshotLoadsWithoutNetwork() async throws {
        let fixture = try CacheFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cache = GGUFCache(root: fixture.directory)
        let downloaded = try await cache.download(model: fixture.model)
        XCTAssertEqual(downloaded, fixture.snapshot)
        XCTAssertEqual(try Data(contentsOf: downloaded), fixture.content)
        XCTAssertEqual(downloaded.resolvingSymlinksInPath(), fixture.blob)
    }

    func testInvalidRepositoryAndFilenameAreRejectedBeforeNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = GGUFCache(root: root)
        for model in [
            GGUFModel(repository: "../escape", filename: "model.gguf"),
            GGUFModel(repository: "owner/repo", filename: "../model.gguf"),
            GGUFModel(repository: "owner/repo", filename: "/absolute.gguf"),
            GGUFModel(repository: "owner/repo?token=value", filename: "model.gguf")
        ] {
            do {
                _ = try await cache.download(model: model)
                XCTFail("Unsafe model location was accepted")
            } catch GGUFRuntimeError.invalidModel {
                // Invalid locations must fail without creating cache paths or contacting the Hub.
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testPortFallbackAuthenticationAndOwnedProcessShutdown() async throws {
        let fixture = try ServerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let listener = try LoopbackListener()
        defer { listener.close() }
        let fallback = try LoopbackListener()
        let fallbackPort = fallback.port
        fallback.close()
        let owned = LocalLlamaServer(executableURL: fixture.executable, ports: [listener.port, fallbackPort])
        do {
            try await owned.start(modelURL: fixture.directory.appendingPathComponent("model.gguf"))
            let response = try await owned.request(
                path: "/v1/chat/completions", body: Data("{\"input\":\"hello\"}".utf8))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
            let echo = try XCTUnwrap(object["echo"] as? [String: String])
            XCTAssertEqual(echo["input"], "hello")
            await owned.stop()
            XCTAssertTrue(listener.isOpen, "Stopping an owned server must preserve another application's listener")
            let released = try LoopbackListener(port: fallbackPort)
            released.close()
            do {
                _ = try await owned.request(path: "/v1/chat/completions", body: Data())
                XCTFail("Stopped server accepted a request")
            } catch GGUFRuntimeError.serverUnavailable {}
        } catch {
            await owned.stop()
            throw error
        }
    }

    func testApplicationTerminationStopsOnlyOwnedServers() async throws {
        let fixture = try ServerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let listener = try LoopbackListener()
        defer { listener.close() }
        let reservation = try LoopbackListener()
        let port = reservation.port
        reservation.close()
        let server = LocalLlamaServer(executableURL: fixture.executable, ports: [port])
        try await server.start(modelURL: fixture.directory.appendingPathComponent("model.gguf"))
        LocalLlamaServer.shutdownAll()
        XCTAssertTrue(listener.isOpen)
        let released = try LoopbackListener(port: port)
        released.close()
        await server.stop()
    }

    func testStoppingDuringStartupRejectsLateReadinessAndReleasesPort() async throws {
        let fixture = try ServerFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let reservation = try LoopbackListener()
        let port = reservation.port
        reservation.close()
        let server = LocalLlamaServer(executableURL: fixture.executable, ports: [port])
        let startup = Task {
            try await server.start(modelURL: fixture.directory.appendingPathComponent("delayed.gguf"))
        }
        try await Task.sleep(for: .milliseconds(250))
        await server.stop()
        do {
            try await startup.value
            XCTFail("A stopped startup became ready")
        } catch is CancellationError {}
        let released = try LoopbackListener(port: port)
        released.close()
    }
}

private struct CacheFixture {
    let directory: URL
    let model = GGUFModel(repository: "test/fixture", filename: "fixture.gguf")
    let content = Data("GGUF cache fixture".utf8)
    let blob: URL
    let snapshot: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VibingSpeech-cache-\(UUID().uuidString)")
        let hash = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let commit = String(repeating: "a", count: 40)
        let repository = directory.appendingPathComponent("models--test--fixture")
        blob = repository.appendingPathComponent("blobs/\(hash)")
        snapshot = repository.appendingPathComponent("snapshots/\(commit)/fixture.gguf")
        try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: snapshot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: blob)
        try FileManager.default.createSymbolicLink(atPath: snapshot.path, withDestinationPath: "../../blobs/\(hash)")
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent("refs"), withIntermediateDirectories: true)
        try Data(commit.utf8).write(to: repository.appendingPathComponent("refs/main"))
    }
}

private struct ServerFixture {
    let directory: URL
    let executable: URL

    init() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("Python 3 is required for the local HTTP process fixture")
        }
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VibingSpeech-server-\(UUID().uuidString)")
        executable = directory.appendingPathComponent("fake-llama")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = """
            #!/usr/bin/python3
            import http.server
            import json
            import sys
            import time
            args = sys.argv
            port = int(args[args.index('--port') + 1])
            key = args[args.index('--api-key') + 1]
            model = args[args.index('--model') + 1]
            if 'delayed' in model:
                time.sleep(5)
            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    self.respond({'data': [{'id': 'vibingspeech'}]})
                def do_POST(self):
                    body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
                    self.respond({'echo': body})
                def respond(self, body):
                    if self.headers.get('Authorization') != 'Bearer ' + key:
                        self.send_response(401)
                        self.end_headers()
                        return
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps(body).encode())
                def log_message(self, *args):
                    pass
            server = http.server.HTTPServer(('127.0.0.1', port), Handler)
            server.serve_forever()
            """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
}

private final class LoopbackListener {
    let port: UInt16
    private var descriptor: Int32
    var isOpen: Bool { descriptor >= 0 && fcntl(descriptor, F_GETFD) != -1 }

    init(port: UInt16 = 0) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw GGUFRuntimeError.noAvailablePort }
        var reuse: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw GGUFRuntimeError.noAvailablePort
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            throw GGUFRuntimeError.noAvailablePort
        }
        self.port = UInt16(bigEndian: address.sin_port)
        self.descriptor = descriptor
    }

    func close() {
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1
    }

    deinit { close() }
}
