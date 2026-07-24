import Foundation

struct CharacterProfile: Codable, Hashable, Sendable {
    var name: String
    /// Stable visual description reused on every page for consistency.
    var appearance: String
    var personality: String
    var lockedDescription: String

    static func fromManual(
        name: String,
        description: String,
        language: AppLanguage = .portugueseBrazil
    ) -> CharacterProfile {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? defaultHeroName(language) : trimmedName
        let appearance = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let personality = defaultPersonality(language)
        return CharacterProfile(
            name: displayName,
            appearance: appearance,
            personality: personality,
            lockedDescription: "\(displayName): \(appearance)"
        )
    }

    static func defaultHeroName(_ language: AppLanguage) -> String {
        switch language {
        case .portugueseBrazil: return "o herói"
        case .englishUS: return "the hero"
        case .spanishSpain: return "el héroe"
        }
    }

    static func defaultPersonality(_ language: AppLanguage) -> String {
        switch language {
        case .portugueseBrazil: return "curioso, gentil e corajoso de um jeito infantil"
        case .englishUS: return "curious, kind, and gently brave in a childlike way"
        case .spanishSpain: return "curioso, amable y valiente de un modo infantil"
        }
    }

    static func defaultCuteAppearance(name: String, language: AppLanguage) -> (appearance: String, locked: String) {
        switch language {
        case .portugueseBrazil:
            let a = "personagem fofo com olhos brilhantes, cores suaves e sorriso gentil, estilo de livro infantil"
            return (a, "\(name): \(a)")
        case .englishUS:
            let a = "cute character with bright eyes, soft colors and a gentle smile, children's book style"
            return (a, "\(name): \(a)")
        case .spanishSpain:
            let a = "personaje tierno con ojos brillantes, colores suaves y sonrisa amable, estilo de libro infantil"
            return (a, "\(name): \(a)")
        }
    }

    static func defaultNameOnlyDescription(name: String, language: AppLanguage) -> String {
        switch language {
        case .portugueseBrazil:
            return "personagem infantil chamado \(name), visual fofo, amigável e colorido"
        case .englishUS:
            return "children's character named \(name), cute, friendly and colorful look"
        case .spanishSpain:
            return "personaje infantil llamado \(name), aspecto tierno, amable y colorido"
        }
    }
}
