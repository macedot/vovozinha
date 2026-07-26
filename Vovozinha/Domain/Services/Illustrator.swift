import Foundation
import UIKit

/// Request for one page illustration with **temporal coherence** inputs.
struct IllustrationRequest: @unchecked Sendable {
    let page: StoryPlanPage
    let plan: StoryPlan
    let referencePhoto: Data?
    /// Previous page image for img2img scene continuity (nil on first page).
    let previousPageImage: UIImage?
    /// Page 0 (hero establish) image — re-injected periodically to fight identity drift.
    let heroReferenceImage: UIImage?
    /// Shared seed for the whole story (style lock).
    let storySeed: UInt64
    /// Per-page seed (usually storySeed &+ page index).
    let pageSeed: UInt64
    /// 0…1 — higher keeps more of the previous frame (neural img2img / procedural blend).
    let continuityStrength: Float
    /// Structured brief (English) for scene matching + hero lock.
    let brief: SceneArtBrief
}

protocol Illustrating: Sendable {
    func illustrate(_ request: IllustrationRequest) async throws -> UIImage
}

enum IllustrationError: LocalizedError {
    case failed
    case packUnavailable

    var errorDescription: String? {
        switch self {
        case .failed: return "Could not create the page illustration."
        case .packUnavailable: return "On-device image model pack is not installed."
        }
    }

    func localizedDescription(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.failed, .portugueseBrazil):
            return "Não foi possível criar a ilustração da página."
        case (.failed, .englishUS):
            return errorDescription ?? "Failed"
        case (.failed, .spanishSpain):
            return "No se pudo crear la ilustración de la página."
        case (.packUnavailable, .portugueseBrazil):
            return "Pack de modelo de imagem no aparelho não está instalado."
        case (.packUnavailable, .englishUS):
            return errorDescription ?? "Pack unavailable"
        case (.packUnavailable, .spanishSpain):
            return "El pack de modelo de imagen en el dispositivo no está instalado."
        }
    }
}

/// Picks neural pack illustrator when installed; otherwise procedural.
enum IllustratorFactory {
    static func make(profile: DeviceProfile = .current) -> any Illustrating {
        if ImagePackStore.isNeuralPackReady {
            return CompositeIllustrator(
                primary: CoreMLDiffusionIllustrator(),
                fallback: ProceduralKidsIllustrator()
            )
        }
        return ProceduralKidsIllustrator()
    }
}

/// Tries neural first; on failure uses procedural (always offline).
struct CompositeIllustrator: Illustrating {
    let primary: any Illustrating
    let fallback: any Illustrating

    func illustrate(_ request: IllustrationRequest) async throws -> UIImage {
        do {
            return try await primary.illustrate(request)
        } catch {
            // Expected when pack OOM (`mach_vm_allocate`) or load fails — keep story going.
            return try await fallback.illustrate(request)
        }
    }
}
