import Foundation

/// Feature boundary: prompt (+ optional photo) → on-device anime image.
///
/// `.imageToImage` resizes the photo, VAE-encodes it, and uses it as the diffusion
/// starting image. `.textToImage` samples from noise. Generation is fully offline.
public protocol ImageGenerating: Sendable {
    func generate(_ input: ImageGenInput, config: ImageGenConfig) async throws -> ImageGenResult
}

/// Failures from on-device image generation.
public enum ImageGenError: Error, Equatable, Sendable {
    /// The source photo could not be decoded or was empty.
    case invalidImage
    /// The on-device Core ML image pack is not installed yet.
    case packNotInstalled
    /// The installed pack has no `VAEEncoder.mlmodelc`, which is required for img2img.
    case vaeEncoderMissing
    /// Inference ran but produced no usable image.
    case generationFailed
}
