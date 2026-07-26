import Foundation

enum AppSettings {
    static let ageGateAcceptedKey = "vovozinha.ageGateAccepted"
    static let preferredTTSRateKey = "vovozinha.ttsRate"
    static let illustrationPackInstalledKey = "vovozinha.illustrationPackInstalled"
    /// `"system"` or BCP-47 (`pt-BR` / `en-US` / `es-ES`). See `LanguageStore`.
    static let languagePreferenceKey = "vovozinha.languagePreference"
    /// Optional `AVSpeechSynthesisVoice.identifier`. Empty = auto (best Premium/Enhanced offline).
    static let preferredVoiceIdentifierKey = "vovozinha.preferredVoiceIdentifier"

    /// User-facing note: true local diffusion pack is Phase 3; mock illustrator always available.
    static var illustrationPackInstalled: Bool {
        get { UserDefaults.standard.bool(forKey: illustrationPackInstalledKey) }
        set { UserDefaults.standard.set(newValue, forKey: illustrationPackInstalledKey) }
    }

    static var preferredVoiceIdentifier: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: preferredVoiceIdentifierKey) ?? ""
            return raw.isEmpty ? nil : raw
        }
        set {
            UserDefaults.standard.set(newValue ?? "", forKey: preferredVoiceIdentifierKey)
        }
    }
}
