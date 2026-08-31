import Foundation

/// Tunable generation parameters for img2img. Defaults follow the project's parent-facing
/// guidance: strength 0.5–0.7, steps 25–28, CFG 5–7. The sampler is fixed to
/// `.dpmSolverMultistep` (see `ImageGenScheduler` for why Euler a isn't available).
public struct ImageGenConfig: Sendable {
    /// Denoising strength: 0 = identity to source, 1 = ignore source. Higher → more
    /// creative / anime conversion. Default 0.6 (within the 0.5–0.7 band).
    public var strength: Float = 0.6
    /// Inference steps. 25–28 recommended for SD1.5 anime.
    public var stepCount: Int = 25
    /// Text guidance (CFG). 5–7 recommended.
    public var guidanceScale: Float = 6.0
    /// Sampler. Default `.dpmSolverMultistep`.
    public var scheduler: ImageGenScheduler = .dpmSolverMultistep
    /// Reproducibility seed. `nil` = random per run.
    public var seed: UInt32?
    /// Target resolution bucket. Default `.square` (512×512 on SD1.5).
    public var bucket: ImageGenBucket = .square
    /// Sampling mode. Default `.imageToImage`.
    public var mode: ImageGenMode = .imageToImage
    /// Free-text positive prompt appended after the locale scaffold.
    public var prompt: String = ""
    /// Negative prompt. Defaults to the locked kids/anti-photoreal scaffold.
    public var negativePrompt: String = ""

    public init(
        strength: Float = 0.6,
        stepCount: Int = 25,
        guidanceScale: Float = 6.0,
        scheduler: ImageGenScheduler = .dpmSolverMultistep,
        seed: UInt32? = nil,
        bucket: ImageGenBucket = .square,
        mode: ImageGenMode = .imageToImage,
        prompt: String = "",
        negativePrompt: String = ""
    ) {
        self.strength = strength
        self.stepCount = stepCount
        self.guidanceScale = guidanceScale
        self.scheduler = scheduler
        self.seed = seed
        self.bucket = bucket
        self.mode = mode
        self.prompt = prompt
        self.negativePrompt = negativePrompt
    }
}

/// Diffusion pipeline mode.
public enum ImageGenMode: String, Sendable, CaseIterable {
    case textToImage
    case imageToImage
}
