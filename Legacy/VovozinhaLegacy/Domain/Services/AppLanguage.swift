import Foundation

/// User preference: follow system or pin a language.
enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case portugueseBrazil = "pt-BR"
    case englishUS = "en-US"
    case spanishSpain = "es-ES"

    var id: String { rawValue }

    /// Languages offered in the toggle (system is separate default resolution).
    static var selectableLanguages: [AppLanguage] {
        AppLanguage.allCases
    }
}

/// Supported app + story languages.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case portugueseBrazil = "pt-BR"
    case englishUS = "en-US"
    case spanishSpain = "es-ES"

    var id: String { rawValue }

    var bcp47: String { rawValue }

    /// Short label for the top toggle.
    var shortLabel: String {
        switch self {
        case .portugueseBrazil: return "PT"
        case .englishUS: return "EN"
        case .spanishSpain: return "ES"
        }
    }

    /// Full label for settings / accessibility.
    var displayName: String {
        switch self {
        case .portugueseBrazil: return "Português (Brasil)"
        case .englishUS: return "English (US)"
        case .spanishSpain: return "Español (España)"
        }
    }

    /// Voice / TTS language code for AVSpeech.
    var speechLanguage: String { rawValue }

    /// Locale used for formatting.
    var locale: Locale { Locale(identifier: rawValue) }

    /// Resolve from OS preferred languages, falling back to English.
    static func fromSystem() -> AppLanguage {
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

    static func resolve(preferenceRaw: String?) -> AppLanguage {
        guard let raw = preferenceRaw, !raw.isEmpty, raw != LanguagePreference.system.rawValue else {
            return fromSystem()
        }
        return AppLanguage(rawValue: raw) ?? fromSystem()
    }
}
