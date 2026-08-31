import Foundation

/// Diffusion sampler. Wraps `StableDiffusionScheduler` from `ml-stable-diffusion`.
///
/// - Note: `ml-stable-diffusion` 1.1.1 exposes only `.pndmScheduler` and
///   `.dpmSolverMultistepScheduler` — it does **not** ship an Euler ancestral sampler
///   (unlike AUTOMATIC1111/ComfyUI). The default is `.dpmSolverMultistepScheduler`,
///   which is the proven choice for on-device Core ML in this project (see
///   `Legacy/.../CoreMLDiffusionIllustrator`).
public enum ImageGenScheduler: String, Sendable, CaseIterable {
    case dpmSolverMultistep
    case pndm
}
