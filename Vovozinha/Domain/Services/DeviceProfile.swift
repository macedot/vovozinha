import Foundation
import AVFoundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Runtime device/OS profile used to enable features and explain gaps to the user.
struct DeviceProfile: Sendable {
    enum ChipClass: String, Sendable {
        case a16
        case a17OrNewer
        case unknown
        case simulator
    }

    let os: OperatingSystemVersion
    let chipClass: ChipClass
    let isSimulator: Bool
    /// Heuristic: A17 Pro+ class devices that typically support Apple Intelligence stacks.
    let appleIntelligenceLikely: Bool
    /// Optional packs (future); injected for tests.
    let localLLMPackInstalled: Bool
    let localImagePackInstalled: Bool
    let graphicsBuildEnabled: Bool

    var osDisplay: String { os.displayString }

    static var current: DeviceProfile {
        make(
            os: .fromProcessInfo(),
            chipClass: detectChipClass(),
            isSimulator: {
                #if targetEnvironment(simulator)
                true
                #else
                false
                #endif
            }(),
            localLLMPackInstalled: false,
            localImagePackInstalled: AppSettings.illustrationPackInstalled,
            graphicsBuildEnabled: FeatureFlags.graphicsEnabled
        )
    }

    static func make(
        os: OperatingSystemVersion,
        chipClass: ChipClass,
        isSimulator: Bool,
        localLLMPackInstalled: Bool = false,
        localImagePackInstalled: Bool = false,
        graphicsBuildEnabled: Bool = FeatureFlags.graphicsEnabled
    ) -> DeviceProfile {
        let aiLikely: Bool = {
            if isSimulator { return false }
            switch chipClass {
            case .a17OrNewer: return true
            case .a16, .unknown, .simulator: return false
            }
        }()
        return DeviceProfile(
            os: os,
            chipClass: chipClass,
            isSimulator: isSimulator,
            appleIntelligenceLikely: aiLikely,
            localLLMPackInstalled: localLLMPackInstalled,
            localImagePackInstalled: localImagePackInstalled,
            graphicsBuildEnabled: graphicsBuildEnabled
        )
    }

    func isEnabled(_ feature: AppFeature) -> Bool {
        availability(for: feature, lang: .englishUS).isUsable
    }

    func availability(for feature: AppFeature, lang: AppLanguage = .englishUS) -> FeatureAvailability {
        // 1) Build flags
        if feature.requiresGraphicsBuildFlag, !graphicsBuildEnabled {
            return .disabledInBuild(L10n.t(.featureBannerGraphicsOff, lang))
        }

        // 2) OS version
        if !isOSAtLeast(feature.minimumOS) {
            return .unavailableOS(
                required: feature.minimumOS.displayString,
                current: osDisplay
            )
        }

        // 3) Hardware
        if feature.requiresAppleIntelligenceCapableDevice, !appleIntelligenceLikely {
            return .unavailableHardware(hardwareMessage(lang))
        }

        // 4) Config / packs
        if feature == .localLLMPack, !localLLMPackInstalled {
            return .unavailableConfig(packMessageLLM(lang))
        }
        if feature == .localImageGen {
            if !graphicsBuildEnabled {
                return .disabledInBuild(L10n.t(.featureBannerGraphicsOff, lang))
            }
            if !localImagePackInstalled {
                return .unavailableConfig(packMessageImage(lang))
            }
        }

        // 5) Foundation Models framework presence
        if feature == .foundationModelsStory || feature == .foundationModelsVision {
            if !foundationModelsFrameworkPresent {
                return .unavailableConfig(foundationModelsMissingMessage(lang))
            }
        }

        return .available
    }

    /// Prefer on-device Foundation Models, then optional local LLM pack. No template planner.
    var preferredStoryPlannerKind: StoryPlannerKind {
        if isEnabled(.foundationModelsStory) { return .foundationModels }
        if isEnabled(.localLLMPack) { return .localLLMPack }
        return .none
    }

    /// Stories require a real on-device LLM (FM or pack). Template/pre-computed stories are disabled.
    var canGenerateStories: Bool {
        preferredStoryPlannerKind != .none
    }

    var canUsePhotos: Bool { isEnabled(.photosPicker) }
    var canNarrate: Bool { isEnabled(.ttsNarration) }
    var canExportPDF: Bool { isEnabled(.pdfExport) }
    var canRunGraphics: Bool { isEnabled(.graphicsPipeline) }

    /// Multi-line status for generation UI / settings summary.
    func statusSummary(lang: AppLanguage) -> String {
        var lines: [String] = []
        lines.append(deviceLine(lang))
        lines.append(plannerLine(lang))
        if !canRunGraphics {
            let g = availability(for: .graphicsPipeline, lang: lang)
            lines.append(g.userMessage(lang))
        }
        let fm = availability(for: .foundationModelsStory, lang: lang)
        if !fm.isUsable {
            lines.append("\(AppFeature.foundationModelsStory.displayName(lang)): \(fm.statusLabel(lang)). \(fm.userMessage(lang))")
        }
        return lines.joined(separator: "\n")
    }

    private func hardwareMessage(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil:
            return "Requer hardware com Apple Intelligence (em geral iPhone 15 Pro ou mais novo)."
        case .englishUS:
            return "Requires Apple Intelligence–capable hardware (typically iPhone 15 Pro or later)."
        case .spanishSpain:
            return "Requiere hardware con Apple Intelligence (normalmente iPhone 15 Pro o posterior)."
        }
    }

    private func packMessageLLM(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil:
            return "Baixe o pack opcional de modelo de histórias no aparelho em Ajustes, quando disponível."
        case .englishUS:
            return "Download the optional on-device story model pack in Settings when available."
        case .spanishSpain:
            return "Descarga el pack opcional de modelo de historias en Ajustes cuando esté disponible."
        }
    }

    private func packMessageImage(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil:
            return "Baixe o pack opcional de ilustração no aparelho quando disponível."
        case .englishUS:
            return "Download the optional on-device illustration pack when available."
        case .spanishSpain:
            return "Descarga el pack opcional de ilustración cuando esté disponible."
        }
    }

    private func foundationModelsMissingMessage(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil:
            return "Apple Foundation Models não estão disponíveis neste build do sistema."
        case .englishUS:
            return "Apple Foundation Models are not available in this system build."
        case .spanishSpain:
            return "Apple Foundation Models no están disponibles en este build del sistema."
        }
    }

    private func deviceLine(_ lang: AppLanguage) -> String {
        let chip: String = {
            switch chipClass {
            case .a16: return "A16"
            case .a17OrNewer: return "A17+"
            case .simulator: return "Simulator"
            case .unknown: return "?"
            }
        }()
        switch lang {
        case .portugueseBrazil:
            return "iOS \(osDisplay) · chip \(chip)" + (isSimulator ? " · simulador" : "")
        case .englishUS:
            return "iOS \(osDisplay) · chip \(chip)" + (isSimulator ? " · simulator" : "")
        case .spanishSpain:
            return "iOS \(osDisplay) · chip \(chip)" + (isSimulator ? " · simulador" : "")
        }
    }

    private func plannerLine(_ lang: AppLanguage) -> String {
        switch preferredStoryPlannerKind {
        case .foundationModels:
            switch lang {
            case .portugueseBrazil: return "Motor de história: Foundation Models (no aparelho)."
            case .englishUS: return "Story engine: Foundation Models (on-device)."
            case .spanishSpain: return "Motor de historia: Foundation Models (en el dispositivo)."
            }
        case .localLLMPack:
            switch lang {
            case .portugueseBrazil: return "Motor de história: pack LLM local."
            case .englishUS: return "Story engine: local LLM pack."
            case .spanishSpain: return "Motor de historia: pack LLM local."
            }
        case .none:
            switch lang {
            case .portugueseBrazil:
                return "Nenhum LLM no aparelho disponível. É preciso iOS 26+ com Apple Intelligence (Foundation Models) ou pack de modelo local. Não geramos textos pré-prontos."
            case .englishUS:
                return "No on-device LLM available. Need iOS 26+ with Apple Intelligence (Foundation Models) or a local model pack. Pre-written stories are not used."
            case .spanishSpain:
                return "No hay LLM en el dispositivo. Se necesita iOS 26+ con Apple Intelligence (Foundation Models) o un pack de modelo local. No usamos textos preescritos."
            }
        }
    }

    private func isOSAtLeast(_ minimum: OperatingSystemVersion) -> Bool {
        // Compare component-wise so tests can inject fake OS versions without ProcessInfo.
        if os.majorVersion != minimum.majorVersion {
            return os.majorVersion > minimum.majorVersion
        }
        if os.minorVersion != minimum.minorVersion {
            return os.minorVersion > minimum.minorVersion
        }
        return os.patchVersion >= minimum.patchVersion
    }

    private var foundationModelsFrameworkPresent: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Runtime: model assets + Apple Intelligence must be ready.
            return SystemLanguageModel.default.isAvailable
        }
        return false
        #else
        return false
        #endif
    }

    private static func detectChipClass() -> ChipClass {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        // iPhone15,4 / 15,5 = iPhone 15 / 15 Plus (A16)
        if machine.hasPrefix("iPhone15,4") || machine.hasPrefix("iPhone15,5") {
            return .a16
        }
        if machine.hasPrefix("iPhone") {
            return .a17OrNewer
        }
        return .unknown
        #endif
    }
}

enum StoryPlannerKind: String, Sendable {
    case foundationModels
    case localLLMPack
    case none
}
