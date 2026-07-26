import Foundation
import UIKit
import CoreGraphics
import os

#if canImport(StableDiffusion)
import StableDiffusion
import CoreML
#endif

private let diffusionLog = Logger(subsystem: "app.vovozinha", category: "DiffusionArt")

/// On-device Core ML illustrator:
/// - **Section-custom prompts** (from `SceneArtBrief.sectionPrompt`)
/// - **Page story text** drives the new action/setting
/// - **Locked cast** (hero + recurring elements) via prompt + img2img chain + hero re-inject
///
/// Memory strategy (iPhone-critical):
/// - Always `reduceMemory: true` (models load one-at-a-time during generate)
/// - **No eager prewarm** — `loadResources()`/`prewarmResources()` loads the full Unet once and
///   often trips `mach_vm_allocate` right after Foundation Models story text
/// - Skip neural when free process memory is critically low
/// - On load/generate OOM: mark failed once and let `CompositeIllustrator` use procedural
final class CoreMLDiffusionIllustrator: Illustrating, @unchecked Sendable {
    private static let lock = NSLock()
    private static var sharedPipeline: Any?
    private static var pipelineLoadFailed = false

    /// Conservative defaults — quality still good with DPM-Solver; lower peaks vs 24+12.
    var stepCount: Int = 20
    var refineStepCount: Int = 8
    var guidanceScale: Float = 8.5
    var refineStrength: Float = 0.22
    /// Refine is a second full denoise pass; off by default to cut peak RAM ~2× on A16/A17.
    var enableRefinePass: Bool = false
    /// Img2img denoise for chain pages. Higher → **new scene** follows page text;
    /// lower freezes the previous frame (looks like “same image every page”).
    /// Identity of the actor is carried by the **prompt lock**, not by a sticky img2img.
    var chainStrength: Float = 0.78
    /// Re-inject page-0 hero occasionally (soft identity). Keep rare/low so scenes still change.
    var heroReinjectionInterval: Int = 4
    var heroBlendAlpha: CGFloat = 0.14

    /// Rough floor before attempting to load SD weights (bytes). Unet alone often needs ~1–2 GB.
    private static let minimumFreeBytesForNeural: UInt64 = 900 * 1024 * 1024

    func illustrate(_ request: IllustrationRequest) async throws -> UIImage {
        #if canImport(StableDiffusion)
        if #available(iOS 16.2, *) {
            let steps = self.stepCount
            let refineSteps = self.refineStepCount
            let guidance = self.guidanceScale
            let refineStrength = self.refineStrength
            let doRefine = self.enableRefinePass
            let chainStrength = self.chainStrength
            let reinjectEvery = self.heroReinjectionInterval
            let heroAlpha = self.heroBlendAlpha
            return try await Task.detached(priority: .userInitiated) {
                try autoreleasepool {
                    try Self.generateWithStableDiffusion(
                        request,
                        stepCount: steps,
                        refineStepCount: refineSteps,
                        guidanceScale: guidance,
                        refineStrength: refineStrength,
                        enableRefinePass: doRefine,
                        chainStrength: chainStrength,
                        heroReinjectionInterval: reinjectEvery,
                        heroBlendAlpha: heroAlpha
                    )
                }
            }.value
        }
        #endif
        diffusionLog.notice("StableDiffusion unavailable — install pack + SPM")
        throw IllustrationError.packUnavailable
    }

    #if canImport(StableDiffusion)
    @available(iOS 16.2, *)
    private static func generateWithStableDiffusion(
        _ request: IllustrationRequest,
        stepCount: Int,
        refineStepCount: Int,
        guidanceScale: Float,
        refineStrength: Float,
        enableRefinePass: Bool,
        chainStrength: Float,
        heroReinjectionInterval: Int,
        heroBlendAlpha: CGFloat
    ) throws -> UIImage {
        guard ImagePackStore.isNeuralPackReady else {
            throw IllustrationError.packUnavailable
        }

        let pipeline = try loadPipeline()
        // Strong per-page seed so noise layout differs even when prompts share a hero lock.
        let seed = UInt32(truncatingIfNeeded: request.pageSeed != 0
            ? request.pageSeed
            : request.storySeed &+ UInt64(request.page.index) &* 1_000_003)

        diffusionLog.info(
            "page=\(request.page.index) section=\(request.brief.sectionTag, privacy: .public)"
        )
        diffusionLog.info(
            "page=\(request.page.index) PAGE_TEXT=\(request.brief.sceneDescription, privacy: .public)"
        )
        diffusionLog.info(
            "page=\(request.page.index) LOCK=\(request.brief.continuityLock, privacy: .public)"
        )
        diffusionLog.info(
            "page=\(request.page.index) PROMPT=\(request.brief.positivePrompt, privacy: .public)"
        )

        var config = baseConfig(
            prompt: request.brief.positivePrompt,
            negative: request.brief.negativePrompt,
            stepCount: stepCount,
            guidanceScale: guidanceScale,
            seed: seed
        )

        if request.page.index == 0 || request.brief.isEstablishShot {
            if let photoData = request.referencePhoto,
               let ui = UIImage(data: photoData),
               let cg = cgImage(from: ui) {
                config.startingImage = cg
                // High strength so photo only hints identity; scene still from page text.
                config.strength = 0.78
                diffusionLog.info("page=0 photo establish strength=\(config.strength)")
            } else {
                diffusionLog.info("page=0 text2img establish section=\(request.brief.sectionTag, privacy: .public)")
            }
        } else if let prev = request.previousPageImage,
                  request.continuityStrength > 0.02,
                  ImagePackStore.supportsImageToImage {
            // Soft chain: previous page only for light identity/style bleed.
            // High denoise so each page’s *story text* drives a new composition.
            let startUI: UIImage
            let reinject = heroReinjectionInterval > 0
                && request.page.index % heroReinjectionInterval == 0
                && request.heroReferenceImage != nil
            if reinject, let hero = request.heroReferenceImage {
                startUI = blend(base: prev, overlay: hero, alpha: heroBlendAlpha) ?? prev
                diffusionLog.info("page=\(request.page.index) hero re-inject alpha=\(heroBlendAlpha)")
            } else {
                startUI = prev
            }
            if let cg = cgImage(from: startUI) {
                config.startingImage = cg
                // continuityStrength 0…1 = how sticky identity is; maps to denoise inverted.
                // Target strength ~0.70…0.88 so scenes change clearly page-to-page.
                let identity = min(max(request.continuityStrength, 0.15), 0.55)
                let strength = min(0.88, max(0.70, chainStrength - identity * 0.18))
                config.strength = strength
                diffusionLog.info(
                    "page=\(request.page.index) img2img strength=\(strength) identity=\(identity) section=\(request.brief.sectionTag, privacy: .public)"
                )
            }
        } else {
            // No VAEEncoder / no previous: pure text2img; hero lock in prompt keeps the actor.
            diffusionLog.info("page=\(request.page.index) text2img (no chain)")
        }

        let draft: UIImage
        do {
            draft = try runGenerate(pipeline: pipeline, config: config, label: "draft")
        } catch {
            // Generation OOM → drop pipeline so later pages don't thrash.
            markFailedAndUnload(reason: "draft generate: \(error)")
            throw IllustrationError.failed
        }

        guard enableRefinePass,
              ImagePackStore.supportsImageToImage,
              let draftCG = cgImage(from: draft) else {
            // Free Unet/encoder weights between pages when reduceMemory is on.
            pipeline.unloadResources()
            return draft
        }

        let refineText = """
        masterpiece, best quality, \(request.brief.sectionPrompt), \
        \(request.brief.continuityLock), \
        do not redesign locked character or elements, \
        illustrate this story page exactly: \(request.brief.sceneDescription), \
        the hero is \(request.brief.actionFocus), \(request.brief.lighting)
        """
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        var refine = baseConfig(
            prompt: refineText,
            negative: request.brief.negativePrompt,
            stepCount: refineStepCount,
            guidanceScale: min(guidanceScale + 0.4, 10),
            seed: seed &+ 11
        )
        refine.startingImage = draftCG
        refine.strength = min(max(refineStrength, 0.15), 0.30)
        diffusionLog.info("page=\(request.page.index) refine strength=\(refine.strength)")

        do {
            let refined = try runGenerate(pipeline: pipeline, config: refine, label: "refine")
            pipeline.unloadResources()
            return refined
        } catch {
            diffusionLog.error("refine failed, keeping draft: \(String(describing: error), privacy: .public)")
            pipeline.unloadResources()
            return draft
        }
    }

    @available(iOS 16.2, *)
    private static func baseConfig(
        prompt: String,
        negative: String,
        stepCount: Int,
        guidanceScale: Float,
        seed: UInt32
    ) -> StableDiffusionPipeline.Configuration {
        var config = StableDiffusionPipeline.Configuration(prompt: prompt)
        config.negativePrompt = negative
        config.stepCount = stepCount
        config.guidanceScale = guidanceScale
        config.seed = seed
        config.imageCount = 1
        config.disableSafety = true
        config.schedulerType = .dpmSolverMultistepScheduler
        return config
    }

    private static func blend(base: UIImage, overlay: UIImage, alpha: CGFloat) -> UIImage? {
        let size = base.size
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            let a = min(max(alpha, 0), 0.45)
            overlay.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: a)
        }
    }

    @available(iOS 16.2, *)
    private static func runGenerate(
        pipeline: StableDiffusionPipeline,
        config: StableDiffusionPipeline.Configuration,
        label: String
    ) throws -> UIImage {
        let images: [CGImage?]
        do {
            images = try autoreleasepool {
                try pipeline.generateImages(configuration: config) { progress in
                    diffusionLog.debug("\(label) step \(progress.step)/\(progress.stepCount)")
                    return true
                }
            }
        } catch {
            diffusionLog.error("generateImages(\(label)) failed: \(String(describing: error), privacy: .public)")
            throw IllustrationError.failed
        }
        guard let cg = images.compactMap({ $0 }).first else {
            throw IllustrationError.failed
        }
        return UIImage(cgImage: cg)
    }

    @available(iOS 16.2, *)
    private static func loadPipeline() throws -> StableDiffusionPipeline {
        lock.lock()
        defer { lock.unlock() }

        if pipelineLoadFailed {
            throw IllustrationError.packUnavailable
        }
        if let existing = sharedPipeline as? StableDiffusionPipeline {
            return existing
        }

        guard let url = ImagePackStore.activeResourcesURL else {
            throw IllustrationError.packUnavailable
        }

        let free = availableProcessMemoryBytes()
        diffusionLog.info(
            "Loading Core ML SD pipeline from \(url.path, privacy: .public) free≈\(free / (1024 * 1024))MB chunkedUnet=\(ImagePackStore.hasChunkedUnet(at: url))"
        )

        if free > 0, free < minimumFreeBytesForNeural {
            pipelineLoadFailed = true
            diffusionLog.error(
                "skip neural: only \(free / (1024 * 1024))MB free (need ≥\(minimumFreeBytesForNeural / (1024 * 1024))MB)"
            )
            throw IllustrationError.packUnavailable
        }

        // Prefer ANE; never force GPU (higher peak). allowLowPrecision helps footprint.
        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = .cpuAndNeuralEngine
        if #available(iOS 17.0, *) {
            mlConfig.allowLowPrecisionAccumulationOnGPU = true
        }

        do {
            // reduceMemory: true → generateImages loads/unloads TextEncoder → Unet → VAE one at a time.
            // Do NOT call loadResources()/prewarmResources() here: prewarm still materializes the full
            // Unet once and is a common source of mach_vm_allocate failures after LLM story gen.
            let pipeline = try StableDiffusionPipeline(
                resourcesAt: url,
                controlNet: [],
                configuration: mlConfig,
                disableSafety: true,
                reduceMemory: true
            )
            sharedPipeline = pipeline
            diffusionLog.info("pipeline constructed (lazy weights; first page loads models on demand)")
            return pipeline
        } catch {
            pipelineLoadFailed = true
            sharedPipeline = nil
            diffusionLog.error("pipeline load failed: \(String(describing: error), privacy: .public)")
            throw IllustrationError.packUnavailable
        }
    }

    @available(iOS 16.2, *)
    private static func markFailedAndUnload(reason: String) {
        lock.lock()
        if let p = sharedPipeline as? StableDiffusionPipeline {
            p.unloadResources()
        }
        sharedPipeline = nil
        pipelineLoadFailed = true
        lock.unlock()
        diffusionLog.error("neural disabled for rest of process: \(reason, privacy: .public)")
    }

    /// Bytes this process can still allocate (0 if unknown).
    private static func availableProcessMemoryBytes() -> UInt64 {
        UInt64(max(0, os_proc_available_memory()))
    }
    #endif

    static func unloadPipeline() {
        #if canImport(StableDiffusion)
        lock.lock()
        if #available(iOS 16.2, *), let p = sharedPipeline as? StableDiffusionPipeline {
            p.unloadResources()
        }
        sharedPipeline = nil
        // Keep pipelineLoadFailed so we don't thrash after OOM mid-story.
        // Caller can reset via resetLoadFailure() after user frees memory / restarts.
        lock.unlock()
        #else
        lock.lock()
        sharedPipeline = nil
        lock.unlock()
        #endif
    }

    /// Allow a later retry (e.g. Settings re-download, app relaunch path).
    static func resetLoadFailure() {
        lock.lock()
        pipelineLoadFailed = false
        lock.unlock()
    }

    private static func cgImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return rendered.cgImage
    }
}
