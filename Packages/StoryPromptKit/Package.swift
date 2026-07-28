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
        // Local mlx-swift (Prism or stock checkout). Prefer local over remote 0.31.6+ because
        // remote mlx-swift’s host CudaBuild/encuda tool fails under Xcode 27 + Swift 6 when
        // building the iOS app (ArgumentParser Sendable). 4-bit Qwen packs work on Prism kernels.
        //
        // Setup once from repo root:
        //   ./scripts/setup_mlx_local.sh
        .package(path: "../../../mlx-swift"),
        .package(path: "../../../mlx-swift-lm"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.0"),
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
                .product(name: "Tokenizers", package: "swift-transformers"),
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
