// swift-tools-version: 6.0
import PackageDescription
import Foundation

func resolveSiblingPackagePath(_ relativeName: String) -> String {
    let manifestDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let candidates = [
        "../../../\(relativeName)",
        "../../../../\(relativeName)",
        "../../\(relativeName)"
    ]
    for c in candidates {
        let candidateURL = manifestDir.appendingPathComponent(c)
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            return c
        }
    }
    return "../../../\(relativeName)"
}

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
        .package(path: resolveSiblingPackagePath("mlx-swift")),
        .package(path: resolveSiblingPackagePath("mlx-swift-lm")),
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
