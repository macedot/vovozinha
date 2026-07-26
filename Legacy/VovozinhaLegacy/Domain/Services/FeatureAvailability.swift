import Foundation

/// Result of checking whether a feature can run on this device/build.
enum FeatureAvailability: Equatable, Sendable {
    case available
    case unavailableOS(required: String, current: String)
    case unavailableHardware(String)
    case unavailableConfig(String)
    case disabledInBuild(String)

    var isUsable: Bool {
        if case .available = self { return true }
        return false
    }

    var statusSymbolName: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .unavailableOS, .unavailableHardware, .unavailableConfig: return "exclamationmark.triangle.fill"
        case .disabledInBuild: return "minus.circle.fill"
        }
    }

    /// Short status label for lists.
    func statusLabel(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.available, .portugueseBrazil): return "Disponível"
        case (.available, .englishUS): return "Available"
        case (.available, .spanishSpain): return "Disponible"
        case (.unavailableOS, .portugueseBrazil): return "iOS insuficiente"
        case (.unavailableOS, .englishUS): return "iOS too old"
        case (.unavailableOS, .spanishSpain): return "iOS insuficiente"
        case (.unavailableHardware, .portugueseBrazil): return "Hardware"
        case (.unavailableHardware, .englishUS): return "Hardware"
        case (.unavailableHardware, .spanishSpain): return "Hardware"
        case (.unavailableConfig, .portugueseBrazil): return "Não configurado"
        case (.unavailableConfig, .englishUS): return "Not set up"
        case (.unavailableConfig, .spanishSpain): return "No configurado"
        case (.disabledInBuild, .portugueseBrazil): return "Desligado nesta versão"
        case (.disabledInBuild, .englishUS): return "Off in this build"
        case (.disabledInBuild, .spanishSpain): return "Desactivado en esta versión"
        }
    }

    /// Full user-facing explanation.
    func userMessage(_ lang: AppLanguage) -> String {
        switch self {
        case .available:
            switch lang {
            case .portugueseBrazil: return "Este recurso está disponível neste iPhone."
            case .englishUS: return "This feature is available on this iPhone."
            case .spanishSpain: return "Esta función está disponible en este iPhone."
            }
        case .unavailableOS(let required, let current):
            switch lang {
            case .portugueseBrazil:
                return "Requer iOS \(required) ou superior. Este aparelho está em iOS \(current)."
            case .englishUS:
                return "Requires iOS \(required) or later. This device is on iOS \(current)."
            case .spanishSpain:
                return "Requiere iOS \(required) o superior. Este dispositivo está en iOS \(current)."
            }
        case .unavailableHardware(let detail):
            switch lang {
            case .portugueseBrazil: return "Indisponível neste hardware. \(detail)"
            case .englishUS: return "Unavailable on this hardware. \(detail)"
            case .spanishSpain: return "No disponible en este hardware. \(detail)"
            }
        case .unavailableConfig(let detail):
            switch lang {
            case .portugueseBrazil: return detail
            case .englishUS: return detail
            case .spanishSpain: return detail
            }
        case .disabledInBuild(let detail):
            return detail
        }
    }
}
