import Foundation
import CoreGraphics
import CoreML
import os

#if canImport(StableDiffusion)
import StableDiffusion

/// Owns the cached, lazily-loaded `StableDiffusionPipeline` **and** runs generation on it.
///
/// `StableDiffusionPipeline` is a non-`Sendable` value type, so it must not cross an actor
/// boundary. Keeping both the cache *and* the `generateImages` call inside this actor means
/// the pipeline never escapes isolation — satisfying Swift 6 concurrency cleanly (no
/// `NSLock` from async, no nonisolated global state).
///
/// Ports the proven on-device strategy from `Legacy/.../CoreMLDiffusionIllustrator`:
///   - `.cpuAndNeuralEngine` compute units (prefer ANE; never force GPU — higher peak).
///   - `reduceMemory: true` → load/unload TextEncoder → Unet → VAE one model at a time.
///   - Lazy weight load — never call `loadResources()`/`prewarmResources()` eagerly.
///   - An `os_proc_available_memory()` floor (~900 MB) gates the load to avoid jetsam.
actor PipelineCache {
    static let shared = PipelineCache()

    private var pipeline: StableDiffusionPipeline?
    private var loadedResourcesURL: URL?
    private var loadFailed = false

    /// Floor on free process memory before we even try to load the neural pipeline.
    private let minimumFreeBytes: UInt64 = 900 * 1024 * 1024  // 900 MB

    /// Loads (if needed) and returns the pipeline, isolated to this actor.
    private func pipeline(for url: URL) throws -> StableDiffusionPipeline {
        if loadFailed { throw ImageGenError.generationFailed }
        if let existing = pipeline, loadedResourcesURL == url { return existing }

        #if os(iOS)
        let free = UInt64(max(0, os_proc_available_memory()))
        if free > 0, free < minimumFreeBytes {
            os_log(.error, "skip neural: only %{public}llu MB free (need ≥%{public}llu MB)",
                   free / (1024 * 1024), minimumFreeBytes / (1024 * 1024))
            // Do not sticky-fail: Metal reclaim lags `clearCache()`. Caller retries.
            throw ImageGenError.generationFailed
        }
        #endif

        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = .cpuAndNeuralEngine
        if #available(iOS 17.0, macOS 14.0, *) {
            mlConfig.allowLowPrecisionAccumulationOnGPU = true
        }

        do {
            // reduceMemory: true → lazy load; do NOT call loadResources()/prewarmResources()
            // eagerly. Eager prewarm materializes the full Unet once and is a common source
            // of mach_vm_allocate failures after other heavy work.
            let p = try StableDiffusionPipeline(
                resourcesAt: url,
                controlNet: [],
                configuration: mlConfig,
                disableSafety: true,
                reduceMemory: true
            )
            pipeline = p
            loadedResourcesURL = url
            loadFailed = false
            return p
        } catch {
            os_log(.error, "pipeline load failed: %{public}s", String(describing: error))
            pipeline = nil
            loadedResourcesURL = nil
            loadFailed = true
            throw ImageGenError.generationFailed
        }
    }

    /// Runs txt2img or img2img on the cached pipeline for `url`. Isolated here.
    func generate(
        at url: URL,
        startingImage: CGImage?,
        prompt: String,
        negativePrompt: String,
        config: ImageGenConfig
    ) throws -> (cgImage: CGImage, seed: UInt32, elapsed: Double) {
        let pipeline = try pipeline(for: url)
        let seed = config.seed ?? UInt32.random(in: 0...UInt32.max)

        var pc = StableDiffusionPipeline.Configuration(prompt: prompt)
        pc.negativePrompt = negativePrompt
        if let startingImage {
            pc.startingImage = startingImage
            pc.strength = min(max(config.strength, 0.01), 0.99)  // must be < 1.0 for img2img
        }
        pc.stepCount = config.stepCount
        pc.guidanceScale = config.guidanceScale
        pc.seed = seed
        pc.imageCount = 1
        pc.disableSafety = true
        switch config.scheduler {
        case .dpmSolverMultistep: pc.schedulerType = .dpmSolverMultistepScheduler
        case .pndm:               pc.schedulerType = .pndmScheduler
        }

        let started = Date()
        let images: [CGImage?] = try autoreleasepool {
            try pipeline.generateImages(configuration: pc) { progress in
                os_log(.debug, "img2img step %{public}d/%{public}d",
                       progress.step, progress.stepCount)
                return true
            }
        }
        guard let cg = images.compactMap({ $0 }).first else {
            throw ImageGenError.generationFailed
        }
        return (cg, seed, Date().timeIntervalSince(started))
    }

    /// Resets the cache (e.g. after the pack is removed or swapped).
    func reset() {
        pipeline?.unloadResources()
        pipeline = nil
        loadedResourcesURL = nil
        loadFailed = false
    }
}
#endif
