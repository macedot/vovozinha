// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StorybookKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "StorybookKit", targets: ["StorybookKit"])
    ],
    dependencies: [
        .package(path: "../VovoUI"),
        .package(path: "../StoryPromptKit"),
        .package(path: "../PhotoDescribeKit"),
        .package(path: "../ImageGenKit"),
    ],
    targets: [
        .target(
            name: "StorybookKit",
            dependencies: [
                "VovoUI",
                "StoryPromptKit",
                "PhotoDescribeKit",
                "ImageGenKit",
            ],
            path: "Sources/StorybookKit"
        ),
        .testTarget(
            name: "StorybookKitTests",
            dependencies: ["StorybookKit"],
            path: "Tests/StorybookKitTests"
        )
    ]
)
