// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VibingSpeech",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/soniqo/speech-swift", from: "0.0.9"),
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            exact: "2.31.3"
        ),
    ],
    targets: [
        .executableTarget(
            name: "VibingSpeech",
            dependencies: [
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/VibingSpeech",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
