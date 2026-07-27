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
        // On-device LLM: Prism MLX (1-bit kernels) + mlx-swift-lm.
        //
        // WORKAROUND: both packages are LOCAL path dependencies so we can point mlx-swift-lm
        // at the Prism 1-bit mlx-swift fork (remote SPM would pin ml-explore/mlx-swift and
        // collide on package identity).
        //
        // One-time setup from the vovozinha repo root:
        //   ./scripts/setup_bonsai_mlx.sh
        // This clones:
        //   ../../mlx-swift      (PrismML-Eng/mlx-swift @ prism)
        //   ../../mlx-swift-lm  (ml-explore/mlx-swift-lm, patched to use path mlx-swift)
        .package(path: "../../../mlx-swift"),
        .package(path: "../../../mlx-swift-lm"),
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
