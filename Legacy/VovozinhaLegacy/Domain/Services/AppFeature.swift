import Foundation

/// Catalog of app capabilities with declared platform requirements.
enum AppFeature: String, CaseIterable, Identifiable, Sendable {
    case swiftDataLibrary
    case photosPicker
    case ttsNarration
    case pdfExport
    case languageToggle
    case foundationModelsStory
    case foundationModelsVision
    case localLLMPack
    case localImageGen
    case graphicsPipeline

    var id: String { rawValue }

    /// Features shown in Settings “Resources on this iPhone”.
    static var userVisible: [AppFeature] {
        [
            .photosPicker,
            .ttsNarration,
            .pdfExport,
            .languageToggle,
            .foundationModelsStory,
            .foundationModelsVision,
            .localLLMPack,
            .localImageGen,
            .graphicsPipeline
        ]
    }

    var minimumOS: OperatingSystemVersion {
        switch self {
        case .languageToggle, .localLLMPack, .localImageGen, .graphicsPipeline:
            return OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)
        case .swiftDataLibrary:
            return OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0)
        case .photosPicker:
            return OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)
        case .ttsNarration:
            return OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)
        case .pdfExport:
            return OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0)
        case .foundationModelsStory, .foundationModelsVision:
            // On-device AFM / Foundation Models path (product analysis: iOS 26+).
            return OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        }
    }

    var requiresAppleIntelligenceCapableDevice: Bool {
        switch self {
        case .foundationModelsStory, .foundationModelsVision:
            return true
        default:
            return false
        }
    }

    /// Gated by `FeatureFlags.graphicsEnabled`.
    var requiresGraphicsBuildFlag: Bool {
        switch self {
        case .graphicsPipeline, .localImageGen:
            return true
        default:
            return false
        }
    }

    /// Needs an optional downloaded model pack (future).
    var requiresModelPack: Bool {
        switch self {
        case .localLLMPack, .localImageGen:
            return true
        default:
            return false
        }
    }

    func displayName(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.swiftDataLibrary, .portugueseBrazil): return "Biblioteca de histórias"
        case (.swiftDataLibrary, .englishUS): return "Story library"
        case (.swiftDataLibrary, .spanishSpain): return "Biblioteca de historias"

        case (.photosPicker, .portugueseBrazil): return "Foto do personagem"
        case (.photosPicker, .englishUS): return "Character photo"
        case (.photosPicker, .spanishSpain): return "Foto del personaje"

        case (.ttsNarration, .portugueseBrazil): return "Narração (voz do sistema)"
        case (.ttsNarration, .englishUS): return "Narration (system voice)"
        case (.ttsNarration, .spanishSpain): return "Narración (voz del sistema)"

        case (.pdfExport, .portugueseBrazil): return "Exportar PDF"
        case (.pdfExport, .englishUS): return "PDF export"
        case (.pdfExport, .spanishSpain): return "Exportar PDF"

        case (.languageToggle, .portugueseBrazil): return "Idioma do app e das histórias"
        case (.languageToggle, .englishUS): return "App & story language"
        case (.languageToggle, .spanishSpain): return "Idioma de la app y las historias"

        case (.foundationModelsStory, .portugueseBrazil): return "Foundation Models (texto)"
        case (.foundationModelsStory, .englishUS): return "Foundation Models (text)"
        case (.foundationModelsStory, .spanishSpain): return "Foundation Models (texto)"

        case (.foundationModelsVision, .portugueseBrazil): return "Foundation Models (visão / foto)"
        case (.foundationModelsVision, .englishUS): return "Foundation Models (vision / photo)"
        case (.foundationModelsVision, .spanishSpain): return "Foundation Models (visión / foto)"

        case (.localLLMPack, .portugueseBrazil): return "Pack LLM local (histórico)"
        case (.localLLMPack, .englishUS): return "Local LLM story pack"
        case (.localLLMPack, .spanishSpain): return "Pack LLM local (historias)"

        case (.localImageGen, .portugueseBrazil): return "Pack de ilustração local"
        case (.localImageGen, .englishUS): return "Local illustration pack"
        case (.localImageGen, .spanishSpain): return "Pack de ilustración local"

        case (.graphicsPipeline, .portugueseBrazil): return "Geração de ilustrações"
        case (.graphicsPipeline, .englishUS): return "Illustration generation"
        case (.graphicsPipeline, .spanishSpain): return "Generación de ilustraciones"
        }
    }
}

extension OperatingSystemVersion {
    var displayString: String {
        if patchVersion > 0 {
            return "\(majorVersion).\(minorVersion).\(patchVersion)"
        }
        if minorVersion > 0 {
            return "\(majorVersion).\(minorVersion)"
        }
        return "\(majorVersion)"
    }

    static func fromProcessInfo() -> OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }
}
