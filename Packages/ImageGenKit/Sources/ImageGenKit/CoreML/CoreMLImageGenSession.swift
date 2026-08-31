import Foundation
import CoreGraphics
import os

#if canImport(StableDiffusion)
import StableDiffusion
#endif

/// Real Core ML Stable Diffusion adapter — compiled only when `StableDiffusion` is linked.
///
/// Delegates pipeline ownership + generation to `PipelineCache` (an actor) so the non-Sendable
/// `StableDiffusionPipeline` never crosses an isolation boundary. See `PipelineCache` for the
/// memory / lazy-load strategy.
public struct CoreMLImageGenSession: CoreMLImageGenSessioning {
    private let resourcesURL: URL

    public init(resourcesURL: URL) {
        self.resourcesURL = resourcesURL
    }

    #if canImport(StableDiffusion)
    public func generate(
        from sourceImage: CGImage?,
        prompt: String,
        negativePrompt: String,
        config: ImageGenConfig,
        modelSize: ImageGenModelSize
    ) async throws -> ImageGenResult {
        let outcome = try await PipelineCache.shared.generate(
            at: resourcesURL,
            startingImage: sourceImage,
            prompt: prompt,
            negativePrompt: negativePrompt,
            config: config
        )
        return ImageGenResult(
            cgImage: outcome.cgImage,
            seed: outcome.seed,
            elapsedSeconds: outcome.elapsed,
            bucket: config.bucket
        )
    }

    /// Resets the cached pipeline (e.g. after the pack is removed or swapped).
    public static func resetCache() async {
        await PipelineCache.shared.reset()
    }
    #else
    // Without StableDiffusion linked there is no real session; the default session provider
    // throws, so this path is unreachable in production.
    public func generate(
        from sourceImage: CGImage?,
        prompt: String,
        negativePrompt: String,
        config: ImageGenConfig,
        modelSize: ImageGenModelSize
    ) async throws -> ImageGenResult {
        throw ImageGenError.generationFailed
    }
    public static func resetCache() async {}
    #endif
}
