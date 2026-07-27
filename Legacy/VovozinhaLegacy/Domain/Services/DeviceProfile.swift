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
    }

    let os: OperatingSystemVersion
    let chipClass: ChipClass
    /// Heuristic: A17 Pro+ class devices for Apple Intelligence features.
    let appleIntelligenceLikely: Bool
    /// Optional packs; injected for tests.
    let localLLMPackInstalled: Bool
    let localImagePackInstalled: Bool
    let graphicsBuildEnabled: Bool

    var osDisplay: String { os.displayString }

    /// iOS app running on Mac (Xcode: **My Mac (Designed for iPad)**).
    static var isIOSAppOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    /// Offline draft-parameterized stories allowed (no Foundation Models required).
    /// - iOS app on Mac (Designed for iPad)
    /// - Any **DEBUG** build (physical device while developing)
    /// - **Release** on a real iPhone: `false` → product FM/pack rules
    static var allowsDevStoryFallback: Bool {
        if isIOSAppOnMac { return true }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var current: DeviceProfile {
        let dev = allowsDevStoryFallback
        return make(
            os: .fromProcessInfo(),
            chipClass: detectChipClass(),
            // Dev environments: unlock pack-dependent UI flags for iteration.
            localLLMPackInstalled: dev,
            localImagePackInstalled: dev ? true : ImagePackStore.isNeuralPackReady,
            graphicsBuildEnabled: FeatureFlags.graphicsEnabled
        )
    }

    static func make(
        os: OperatingSystemVersion,
        chipClass: ChipClass,
        localLLMPackInstalled: Bool = false,
        localImagePackInstalled: Bool = false,
        graphicsBuildEnabled: Bool = FeatureFlags.graphicsEnabled
    ) -> DeviceProfile {
        let packsLLM = localLLMPackInstalled
        let packsImage = localImagePackInstalled
        let aiLikely = Self.computeAppleIntelligenceLikely(
            unlockForDev: Self.allowsDevStoryFallback,
            chipClass: chipClass
        )
        return DeviceProfile(
            os: os,
            chipClass: chipClass,
            appleIntelligenceLikely: aiLikely,
            localLLMPackInstalled: packsLLM,
            localImagePackInstalled: packsImage,
            graphicsBuildEnabled: graphicsBuildEnabled
        )
    }

    static var isAppleSiliconHost: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private static func computeAppleIntelligenceLikely(
        unlockForDev: Bool,
        chipClass: ChipClass
    ) -> Bool {
        if unlockForDev { return true }
        switch chipClass {
        case .a17OrNewer: return true
        case .a16, .unknown: return false
        }
    }

    func isEnabled(_ feature: AppFeature) -> Bool {
        availability(for: feature, lang: .englishUS).isUsable
    }

    func availability(for feature: AppFeature, lang: AppLanguage = .englishUS) -> FeatureAvailability {
        if Self.allowsDevStoryFallback {
            if feature.requiresGraphicsBuildFlag, !graphicsBuildEnabled {
                return .disabledInBuild(L10n.t(.featureBannerGraphicsOff, lang))
            }
            return .available
        }

        if feature.requiresGraphicsBuildFlag, !graphicsBuildEnabled {
            return .disabledInBuild(L10n.t(.featureBannerGraphicsOff, lang))
        }

        if !isOSAtLeast(feature.minimumOS) {
            return .unavailableOS(
                required: feature.minimumOS.displayString,
                current: osDisplay
            )
        }

        if feature.requiresAppleIntelligenceCapableDevice, !appleIntelligenceLikely {
            return .unavailableHardware(hardwareMessage(lang))
        }

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
        if Self.allowsDevStoryFallback { return .foundationModels }
        return .none
    }

    /// Stories require a real on-device LLM (FM or pack) on Release devices.
    /// DEBUG / iOS-on-Mac always allows generation via offline dev planner.
    var canGenerateStories: Bool {
        if Self.allowsDevStoryFallback { return true }
        return preferredStoryPlannerKind != .none
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
        if canRunGraphics {
            lines.append(ImagePackStore.statusSummary(lang: lang))
        } else {
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
            return "Baixe o pacote de imagens em Ajustes (Wi‑Fi, ~1,5 GB). Depois as cenas rodam offline."
        case .englishUS:
            return "Download the picture pack in Settings (Wi‑Fi, ~1.5 GB). Then scenes run offline."
        case .spanishSpain:
            return "Descarga el paquete de imágenes en Ajustes (Wi‑Fi, ~1,5 GB). Luego las escenas corren offline."
        }
    }

    private func foundationModelsMissingMessage(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil:
            return "Apple Foundation Models não estão disponíveis neste build do sistema (ou a Apple Intelligence ainda não baixou os modelos)."
        case .englishUS:
            return "Apple Foundation Models are not available in this system build (or Apple Intelligence has not finished downloading models)."
        case .spanishSpain:
            return "Apple Foundation Models no están disponibles en este build del sistema (o Apple Intelligence aún no ha descargado los modelos)."
        }
    }

    private func deviceLine(_ lang: AppLanguage) -> String {
        let chip: String = {
            switch chipClass {
            case .a16: return "A16"
            case .a17OrNewer: return "A17+"
            case .unknown: return "?"
            }
        }()
        switch lang {
        case .portugueseBrazil:
            return "iOS \(osDisplay) · chip \(chip)"
        case .englishUS:
            return "iOS \(osDisplay) · chip \(chip)"
        case .spanishSpain:
            return "iOS \(osDisplay) · chip \(chip)"
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
            return Self.systemLanguageModelAvailable()
        }
        return false
        #else
        return false
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func systemLanguageModelAvailable() -> Bool {
        let general = SystemLanguageModel(useCase: .general)
        if general.isAvailable { return true }
        return SystemLanguageModel.default.isAvailable
    }
    #endif

    private static func detectChipClass() -> ChipClass {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return chipClass(forMachineIdentifier: machine)
    }

    private static func chipClass(forMachineIdentifier machine: String) -> ChipClass {
        if machine.hasPrefix("iPhone15,4") || machine.hasPrefix("iPhone15,5") {
            return .a16
        }
        if machine.hasPrefix("iPhone14,") || machine.hasPrefix("iPhone13,")
            || machine.hasPrefix("iPhone12,") || machine.hasPrefix("iPhone11,") {
            return .unknown
        }
        if machine.hasPrefix("iPhone") {
            return .a17OrNewer
        }
        if machine.hasPrefix("arm64") || machine.isEmpty {
            return isAppleSiliconHost ? .a17OrNewer : .unknown
        }
        return .unknown
    }
}

enum StoryPlannerKind: String, Sendable {
    case foundationModels
    case localLLMPack
    case none
}
