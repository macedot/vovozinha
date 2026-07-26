// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VovoUI",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "VovoUI", targets: ["VovoUI"])
    ],
    targets: [
        .target(
            name: "VovoUI",
            path: "Sources/VovoUI",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
