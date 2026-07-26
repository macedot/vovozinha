import Foundation
import VovoUI

/// Feature boundary: seed prompt → story draft.
public protocol StoryFromPromptGenerating: Sendable {
    func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft
}

public enum StoryPromptError: Error, Equatable, Sendable {
    case invalidPrompt(StorySeedPrompt.ValidationError)
    case generationFailed
}

/// Offline deterministic generator for the multi-module bootstrap.
///
/// Generation **instructions** live in `Resources/Prompts/offline.<lang>.md` and must
/// receive the parent’s story description via placeholders (never leave them raw).
/// Until Foundation Models is wired, the story body is a lightweight offline draft
/// that still embeds that description.
public struct OfflineStoryFromPromptGenerator: StoryFromPromptGenerating {
    /// Known “insert description here” tokens across the three prompt files.
    public static let descriptionPlaceholders: [String] = [
        "[INSERT STORY DESCRIPTION HERE]",
        "[INSERIR A DESCRIÇÃO DA HISTÓRIA AQUI]",
        "[INSERTAR LA DESCRIPCIÓN DE LA HISTORIA AQUÍ]",
        "{{seed}}",
        "{{idea}}",
        "{{description}}"
    ]

    public init() {}

    public func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        try prompt.validate()
        try await Task.sleep(for: .milliseconds(250))

        let seed = prompt.trimmed
        let lang = prompt.language

        // Always fill the generation prompt so no INSERT token leaks to callers / logs / future FM.
        let filledPrompt = Self.filledGenerationPrompt(description: seed, language: lang)
        guard !filledPrompt.isEmpty,
              !Self.containsUnresolvedDescriptionPlaceholder(filledPrompt) else {
            throw StoryPromptError.generationFailed
        }
        // Keep filled prompt live for debugging / future FM path (side-effect free otherwise).
        _ = filledPrompt

        let title = Self.makeTitle(from: seed, language: lang)
        let summary = Self.makeSummary(seed: seed, language: lang)
        let paragraphs = Self.makeParagraphs(seed: seed, language: lang)

        return StoryDraft(
            title: title,
            summary: summary,
            seedPrompt: seed,
            paragraphs: paragraphs,
            language: lang
        )
    }

    // MARK: - Prompt template (user-edited MD — do not rewrite file content here)

    /// Loads `offline.<lang>.md` and substitutes the parent’s short story description.
    public static func filledGenerationPrompt(
        description: String,
        language: AppLanguage
    ) -> String {
        let path = "Prompts/offline.\(language.rawValue).md"
        let fallback = "Prompts/offline.\(AppLanguage.englishUS.rawValue).md"
        var raw = MarkdownTextCatalog.loadFile(
            path,
            bundle: .module,
            sourceFallbackRoot: sourcePromptsRoot
        )
        if raw.isEmpty {
            raw = MarkdownTextCatalog.loadFile(
                fallback,
                bundle: .module,
                sourceFallbackRoot: sourcePromptsRoot
            )
        }
        return replaceDescriptionPlaceholders(in: raw, with: description)
    }

    public static func replaceDescriptionPlaceholders(in template: String, with description: String) -> String {
        var out = template
        for token in descriptionPlaceholders {
            out = out.replacingOccurrences(of: token, with: description)
        }
        // Any remaining `[INSERT …]` / `[INSERIR …]` / `[INSERTAR …]` style tokens.
        if let regex = try? NSRegularExpression(
            pattern: #"\[(?:INSERT|INSERIR|INSERTAR)[^\]]*\]"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            let safe = NSRegularExpression.escapedTemplate(for: description)
            out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: safe)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func containsUnresolvedDescriptionPlaceholder(_ text: String) -> Bool {
        for token in descriptionPlaceholders where text.contains(token) {
            return true
        }
        return text.range(of: #"\[(?:INSERT|INSERIR|INSERTAR)[^\]]*\]"#, options: .regularExpression) != nil
    }

    // MARK: - Offline story body (not the generation prompt file)

    private static func makeTitle(from seed: String, language: AppLanguage) -> String {
        let parts = seed.split(whereSeparator: \.isWhitespace).prefix(4).map(String.init)
        guard let first = parts.first else {
            switch language {
            case .portugueseBrazil: return "História de ninar"
            case .englishUS: return "Bedtime Story"
            case .spanishSpain: return "Cuento de dormir"
            }
        }
        let head = first.prefix(1).uppercased() + first.dropFirst()
        let tail = parts.dropFirst().joined(separator: " ")
        return tail.isEmpty ? head : "\(head) \(tail)"
    }

    private static func makeSummary(seed: String, language: AppLanguage) -> String {
        switch language {
        case .portugueseBrazil:
            return "Uma história suave de ninar inspirada em: \(seed)"
        case .englishUS:
            return "A gentle bedtime story inspired by: \(seed)"
        case .spanishSpain:
            return "Un cuento suave de dormir inspirado en: \(seed)"
        }
    }

    private static func makeParagraphs(seed: String, language: AppLanguage) -> [String] {
        let idea = seed
        switch language {
        case .portugueseBrazil:
            return [
                "A luz da noite amacia o mundo. A ideia da história começa: \(idea). Tudo se sente calmo e pronto para uma aventura gentil.",
                "Um caminho quieto se abre adiante. Cores suaves e uma brisa leve marcam o lugar. A curiosidade cresce sem pressa.",
                "Um probleminha manso aparece, leve o bastante para corações pequeninos. Nada assustador—só um momento que pede carinho.",
                "Os sentimentos se acomodam como cobertores quentes. Há um pouco de preocupação e um pouco de coragem, lado a lado.",
                "Um plano bondoso toma forma. Passos simples, vozes baixas e paciência fazem o plano parecer seguro.",
                "A primeira tentativa cuidadosa acontece devagar. Mãos e corações trabalham com carinho. Erros são permitidos.",
                "Uma ajuda amiga se junta. Juntos é mais fácil. O lugar fica mais brilhante por um momento.",
                "As coisas melhoram. Os sorrisos voltam. O ar fica mais leve, e a esperança é fácil de segurar.",
                "A lição da semente brilha sem sermão—\(idea)—tecida num sentimento quente.",
                "A noite chega macia. As estrelas piscam como lampadinhas. É hora de dormir, sonhar e ficar em paz."
            ]
        case .englishUS:
            return [
                "Evening light softens the world. The idea of the story begins: \(idea). Everything feels calm and ready for a gentle adventure.",
                "A quiet path opens ahead. Soft colors and a mild breeze set the place. Curiosity grows without hurry.",
                "A small gentle problem appears, light enough for little hearts. Nothing scary—only a moment that needs kindness.",
                "Feelings settle like warm blankets. There is a little worry and a little courage, side by side.",
                "A kind plan takes shape. Simple steps, soft voices, and patience make the plan feel safe.",
                "The first careful try happens slowly. Hands and hearts work with care. Mistakes are allowed.",
                "A friendly help joins in. Together is easier. The place feels brighter for a moment.",
                "Things turn better. Smiles return. The air feels lighter, and hope is easy to hold.",
                "The lesson of the seed idea shines without a lecture—\(idea)—woven into a warm feeling.",
                "Night arrives softly. Stars wink like tiny lamps. It is time for sleep, dreams, and peace."
            ]
        case .spanishSpain:
            return [
                "La luz de la noche suaviza el mundo. La idea del cuento empieza: \(idea). Todo se siente calmado y listo para una aventura gentil.",
                "Un camino quieto se abre delante. Colores suaves y una brisa leve marcan el lugar. La curiosidad crece sin prisa.",
                "Aparece un problemilla manso, ligero para corazones pequeños. Nada de miedo—solo un momento que pide cariño.",
                "Los sentimientos se acomodan como mantas calentitas. Hay un poco de preocupación y un poco de valor, juntos.",
                "Un plan bondadoso toma forma. Pasos simples, voces bajitas y paciencia hacen que el plan se sienta seguro.",
                "El primer intento cuidadoso ocurre despacio. Manos y corazones trabajan con cariño. Se permiten errores.",
                "Llega una ayuda amiga. Juntos es más fácil. El lugar se siente más brillante un momento.",
                "Las cosas mejoran. Vuelven las sonrisas. El aire se siente más ligero, y la esperanza es fácil de sostener.",
                "La lección de la semilla brilla sin sermón—\(idea)—tejida en un sentimiento cálido.",
                "La noche llega suave. Las estrellas guiñan como lamparitas. Es hora de dormir, soñar y estar en paz."
            ]
        }
    }

    /// Filesystem root of `Resources/` (used to load prompts from disk in tests / DEBUG).
    public static var sourcePromptsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }
}
