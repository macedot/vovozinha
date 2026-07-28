// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StoryPromptKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "StoryPromptKit", targets: ["StoryPromptKit"])
    ],
    dependencies: [
        .package(path: "../VovoUI"),
        // On-device LLM: stock MLX + mlx-swift-lm (4-bit Qwen3.5 — no Prism 1-bit fork).
        // Metal shaders require Xcode / xcodebuild (and MetalToolchain on some Xcode betas).
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.31.4")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "StoryPromptKit",
            dependencies: [
                "VovoUI",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/StoryPromptKit",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: "StoryPromptKitTests",
            dependencies: ["StoryPromptKit"],
            path: "Tests/StoryPromptKitTests"
        )
    ]
)
