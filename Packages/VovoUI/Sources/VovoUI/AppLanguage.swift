import Foundation

/// User preference: follow system or pin a language.
public enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case portugueseBrazil = "pt-BR"
    case englishUS = "en-US"
    case spanishSpain = "es-ES"

    public var id: String { rawValue }
}

/// Supported app + story languages (UI and generation).
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case portugueseBrazil = "pt-BR"
    case englishUS = "en-US"
    case spanishSpain = "es-ES"

    public var id: String { rawValue }

    public var bcp47: String { rawValue }

    /// Short label for the top toggle.
    public var shortLabel: String {
        switch self {
        case .portugueseBrazil: return "PT"
        case .englishUS: return "EN"
        case .spanishSpain: return "ES"
        }
    }

    /// Full label for settings / accessibility.
    public var displayName: String {
        switch self {
        case .portugueseBrazil: return "Português (Brasil)"
        case .englishUS: return "English (US)"
        case .spanishSpain: return "Español (España)"
        }
    }

    /// Stable XCUITest identifier (no hyphens).
    public var accessibilityIdentifier: String {
        switch self {
        case .portugueseBrazil: return "language.pt"
        case .englishUS: return "language.en"
        case .spanishSpain: return "language.es"
        }
    }

    /// Voice / TTS language code for AVSpeech.
    public var speechLanguage: String { rawValue }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// Resolve from OS preferred languages, falling back to English.
    public static func fromSystem() -> AppLanguage {
        for id in Locale.preferredLanguages {
            let lower = id.lowercased()
            if lower.hasPrefix("pt") { return .portugueseBrazil }
            if lower.hasPrefix("es") { return .spanishSpain }
            if lower.hasPrefix("en") { return .englishUS }
        }
        let code = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        if code == "pt" { return .portugueseBrazil }
        if code == "es" { return .spanishSpain }
        return .englishUS
    }

    public static func resolve(preferenceRaw: String?) -> AppLanguage {
        guard let raw = preferenceRaw, !raw.isEmpty, raw != LanguagePreference.system.rawValue else {
            return fromSystem()
        }
        return AppLanguage(rawValue: raw) ?? fromSystem()
    }
}
