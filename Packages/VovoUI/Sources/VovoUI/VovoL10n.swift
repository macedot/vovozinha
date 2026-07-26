import Foundation

/// Lightweight in-app strings for PT / EN / ES (shared UI + story prompt).
public enum VovoL10n {
    public enum Key: String, Sendable {
        case language

        // Story prompt feature
        case storySeedTitle
        case storySeedSubtitle
        case storySeedPlaceholder
        case storyWordCount
        case storyNeedMinWords
        case storyTooLong
        case storyCreate
        case storyScene
        case storyInvalidPrompt
        case storyGenerateFailed
        case storyValidationTooShort
        case storyValidationTooLong
    }

    public static func t(_ key: Key, _ lang: AppLanguage) -> String {
        table[key]?[lang] ?? table[key]?[.englishUS] ?? key.rawValue
    }

    /// Format helpers that embed numbers.
    public static func wordCount(current: Int, max: Int, lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "\(current) / \(max) palavras"
        case .englishUS: return "\(current) / \(max) words"
        case .spanishSpain: return "\(current) / \(max) palabras"
        }
    }

    public static func needMinWords(_ min: Int, lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Precisa de pelo menos \(min)"
        case .englishUS: return "Need at least \(min)"
        case .spanishSpain: return "Necesita al menos \(min)"
        }
    }

    public static func tooLong(max: Int, lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Muito longo (máx. \(max))"
        case .englishUS: return "Too long (max \(max))"
        case .spanishSpain: return "Demasiado largo (máx. \(max))"
        }
    }

    public static func scene(_ index: Int, lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Cena \(index)"
        case .englishUS: return "Scene \(index)"
        case .spanishSpain: return "Escena \(index)"
        }
    }

    public static func validationTooShort(min: Int, current: Int, lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Use pelo menos \(min) palavras (agora \(current))."
        case .englishUS: return "Use at least \(min) words (now \(current))."
        case .spanishSpain: return "Usa al menos \(min) palabras (ahora \(current))."
        }
    }

    public static func validationTooLong(max: Int, current: Int, lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil: return "Use no máximo \(max) palavras (agora \(current))."
        case .englishUS: return "Use at most \(max) words (now \(current))."
        case .spanishSpain: return "Usa como máximo \(max) palabras (ahora \(current))."
        }
    }

    public static func seedSubtitle(min: Int, max: Int, lang: AppLanguage) -> String {
        switch lang {
        case .portugueseBrazil:
            return "Descreva a base da história em \(min)–\(max) palavras."
        case .englishUS:
            return "Describe the base of the story in \(min)–\(max) words."
        case .spanishSpain:
            return "Describe la base del cuento en \(min)–\(max) palabras."
        }
    }

    private static let table: [Key: [AppLanguage: String]] = [
        .language: [
            .portugueseBrazil: "Idioma",
            .englishUS: "Language",
            .spanishSpain: "Idioma"
        ],
        .storySeedTitle: [
            .portugueseBrazil: "Semente da história",
            .englishUS: "Story seed",
            .spanishSpain: "Semilla del cuento"
        ],
        .storySeedSubtitle: [
            .portugueseBrazil: "Descreva a base da história.",
            .englishUS: "Describe the base of the story.",
            .spanishSpain: "Describe la base del cuento."
        ],
        .storySeedPlaceholder: [
            .portugueseBrazil: "Uma ideia aconchegante para uma história de ninar…",
            .englishUS: "A cozy idea for a gentle bedtime story…",
            .spanishSpain: "Una idea acogedora para un cuento de dormir…"
        ],
        .storyWordCount: [
            .portugueseBrazil: "palavras",
            .englishUS: "words",
            .spanishSpain: "palabras"
        ],
        .storyNeedMinWords: [
            .portugueseBrazil: "Precisa de mais palavras",
            .englishUS: "Need more words",
            .spanishSpain: "Necesita más palabras"
        ],
        .storyTooLong: [
            .portugueseBrazil: "Muito longo",
            .englishUS: "Too long",
            .spanishSpain: "Demasiado largo"
        ],
        .storyCreate: [
            .portugueseBrazil: "Criar história",
            .englishUS: "Create story",
            .spanishSpain: "Crear cuento"
        ],
        .storyScene: [
            .portugueseBrazil: "Cena",
            .englishUS: "Scene",
            .spanishSpain: "Escena"
        ],
        .storyInvalidPrompt: [
            .portugueseBrazil: "Ideia inválida.",
            .englishUS: "Invalid prompt.",
            .spanishSpain: "Idea no válida."
        ],
        .storyGenerateFailed: [
            .portugueseBrazil: "Não foi possível criar a história. Tente de novo.",
            .englishUS: "Could not create the story. Try again.",
            .spanishSpain: "No se pudo crear el cuento. Inténtalo de nuevo."
        ],
        .storyValidationTooShort: [
            .portugueseBrazil: "Muito curto",
            .englishUS: "Too short",
            .spanishSpain: "Demasiado corto"
        ],
        .storyValidationTooLong: [
            .portugueseBrazil: "Muito longo",
            .englishUS: "Too long",
            .spanishSpain: "Demasiado largo"
        ]
    ]
}
