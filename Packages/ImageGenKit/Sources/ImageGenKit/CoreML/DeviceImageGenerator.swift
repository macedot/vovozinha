import Foundation
import CoreGraphics

#if canImport(StableDiffusion)
import StableDiffusion
#endif

/// Production entry point for on-device img2img.
///
/// Resolves the Core ML image pack via `CoreMLImagePackStore`, resizes the source photo
/// into the nearest model bucket, then delegates to a `CoreMLImageGenSessioning`.
///
/// A missing pack → `.packNotInstalled`; a pack without VAEEncoder → `.vaeEncoderMissing`;
/// an empty/undecodable photo → `.invalidImage`. Generation failure is never fabricated —
/// it surfaces as `.generationFailed`.
public struct DeviceImageGenerator: ImageGenerating {
    private let packStore: CoreMLImagePackStore
    private let sessionProvider: @Sendable (URL) throws -> any CoreMLImageGenSessioning
    private let modelSize: ImageGenModelSize

    /// - Parameters:
    ///   - packStore: Owns the on-device Core ML pack.
    ///   - modelSize: Native side length of the backing model (SD1.5 = 512; SDXL = 1024).
    public init(
        packStore: CoreMLImagePackStore = CoreMLImagePackStore(),
        modelSize: ImageGenModelSize = .sd15
    ) {
        self.init(
            packStore: packStore,
            modelSize: modelSize,
            sessionProvider: DeviceImageGenerator.defaultSessionProvider
        )
    }

    /// Injectable seam for tests (internal). Production callers use the convenience init above.
    init(
        packStore: CoreMLImagePackStore,
        modelSize: ImageGenModelSize,
        sessionProvider: @escaping @Sendable (URL) throws -> any CoreMLImageGenSessioning
    ) {
        self.packStore = packStore
        self.modelSize = modelSize
        self.sessionProvider = sessionProvider
    }

    public func generate(_ input: ImageGenInput, config: ImageGenConfig) async throws -> ImageGenResult {
        guard await packStore.isPackPresent() else { throw ImageGenError.packNotInstalled }

        let resourcesURL = await packStore.resourcesDirectory()
        let session = try sessionProvider(resourcesURL)
        let negative = config.negativePrompt.isEmpty
            ? ImageGenTemplate.defaultNegativePrompt
            : config.negativePrompt

        switch config.mode {
        case .textToImage:
            guard await packStore.supportsTextToImage() else { throw ImageGenError.generationFailed }
            return try await session.generate(
                from: nil,
                prompt: config.prompt,
                negativePrompt: negative,
                config: config,
                modelSize: modelSize
            )

        case .imageToImage:
            guard !input.isEmpty, let source = input.makeCGImage() else {
                throw ImageGenError.invalidImage
            }
            guard await packStore.supportsImageToImage() else { throw ImageGenError.vaeEncoderMissing }
            guard let resized = ImageResizer.resize(source, toBucket: config.bucket, modelSize: modelSize) else {
                throw ImageGenError.invalidImage
            }
            return try await session.generate(
                from: resized.cgImage,
                prompt: config.prompt,
                negativePrompt: negative,
                config: config.bucket == resized.bucket ? config : withBucket(config, resized.bucket),
                modelSize: modelSize
            )
        }
    }

    /// Default session provider — real `CoreMLImageGenSession` when SD is linked.
    static func defaultSessionProvider(url: URL) throws -> any CoreMLImageGenSessioning {
        #if canImport(StableDiffusion)
        return CoreMLImageGenSession(resourcesURL: url)
        #else
        throw ImageGenError.generationFailed
        #endif
    }

    private func withBucket(_ config: ImageGenConfig, _ bucket: ImageGenBucket) -> ImageGenConfig {
        var c = config
        c.bucket = bucket
        return c
    }
}
