import Foundation

struct StoryDraftInput: Sendable {
    /// Historical range; text-only phase forces `FeatureFlags.fixedPageCount` (10).
    static let pageCountRange = 4...10
    static let defaultPageCount = FeatureFlags.fixedPageCount

    /// Display name of the single actor (toy or child).
    var actorName: String
    /// Visual / who they are.
    var actorDescription: String
    var photoData: Data?
    var setting: String
    var lesson: String
    var ageBand: AgeBand
    var artStyle: ArtStyle
    /// Optional plot hint (not multi-actor relations).
    var storyIdea: String
    /// Target book length (clamped to `pageCountRange` when generating).
    var pageCount: Int
    /// Language for generated story text (and UI when creating).
    var language: AppLanguage

    // MARK: - Trimmed

    var trimmedActorName: String {
        actorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedActorDescription: String {
        actorDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSetting: String {
        setting.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLesson: String {
        lesson.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedStoryIdea: String {
        storyIdea.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var clampedPageCount: Int {
        min(max(pageCount, Self.pageCountRange.lowerBound), Self.pageCountRange.upperBound)
    }

    // MARK: - Presence

    var hasPhoto: Bool { photoData != nil }
    var hasName: Bool { !trimmedActorName.isEmpty }
    var hasDescription: Bool { !trimmedActorDescription.isEmpty }

    var hasActorIdentity: Bool {
        hasPhoto || hasName || hasDescription
    }

    var isValid: Bool {
        hasActorIdentity && !trimmedSetting.isEmpty && !trimmedLesson.isEmpty
    }

    // MARK: - Helpers

    /// Priority: name → photo default → description snippet.
    func resolvedActorName() -> String {
        if hasName { return trimmedActorName }
        if hasPhoto { return "Luma" }
        if hasDescription {
            let words = trimmedActorDescription.split(separator: " ").prefix(3)
            let snippet = words.joined(separator: " ")
            return snippet.isEmpty ? CharacterProfile.defaultHeroName(language) : snippet
        }
        return CharacterProfile.defaultHeroName(language)
    }

    func parametersSummaryLine() -> String {
        let lang = language
        var parts: [String] = []
        if !trimmedSetting.isEmpty {
            parts.append(Self.labelWorld(lang) + ": \(trimmedSetting)")
        }
        if !trimmedLesson.isEmpty {
            parts.append(Self.labelLesson(lang) + ": \(trimmedLesson)")
        }
        parts.append(Self.labelAge(lang) + ": \(ageBand.title(lang))")
        parts.append(Self.labelPages(lang) + ": \(clampedPageCount)")
        parts.append(Self.labelCharacter(lang) + ": \(resolvedActorName())")
        return parts.joined(separator: " · ")
    }

    private static func labelWorld(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Mundo"
        case .englishUS: return "World"
        case .spanishSpain: return "Mundo"
        }
    }

    private static func labelLesson(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Lição"
        case .englishUS: return "Lesson"
        case .spanishSpain: return "Lección"
        }
    }

    private static func labelAge(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Idade"
        case .englishUS: return "Age"
        case .spanishSpain: return "Edad"
        }
    }

    private static func labelPages(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Páginas"
        case .englishUS: return "Pages"
        case .spanishSpain: return "Páginas"
        }
    }

    private static func labelCharacter(_ lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Personagem"
        case .englishUS: return "Character"
        case .spanishSpain: return "Personaje"
        }
    }

    static func settingSuggestions(for lang: AppLanguage) -> [String] {
        switch lang {
        case .portugueseBrazil:
            return [
                "Floresta encantada", "Fundo do mar", "Castelo mágico", "Fazenda",
                "Espaço sideral", "Quarto à noite", "Nuvens fofas", "Jardim secreto"
            ]
        case .englishUS:
            return [
                "Enchanted forest", "Under the sea", "Magic castle", "Farm",
                "Outer space", "Bedroom at night", "Fluffy clouds", "Secret garden"
            ]
        case .spanishSpain:
            return [
                "Bosque encantado", "Fondo del mar", "Castillo mágico", "Granja",
                "Espacio sideral", "Habitación de noche", "Nubes suaves", "Jardín secreto"
            ]
        }
    }

    static func lessonSuggestions(for lang: AppLanguage) -> [String] {
        switch lang {
        case .portugueseBrazil:
            return ["Bondade", "Coragem", "Empatia", "Amizade", "Partilhar", "Honestidade", "Paciência", "Perdoar"]
        case .englishUS:
            return ["Kindness", "Courage", "Empathy", "Friendship", "Sharing", "Honesty", "Patience", "Forgiveness"]
        case .spanishSpain:
            return ["Bondad", "Valor", "Empatía", "Amistad", "Compartir", "Honestidad", "Paciencia", "Perdonar"]
        }
    }

    /// Quick-create: actor only; everything else is randomized for a surprise kids story.
    static func randomized(actorDescription: String, photoData: Data?, language: AppLanguage) -> StoryDraftInput {
        let settings = settingSuggestions(for: language)
        let lessons = lessonSuggestions(for: language)
        return StoryDraftInput(
            actorName: "",
            actorDescription: actorDescription,
            photoData: photoData,
            setting: settings.randomElement() ?? settings[0],
            lesson: lessons.randomElement() ?? lessons[0],
            ageBand: AgeBand.allCases.randomElement() ?? .threeToFive,
            artStyle: ArtStyle.allCases.randomElement() ?? .watercolor,
            storyIdea: "",
            pageCount: FeatureFlags.fixedPageCount,
            language: language
        )
    }
}
