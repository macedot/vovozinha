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
        // On-device LLM runtime (100% local inference). Swift API is "Early Preview".
        //
        // WORKAROUND: consumed as a LOCAL path dependency. SPM/Xcode otherwise fail on this
        // package — see https://github.com/google-ai-edge/LiteRT-LM/issues/2407 — because
        // (a) v0.14.0+ pins checksums that don't match its release binaries, and
        // (b) SPM clones to a bare mirror and runs `git lfs pull` against that mirror, which
        //     lacks the `prebuilt/*` LFS objects (only the GitHub remote has them).
        // To set up the local checkout (from repo root):
        //   git clone -b v0.13.1 https://github.com/google-ai-edge/LiteRT-LM.git ../LiteRT-LM
        //   ./scripts/setup_litert_xcframeworks.sh
        // Package uses local .xcframeworks/CLiteRTLM*.xcframework (not remote SPM artifacts).
        .package(path: "../../../LiteRT-LM")
    ],
    targets: [
        .target(
            name: "StoryPromptKit",
            dependencies: [
                "VovoUI",
                // LiteRT-LM is for physical iOS devices only (linked on the iOS platform).
                .product(name: "LiteRTLM", package: "LiteRT-LM", condition: .when(platforms: [.iOS]))
            ],
            path: "Sources/StoryPromptKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "StoryPromptKitTests",
            dependencies: ["StoryPromptKit"],
            path: "Tests/StoryPromptKitTests"
        )
    ]
)
