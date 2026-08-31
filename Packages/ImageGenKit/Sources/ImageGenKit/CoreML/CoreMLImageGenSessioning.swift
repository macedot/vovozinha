import Foundation
import CoreGraphics

#if canImport(StableDiffusion)
import StableDiffusion
#endif

/// Testable seam over the Core ML Stable Diffusion pipeline.
///
/// A session owns a loaded pipeline for a given pack `Resources/` URL and runs a single
/// img2img generation. The real implementation (`CoreMLImageGenSession`) is compiled only
/// when `StableDiffusion` is linked; tests inject a mock conforming to this protocol.
public protocol CoreMLImageGenSessioning: Sendable {
    /// Runs txt2img (`sourceImage == nil`) or img2img. Throws on inference failure.
    func generate(
        from sourceImage: CGImage?,
        prompt: String,
        negativePrompt: String,
        config: ImageGenConfig,
        modelSize: ImageGenModelSize
    ) async throws -> ImageGenResult
}
