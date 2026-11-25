// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TranscribeRuntime",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TranscribeRuntime", targets: ["TranscribeRuntime"])
    ],
    targets: [
        .binaryTarget(
            name: "CTranscribe",
            url:
                "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.4.2/TranscribeCpp.xcframework.zip",
            checksum: "650a42ee7836558d3047f328078be2b8a8d4c6e9f6a0a3f4ea145481ad1c1a86"
        ),
        .target(name: "TranscribeRuntime", dependencies: ["CTranscribe"]),
        .testTarget(name: "TranscribeRuntimeTests", dependencies: ["TranscribeRuntime"]),
    ]
)
