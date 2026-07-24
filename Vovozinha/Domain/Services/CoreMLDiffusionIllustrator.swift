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
final class CoreMLDiffusionIllustrator: Illustrating, @unchecked Sendable {
    private static let lock = NSLock()
    private static var sharedPipeline: Any?
    private static var pipelineLoadFailed = false

    var stepCount: Int = 24
    var refineStepCount: Int = 12
    var guidanceScale: Float = 8.5
    var refineStrength: Float = 0.24
    var enableRefinePass: Bool = true
    /// Base img2img strength for chain pages (higher = more change toward new page text).
    /// Paired with continuityStrength from the request for identity vs scene balance.
    var chainStrength: Float = 0.58
    /// Re-inject page-0 hero every N pages (0 = off).
    var heroReinjectionInterval: Int = 2
    var heroBlendAlpha: CGFloat = 0.30

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
        // Shared story seed; small page offset for pose variation.
        let seed = UInt32(truncatingIfNeeded: request.storySeed &+ UInt64(request.page.index) &* 31)

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
                config.strength = 0.68
                diffusionLog.info("page=0 photo establish strength=\(config.strength)")
            } else {
                diffusionLog.info("page=0 text2img establish section=\(request.brief.sectionTag, privacy: .public)")
            }
        } else if let prev = request.previousPageImage,
                  request.continuityStrength > 0.02 {
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
                // Continuity high → keep more identity from previous; still room for page text.
                // strength ≈ 0.48…0.65 depending on continuity.
                let c = min(max(request.continuityStrength, 0.25), 0.75)
                let strength = min(0.68, max(0.48, chainStrength + (0.55 - c) * 0.25))
                config.strength = strength
                diffusionLog.info(
                    "page=\(request.page.index) img2img strength=\(strength) continuity=\(c) section=\(request.brief.sectionTag, privacy: .public)"
                )
            }
        } else {
            diffusionLog.info("page=\(request.page.index) text2img")
        }

        let draft = try runGenerate(pipeline: pipeline, config: config, label: "draft")

        guard enableRefinePass,
              ImagePackStore.supportsImageToImage,
              let draftCG = cgImage(from: draft) else {
            return draft
        }

        // Refine: section + locked cast + page text (no redesign).
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
            return try runGenerate(pipeline: pipeline, config: refine, label: "refine")
        } catch {
            diffusionLog.error("refine failed, keeping draft: \(String(describing: error), privacy: .public)")
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
            images = try pipeline.generateImages(configuration: config) { progress in
                diffusionLog.debug("\(label) step \(progress.step)/\(progress.stepCount)")
                return true
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
        diffusionLog.info("Loading Core ML SD pipeline from \(url.path, privacy: .public)")

        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = .cpuAndNeuralEngine

        do {
            let pipeline = try StableDiffusionPipeline(
                resourcesAt: url,
                controlNet: [],
                configuration: mlConfig,
                disableSafety: true,
                reduceMemory: true
            )
            try pipeline.loadResources()
            sharedPipeline = pipeline
            return pipeline
        } catch {
            pipelineLoadFailed = true
            diffusionLog.error("pipeline load failed: \(String(describing: error), privacy: .public)")
            throw IllustrationError.packUnavailable
        }
    }
    #endif

    static func unloadPipeline() {
        #if canImport(StableDiffusion)
        lock.lock()
        if #available(iOS 16.2, *), let p = sharedPipeline as? StableDiffusionPipeline {
            p.unloadResources()
        }
        sharedPipeline = nil
        pipelineLoadFailed = false
        lock.unlock()
        #else
        lock.lock()
        sharedPipeline = nil
        pipelineLoadFailed = false
        lock.unlock()
        #endif
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
