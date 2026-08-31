import Foundation
import Observation

/// App-wide language for UI strings and story generation. Default follows the system.
/// Inject with `.environment(languageStore)` and read via `@Environment(LanguageStore.self)`.
@MainActor
@Observable
public final class LanguageStore {
    public static let preferenceKey = "vovozinha.languagePreference"

    /// Stored preference: `"system"` or a BCP-47 code (`pt-BR`, `en-US`, `es-ES`).
    public var preferenceRaw: String {
        didSet {
            UserDefaults.standard.set(preferenceRaw, forKey: Self.preferenceKey)
        }
    }

    public init() {
        let saved = UserDefaults.standard.string(forKey: Self.preferenceKey)
        self.preferenceRaw = saved ?? LanguagePreference.system.rawValue
    }

    /// Test / preview helper that does not touch UserDefaults persistence until mutated.
    public init(preferenceRaw: String) {
        self.preferenceRaw = preferenceRaw
    }

    public var isFollowingSystem: Bool {
        preferenceRaw == LanguagePreference.system.rawValue || preferenceRaw.isEmpty
    }

    /// Effective language for UI + stories.
    public var language: AppLanguage {
        AppLanguage.resolve(preferenceRaw: preferenceRaw)
    }

    public func setSystem() {
        preferenceRaw = LanguagePreference.system.rawValue
    }

    public func setLanguage(_ language: AppLanguage) {
        preferenceRaw = language.rawValue
    }

    /// Select language from the toggle; pins the language.
    public func select(_ language: AppLanguage) {
        setLanguage(language)
    }
}
