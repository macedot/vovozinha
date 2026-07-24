import Foundation
import Observation
import SwiftUI

/// App-wide language for UI strings and story generation. Default follows the system.
/// Injected with `.environment(languageStore)` and read via `@Environment(LanguageStore.self)`.
@MainActor
@Observable
final class LanguageStore {
    static let preferenceKey = "vovozinha.languagePreference"

    /// Stored preference: `"system"` or a BCP-47 code (`pt-BR`, `en-US`, `es-ES`).
    var preferenceRaw: String {
        didSet {
            UserDefaults.standard.set(preferenceRaw, forKey: Self.preferenceKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.preferenceKey)
        self.preferenceRaw = saved ?? LanguagePreference.system.rawValue
    }

    var isFollowingSystem: Bool {
        preferenceRaw == LanguagePreference.system.rawValue || preferenceRaw.isEmpty
    }

    /// Effective language for UI + stories.
    var language: AppLanguage {
        AppLanguage.resolve(preferenceRaw: preferenceRaw)
    }

    func setSystem() {
        preferenceRaw = LanguagePreference.system.rawValue
    }

    func setLanguage(_ language: AppLanguage) {
        preferenceRaw = language.rawValue
    }

    /// Select language from toggle; tapping current non-system keeps it pinned.
    func select(_ language: AppLanguage) {
        setLanguage(language)
    }
}
