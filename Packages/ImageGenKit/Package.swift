// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageGenKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "ImageGenKit", targets: ["ImageGenKit"])
    ],
    dependencies: [
        .package(path: "../VovoUI"),
        // Local checkout of apple/ml-stable-diffusion 1.1.1. That release vendors
        // BPETokenizer and no longer depends on swift-transformers, so this kit can
        // share a graph with StoryPromptKit (transformers 1.x via MLX).
        .package(path: "../../../ml-stable-diffusion"),
        // Native libcompression unzip for the multi-GB Core ML image pack.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "ImageGenKit",
            dependencies: [
                "VovoUI",
                .product(name: "StableDiffusion", package: "ml-stable-diffusion"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/ImageGenKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ImageGenKitTests",
            dependencies: ["ImageGenKit"],
            path: "Tests/ImageGenKitTests"
        )
    ]
)
