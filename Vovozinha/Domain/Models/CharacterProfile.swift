import Foundation

struct CharacterProfile: Codable, Hashable, Sendable {
    var name: String
    /// Stable visual description reused on every page for consistency.
    var appearance: String
    var personality: String
    var lockedDescription: String

    /// Short **visual** identity for the image model — same tokens every page.
    /// Appearance is mapped toward English visual tags so SD can draw the actor.
    var artIdentityLock: String {
        let look = Self.visualAppearanceEnglish(
            appearance.isEmpty ? lockedDescription : appearance
        )
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if look.isEmpty {
            return nm.isEmpty ? "cute kids anime hero character" : "\(nm), cute kids anime character"
        }
        if nm.isEmpty || look.localizedCaseInsensitiveContains(nm) {
            return look
        }
        return "\(nm), \(look)"
    }

    /// Map PT/ES/EN appearance phrases into concrete English visual tags for diffusion.
    static func visualAppearanceEnglish(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let folded = t.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        var tags: [String] = []
        let map: [(String, String)] = [
            ("urso", "teddy bear"), ("bear", "teddy bear"), ("oso", "teddy bear"),
            ("gato", "cat"), ("cat", "cat"), ("gatinho", "kitten"),
            ("cao", "dog"), ("cachorro", "dog"), ("dog", "dog"), ("perro", "dog"),
            ("coelho", "rabbit"), ("rabbit", "rabbit"), ("conejo", "rabbit"),
            ("passaro", "bird"), ("bird", "bird"), ("pajaro", "bird"),
            ("menina", "little girl"), ("girl", "little girl"), ("nina", "little girl"),
            ("menino", "little boy"), ("boy", "little boy"), ("nino", "little boy"),
            ("azul", "blue"), ("blue", "blue"),
            ("vermelho", "red"), ("red", "red"), ("rojo", "red"),
            ("verde", "green"), ("green", "green"),
            ("amarelo", "yellow"), ("yellow", "yellow"), ("amarillo", "yellow"),
            ("rosa", "pink"), ("pink", "pink"),
            ("roxo", "purple"), ("purple", "purple"), ("morado", "purple"),
            ("laranja", "orange"), ("orange", "orange"),
            ("branco", "white"), ("white", "white"), ("blanco", "white"),
            ("preto", "black"), ("black", "black"), ("negro", "black"),
            ("marrom", "brown"), ("brown", "brown"), ("marron", "brown"),
            ("cachecol", "scarf"), ("scarf", "scarf"), ("bufanda", "scarf"),
            ("chapeu", "hat"), ("hat", "hat"), ("sombrero", "hat"),
            ("oculos", "glasses"), ("glasses", "glasses"), ("gafas", "glasses"),
            ("fofo", "cute"), ("cute", "cute"), ("tierno", "cute"),
            ("macio", "soft fur"), ("soft", "soft"),
            ("olhos", "big eyes"), ("eyes", "big eyes"), ("ojos", "big eyes"),
            ("sorriso", "gentle smile"), ("smile", "gentle smile"), ("sonrisa", "gentle smile")
        ]
        for (k, v) in map where folded.contains(k) {
            if !tags.contains(v) { tags.append(v) }
        }
        if tags.isEmpty {
            // Keep original short description (user may already write visual EN).
            if t.count <= 90 { return t }
            return String(t.prefix(87)) + "…"
        }
        return tags.joined(separator: ", ")
    }

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
