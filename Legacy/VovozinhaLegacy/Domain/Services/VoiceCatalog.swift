import Foundation
import AVFoundation

/// Offline system voices only (AVSpeech). No cloud processing.
enum VoiceCatalog {
    struct Entry: Identifiable, Hashable, Sendable {
        var id: String { identifier }
        let identifier: String
        let name: String
        let language: String
        let qualityRank: Int
        let qualityLabel: String
    }

    /// Higher is better. Premium > enhanced > default.
    static func qualityRank(of voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        @unknown default: return 0
        }
    }

    static func qualityLabel(of voice: AVSpeechSynthesisVoice, lang: AppLanguage) -> String {
        switch voice.quality {
        case .premium:
            switch lang {
            case .portugueseBrazil: return "Premium"
            case .englishUS: return "Premium"
            case .spanishSpain: return "Premium"
            }
        case .enhanced:
            switch lang {
            case .portugueseBrazil: return "Aprimorada"
            case .englishUS: return "Enhanced"
            case .spanishSpain: return "Mejorada"
            }
        default:
            switch lang {
            case .portugueseBrazil: return "Padrão"
            case .englishUS: return "Default"
            case .spanishSpain: return "Estándar"
            }
        }
    }

    static func voices(forLanguageCode bcp47: String) -> [Entry] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let exact = all.filter { $0.language == bcp47 }
        let prefix = String(bcp47.prefix(2))
        let list = exact.isEmpty ? all.filter { $0.language.hasPrefix(prefix) } : exact
        return list
            .map { voice in
                Entry(
                    identifier: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    qualityRank: qualityRank(of: voice),
                    qualityLabel: qualityLabel(of: voice, lang: AppLanguage(rawValue: bcp47) ?? .englishUS)
                )
            }
            .sorted {
                if $0.qualityRank != $1.qualityRank { return $0.qualityRank > $1.qualityRank }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static func voices(for language: AppLanguage) -> [Entry] {
        voices(forLanguageCode: language.speechLanguage)
    }

    /// Best installed voice for a language, honoring optional user pick.
    /// Prefers exact BCP-47 match (pt-BR over pt-PT), then highest quality rank.
    static func resolveVoice(
        languageCode: String,
        preferredIdentifier: String?
    ) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        if let preferredIdentifier,
           !preferredIdentifier.isEmpty,
           let picked = all.first(where: { $0.identifier == preferredIdentifier }),
           voiceMatchesLanguage(picked, languageCode: languageCode) {
            return picked
        }

        let candidates = all.filter { voiceMatchesLanguage($0, languageCode: languageCode) }
        // Exact language first (e.g. pt-BR), then quality.
        let ranked = candidates.sorted { a, b in
            let aExact = a.language == languageCode ? 1 : 0
            let bExact = b.language == languageCode ? 1 : 0
            if aExact != bExact { return aExact > bExact }
            if qualityRank(of: a) != qualityRank(of: b) {
                return qualityRank(of: a) > qualityRank(of: b)
            }
            // Prefer identifiers that look like enhanced/premium assets when quality ties.
            return voiceAssetScore(a) > voiceAssetScore(b)
        }
        if let best = ranked.first {
            return best
        }
        if let exact = AVSpeechSynthesisVoice(language: languageCode) {
            return exact
        }
        return all.first
    }

    /// Heuristic when multiple voices share the same quality enum value.
    private static func voiceAssetScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        let id = voice.identifier.lowercased()
        var score = 0
        if id.contains("premium") { score += 4 }
        if id.contains("enhanced") || id.contains("premium") == false && id.contains("siri") {
            score += 2
        }
        if id.contains("compact") { score -= 3 }
        if id.contains("eloquence") { score -= 1 } // often more robotic
        return score
    }

    static func hasEnhancedOrBetter(for language: AppLanguage) -> Bool {
        voices(for: language).contains { $0.qualityRank >= 2 }
    }

    private static func voiceMatchesLanguage(_ voice: AVSpeechSynthesisVoice, languageCode: String) -> Bool {
        if voice.language == languageCode { return true }
        return voice.language.hasPrefix(String(languageCode.prefix(2)))
    }
}
