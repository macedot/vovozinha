// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StoryPromptKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "StoryPromptKit", targets: ["StoryPromptKit"])
    ],
    dependencies: [
        .package(path: "../VovoUI")
    ],
    targets: [
        .target(
            name: "StoryPromptKit",
            dependencies: ["VovoUI"],
            path: "Sources/StoryPromptKit"
        ),
        .testTarget(
            name: "StoryPromptKitTests",
            dependencies: ["StoryPromptKit"],
            path: "Tests/StoryPromptKitTests"
        )
    ]
)
