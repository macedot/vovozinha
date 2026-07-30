// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoDescribeKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "PhotoDescribeKit", targets: ["PhotoDescribeKit"])
    ],
    dependencies: [
        .package(path: "../VovoUI"),
        // Shared on-device Qwen pack store / download gate (same Application Support path).
        .package(path: "../StoryPromptKit"),
        .package(path: "../../../mlx-swift"),
        .package(path: "../../../mlx-swift-lm"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "PhotoDescribeKit",
            dependencies: [
                "VovoUI",
                "StoryPromptKit",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/PhotoDescribeKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PhotoDescribeKitTests",
            dependencies: ["PhotoDescribeKit"],
            path: "Tests/PhotoDescribeKitTests"
        )
    ]
)
