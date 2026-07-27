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

/// Offline template-based generator for the multi-module bootstrap.
///
/// The generator **analyzes the seed** (extracts up to 3 key content words after filtering
/// per-language stopwords/common verbs) and **composes a fresh story each time** by randomly
/// picking one of several template variants per narrative beat, weaving the extracted
/// elements through the whole arc — so the same seed no longer yields the same story, and
/// different seeds produce stories that are actually about them.
///
/// The full seed text is still embedded **verbatim exactly once** (paragraph 0, the story's
/// spark); everywhere else only the extracted elements are woven in.
///
/// Generation **instructions** live in `Resources/Prompts/offline.<lang>.md` and must
/// receive the parent's story description via placeholders (never leave them raw). The
/// placeholder helpers below are shared with the LiteRT-LM generator.
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

    /// Picks a variant index in `0..<upperBound`. Injected so tests can be deterministic.
    private let pickVariant: @Sendable (Int) -> Int

    public init() {
        self.pickVariant = { upperBound in Int.random(in: 0..<upperBound) }
    }

    /// Test seam: deterministic variant selection (e.g. `{ _ in 0 }`).
    init(pickVariant: @escaping @Sendable (Int) -> Int) {
        self.pickVariant = pickVariant
    }

    public func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        try prompt.validate()
        try await Task.sleep(for: .milliseconds(250))

        let seed = prompt.trimmed
        let lang = prompt.language
        let elements = Self.keyElements(from: seed, language: lang)

        return StoryDraft(
            title: Self.makeTitle(elements: elements, language: lang, pick: pickVariant),
            summary: Self.makeSummary(elements: elements, language: lang, pick: pickVariant),
            seedPrompt: seed,
            paragraphs: Self.makeParagraphs(seed: seed, elements: elements, language: lang, pick: pickVariant),
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

    // MARK: - Seed analysis

    /// Extracts up to 3 key content words from the seed (original casing, original order),
    /// filtering per-language stopwords and common verbs. Always returns exactly 3 elements,
    /// padding with gentle localized generics when the seed is mostly function words.
    static func keyElements(from seed: String, language: AppLanguage) -> [String] {
        let stops = stopwords(for: language)
        var seen = Set<String>()
        var elements: [String] = []
        for raw in seed.split(whereSeparator: \.isWhitespace) {
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            let key = word.lowercased()
            guard !key.isEmpty, !stops.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            elements.append(word)
            if elements.count == 3 { break }
        }
        for generic in fallbackElements(for: language) where elements.count < 3 {
            elements.append(generic)
        }
        return elements
    }

    /// Function words + frequent verbs — what remains is the seed's “who/what/where”.
    private static func stopwords(for language: AppLanguage) -> Set<String> {
        switch language {
        case .englishUS:
            return [
                "a", "an", "the", "and", "or", "but", "so", "with", "without", "who", "that",
                "this", "these", "those", "in", "on", "under", "over", "at", "to", "of", "for",
                "by", "from", "into", "onto", "upon", "about", "above", "below", "behind",
                "beside", "between", "through", "across", "along", "around", "near", "inside",
                "outside", "up", "down", "out", "off", "is", "are", "was", "were", "be", "been",
                "being", "am", "it", "its", "his", "her", "hers", "their", "theirs", "he", "she",
                "they", "them", "we", "us", "i", "me", "my", "you", "your", "yours", "do", "does",
                "did", "done", "can", "could", "will", "would", "shall", "should", "may", "might",
                "must", "not", "no", "yes", "very", "too", "just", "then", "than", "when", "while",
                "after", "before", "because", "if", "as", "there", "here", "every", "each", "some",
                "any", "all", "both", "few", "more", "most", "other", "another", "such", "own", "same",
                "finds", "find", "found", "goes", "go", "went", "gone", "going", "sees", "see",
                "saw", "seen", "wants", "want", "wanted", "likes", "like", "liked", "loves", "love",
                "loved", "has", "have", "had", "makes", "make", "made", "takes", "take", "took",
                "taken", "gets", "get", "got", "helps", "help", "helped", "says", "say", "said",
                "plays", "play", "played", "walks", "walk", "walked", "runs", "run", "ran", "sails",
                "sail", "sailed", "flies", "fly", "flew", "dreams", "dream", "dreamed", "dreamt",
                "smiles", "smile", "smiled", "sings", "sing", "sang", "sung", "dances", "dance",
                "danced", "jumps", "jump", "jumped", "sits", "sit", "sat", "sleeps", "sleep",
                "slept", "wakes", "wake", "woke", "looks", "look", "looked", "gives", "give",
                "gave", "given", "comes", "come", "came", "meets", "meet", "met", "learns", "learn",
                "learned", "grows", "grow", "grew", "grown", "tries", "try", "tried", "asks", "ask",
                "asked", "calls", "call", "called", "wishes", "wish", "wished", "hopes", "hope",
                "hoped", "starts", "start", "started", "begins", "begin", "began", "ends", "end",
                "ended", "lives", "live", "lived"
            ]
        case .portugueseBrazil:
            return [
                "a", "o", "as", "os", "um", "uma", "uns", "umas", "e", "ou", "mas", "com", "sem",
                "que", "este", "esta", "isso", "isto", "em", "no", "na", "nos", "nas", "de", "do",
                "da", "dos", "das", "para", "por", "pela", "pelo", "sob", "sobre", "entre", "até",
                "após", "antes", "depois", "porque", "se", "como", "lá", "aqui", "é", "são", "foi",
                "era", "eram", "ser", "está", "estão", "estava", "estar", "ele", "ela", "eles",
                "elas", "nós", "eu", "você", "seu", "sua", "meu", "minha", "dele", "dela", "muito",
                "pouco", "mais", "menos", "já", "ainda", "sempre", "nunca", "também", "só", "não",
                "sim", "lhe", "lhes", "me", "te", "nos",
                "acha", "achou", "encontra", "encontrou", "vai", "vão", "vê", "viu", "viram", "quer",
                "querem", "gosta", "ama", "tem", "têm", "tinha", "faz", "fazem", "fez", "pega",
                "pegou", "ajuda", "ajudou", "diz", "disse", "brinca", "brincou", "anda", "andou",
                "corre", "correu", "navega", "navegou", "voa", "voou", "sonha", "sonhou", "sorri",
                "sorriu", "canta", "cantou", "dança", "dançou", "pula", "pulou", "sentou", "dorme",
                "dormiu", "acorda", "acordou", "olha", "olhou", "dá", "deu", "vem", "veio",
                "conhece", "conheceu", "aprende", "aprendeu", "cresce", "cresceu", "tenta", "tentou",
                "pede", "pediu", "chama", "chamou", "deseja", "desejou", "espera", "esperou",
                "começa", "começou", "termina", "terminou", "mora", "morou", "vive", "viveu"
            ]
        case .spanishSpain:
            return [
                "el", "la", "los", "las", "un", "una", "unos", "unas", "y", "o", "pero", "con",
                "sin", "que", "este", "esta", "esto", "ese", "esa", "eso", "en", "de", "del", "al",
                "a", "para", "por", "bajo", "sobre", "entre", "hasta", "tras", "antes", "después",
                "porque", "si", "como", "allí", "aquí", "es", "son", "fue", "era", "eran", "ser",
                "está", "están", "estaba", "estar", "él", "ella", "ellos", "ellas", "nosotros", "yo",
                "tú", "su", "sus", "mi", "mis", "tu", "tus", "muy", "poco", "más", "menos", "ya",
                "aún", "siempre", "nunca", "también", "solo", "no", "sí", "se", "lo", "le", "les",
                "me", "te", "nos",
                "encuentra", "encontró", "halla", "halló", "va", "van", "ve", "vio", "quiere",
                "quiso", "gusta", "ama", "amó", "tiene", "tienen", "tenía", "hace", "hizo", "coge",
                "cogió", "ayuda", "ayudó", "dice", "dijo", "juega", "jugó", "anda", "anduvo",
                "corre", "corrió", "navega", "navegó", "vuela", "voló", "sueña", "soñó", "sonríe",
                "sonrió", "canta", "cantó", "baila", "bailó", "salta", "saltó", "duerme", "durmió",
                "despierta", "despertó", "mira", "miró", "da", "dio", "viene", "vino", "conoce",
                "conoció", "aprende", "aprendió", "crece", "creció", "intenta", "intentó", "pide",
                "pidió", "llama", "llamó", "desea", "deseó", "espera", "esperó", "empieza", "empezó",
                "termina", "terminó", "vive", "vivió"
            ]
        }
    }

    private static func fallbackElements(for language: AppLanguage) -> [String] {
        switch language {
        case .englishUS:
            return ["a little friend", "a quiet place", "a small wish"]
        case .portugueseBrazil:
            return ["um amiguinho", "um lugar tranquilo", "um desejo pequenininho"]
        case .spanishSpain:
            return ["un amiguito", "un lugar tranquilo", "un deseo pequeñito"]
        }
    }

    // MARK: - Template rendering

    /// Fills `{{spark}}` (full seed) and `{{e0}}…{{e2}}` / `{{E0}}…{{E2}}` (elements, with
    /// capitalized variants for sentence starts).
    private static func render(_ template: String, seed: String, elements: [String]) -> String {
        var out = template.replacingOccurrences(of: "{{spark}}", with: seed)
        for i in 0..<3 {
            let element = i < elements.count ? elements[i] : ""
            out = out.replacingOccurrences(of: "{{E\(i)}}", with: capitalizingFirst(element))
            out = out.replacingOccurrences(of: "{{e\(i)}}", with: element)
        }
        return out
    }

    private static func capitalizingFirst(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }

    private static func renderPick(
        _ options: [String],
        seed: String,
        elements: [String],
        pick: (Int) -> Int
    ) -> String {
        render(options[pick(options.count)], seed: seed, elements: elements)
    }

    // MARK: - Story parts

    private static func makeTitle(
        elements: [String],
        language: AppLanguage,
        pick: (Int) -> Int
    ) -> String {
        renderPick(titleTemplates(for: language), seed: "", elements: elements, pick: pick)
    }

    private static func makeSummary(
        elements: [String],
        language: AppLanguage,
        pick: (Int) -> Int
    ) -> String {
        renderPick(summaryTemplates(for: language), seed: "", elements: elements, pick: pick)
    }

    private static func makeParagraphs(
        seed: String,
        elements: [String],
        language: AppLanguage,
        pick: (Int) -> Int
    ) -> [String] {
        // Weave the full seed in ONCE, as the story's spark (beat 0 templates all carry
        // `{{spark}}`). Later beats weave only the extracted elements, so the parent's typed
        // text is never pasted verbatim twice.
        beatTemplates(for: language).map { variants in
            renderPick(variants, seed: seed, elements: elements, pick: pick)
        }
    }

    // MARK: - Copy banks (2–3 variants per slot; keep tone gentle, kid-safe, parent-friendly)

    private static func titleTemplates(for language: AppLanguage) -> [String] {
        switch language {
        case .englishUS:
            return [
                "{{E0}} {{e1}}",
                "The {{e0}} {{e1}}",
                "{{E0}} {{e1}} at Night"
            ]
        case .portugueseBrazil:
            return [
                "{{E0}} {{e1}}",
                "{{E0}} {{e1}} e a noite",
                "{{E0}} {{e1}} na hora de dormir"
            ]
        case .spanishSpain:
            return [
                "{{E0}} {{e1}}",
                "{{E0}} {{e1}} y la noche",
                "{{E0}} {{e1}} a la hora de dormir"
            ]
        }
    }

    private static func summaryTemplates(for language: AppLanguage) -> [String] {
        switch language {
        case .englishUS:
            return [
                "A gentle bedtime tale about {{e0}} {{e1}} and a very special night.",
                "A soft bedtime story where {{e0}} {{e1}} discovers something wonderful about {{e2}}.",
                "A calm bedtime adventure with {{e0}} {{e1}}, ending in sweet dreams."
            ]
        case .portugueseBrazil:
            return [
                "Uma história suave de ninar sobre {{e0}} {{e1}} e uma noite muito especial.",
                "Uma história suave e aconchegante em que {{e0}} {{e1}} descobre algo lindo sobre {{e2}}.",
                "Uma história suave de aventura com {{e0}} {{e1}}, terminando em bons sonhos."
            ]
        case .spanishSpain:
            return [
                "Un cuento suave de dormir sobre {{e0}} {{e1}} y una noche muy especial.",
                "Un cuento suave y acogedor en el que {{e0}} {{e1}} descubre algo bonito sobre {{e2}}.",
                "Un cuento suave de aventura con {{e0}} {{e1}}, que termina en dulces sueños."
            ]
        }
    }

    /// 10 narrative beats (opening spark, path, problem, feelings, plan, try, help, better,
    /// lesson, goodnight) × 3 variants. Every beat-0 variant must contain `{{spark}}` exactly
    /// once — see `makeParagraphs`.
    private static func beatTemplates(for language: AppLanguage) -> [[String]] {
        switch language {
        case .englishUS:
            return [
                [
                    "Evening light softens the world. It all begins with one small idea: {{spark}}. Everything feels calm and ready for a gentle adventure.",
                    "The sky turns honey-gold and the house grows quiet. Tonight's story starts here: {{spark}}. The night air feels warm and safe.",
                    "Stars begin to blink awake. A little wish floats in: {{spark}}. And just like that, a gentle adventure begins."
                ],
                [
                    "A quiet path opens ahead for {{e0}} {{e1}}. Soft colors and a mild breeze set the place. Curiosity grows without hurry.",
                    "Not far from home, {{e0}} {{e1}} finds a trail of silver light. Each step is slow and easy. The night seems to smile.",
                    "The world feels big and kind. {{E0}} {{e1}} takes one small step, then another, and the way ahead glows softly."
                ],
                [
                    "A small gentle problem appears, light enough for little hearts. Nothing scary—only a moment that needs kindness.",
                    "Then—oh!—a tiny puzzle about {{e2}} shows itself. It is not frightening, just something that needs a caring idea.",
                    "Something is not quite right with {{e2}}. It is a small thing, the kind a brave heart can help with."
                ],
                [
                    "Feelings settle like warm blankets. There is a little worry and a little courage, side by side.",
                    "For a moment there is worry, soft as a cloud. Underneath it, courage waits, warm as cocoa.",
                    "{{E0}} {{e1}} takes a deep breath. The butterflies calm down. Being a little nervous is okay."
                ],
                [
                    "A kind plan takes shape. Simple steps, soft voices, and patience make the plan feel safe.",
                    "Together with the moonlight, an idea grows: gentle, simple, and just right for helping {{e2}}.",
                    "The plan is small and kind: one careful step at a time, with {{e2}} waiting at the end of it."
                ],
                [
                    "The first careful try happens slowly. Hands and hearts work with care. Mistakes are allowed.",
                    "Step one goes slowly, and that is fine. {{E0}} {{e1}} tries again, gently. Practice makes cozy.",
                    "The try is wobbly at first, like a foal's first steps. But wobbles are welcome here."
                ],
                [
                    "A friendly help joins in. Together is easier. The place feels brighter for a moment.",
                    "A kind friend appears, drawn by the glow of {{e2}}. Two hearts helping feel twice as light.",
                    "Help arrives softly, right on time. Nobody has to be brave all alone."
                ],
                [
                    "Things turn better. Smiles return. The air feels lighter, and hope is easy to hold.",
                    "Slowly, gently, {{e2}} feels right again. A warm brightness spreads like sunshine after rain.",
                    "The worry melts away like snow in sunshine. Everything is going to be alright."
                ],
                [
                    "The lesson of the adventure shows itself without a lecture, woven into a warm feeling of kindness and courage.",
                    "{{E0}} {{e1}} has learned something quiet and precious: gentle hearts can do big things.",
                    "No one says the lesson out loud. It just lives warm inside: being kind is its own magic."
                ],
                [
                    "Night arrives softly. Stars wink like tiny lamps. It is time for sleep, dreams, and peace.",
                    "The moon tucks the world in. {{E0}} {{e1}} yawns a tiny yawn. Sleep comes gentle and deep.",
                    "All is calm, all is bright. The story curls up like a sleepy cat. Good night, little dreamer."
                ]
            ]
        case .portugueseBrazil:
            return [
                [
                    "A luz da noite amacia o mundo. Tudo começa a partir de uma ideia: {{spark}}. O ar se sente calmo e pronto para uma aventura gentil.",
                    "O céu fica cor de mel e a casa aquietinha. A história de hoje começa assim: {{spark}}. A noite chega morna e segura.",
                    "As estrelinhas começam a piscar. Um desejo pequenininho flutua no ar: {{spark}}. E assim nasce uma aventura gentil."
                ],
                [
                    "Um caminho quieto se abre adiante para {{e0}} {{e1}}. Cores suaves e uma brisa leve marcam o lugar. A curiosidade cresce sem pressa.",
                    "Perto de casa, {{e0}} {{e1}} encontra uma trilha de luz prateada. Cada passo é devagar e tranquilo. A noite parece sorrir.",
                    "O mundo parece grande e bondoso. {{E0}} {{e1}} dá um passinho, depois outro, e o caminho brilha suave."
                ],
                [
                    "Um probleminha manso aparece, leve o bastante para corações pequeninos. Nada assustador—só um momento que pede carinho.",
                    "Então—ops!—uma charadinha pequena sobre {{e2}} aparece. Não dá medo; só pede uma ideia carinhosa.",
                    "Algo não está direitinho com {{e2}}. É coisa pequena, dessas que um coração corajoso consegue ajudar."
                ],
                [
                    "Os sentimentos se acomodam como cobertores quentes. Há um pouco de preocupação e um pouco de coragem, lado a lado.",
                    "Por um instante há uma preocupaçãozinha, macia como nuvem. Embaixo dela, a coragem espera, quentinha como chocolate.",
                    "{{E0}} {{e1}} respira fundo. As borboletas na barriga se acalmam. Sentir um pouquinho de receio é normal."
                ],
                [
                    "Um plano bondoso toma forma. Passos simples, vozes baixas e paciência fazem o plano parecer seguro.",
                    "Junto com o luar, nasce uma ideia: gentil, simples e perfeita para ajudar {{e2}}.",
                    "O plano é pequeno e cheio de carinho: um passo cuidadoso de cada vez, com {{e2}} esperando no final."
                ],
                [
                    "A primeira tentativa cuidadosa acontece devagar. Mãos e corações trabalham com carinho. Erros são permitidos.",
                    "O primeiro passo sai devagarinho, e tudo bem. {{E0}} {{e1}} tenta de novo, com jeitinho. Praticar deixa tudo aconchegante.",
                    "A tentativa sai meio tortinha, como os primeiros passos de um potrinho. Mas tropeços são bem-vindos aqui."
                ],
                [
                    "Uma ajuda amiga se junta. Juntos é mais fácil. O lugar fica mais brilhante por um momento.",
                    "Um amigo bondoso aparece, atraído pelo brilho de {{e2}}. Dois corações ajudando ficam duas vezes mais leves.",
                    "A ajuda chega de mansinho, na hora certa. Ninguém precisa ser corajoso sozinho."
                ],
                [
                    "As coisas melhoram. Os sorrisos voltam. O ar fica mais leve, e a esperança é fácil de segurar.",
                    "Devagar e com carinho, {{e2}} fica bem de novo. Um calorzinho se espalha como sol de manhã.",
                    "A preocupação derrete como neve no sol. Tudo vai ficar bem."
                ],
                [
                    "A lição da aventura aparece sem alarde, tecida num sentimento quente de carinho e coragem.",
                    "{{E0}} {{e1}} aprendeu algo quieto e precioso: corações gentis conseguem fazer coisas grandes.",
                    "Ninguém explica a lição em voz alta. Ela mora quentinha no peito: ser gentil é uma magia."
                ],
                [
                    "A noite chega macia. As estrelas piscam como lampadinhas. É hora de dormir, sonhar e ficar em paz.",
                    "A lua põe o mundo para dormir. {{E0}} {{e1}} boceja um bocejo pequenininho. O sono chega gentil e profundo.",
                    "Tudo calmo, tudo iluminado. A história se enrola como um gatinho sonolento. Boa noite, pequeno sonhador."
                ]
            ]
        case .spanishSpain:
            return [
                [
                    "La luz de la noche suaviza el mundo. Todo empieza con una pequeña idea: {{spark}}. El ambiente se siente calmado y listo para una aventura gentil.",
                    "El cielo se vuelve color miel y la casa se queda calladita. El cuento de esta noche empieza así: {{spark}}. La noche llega tibia y segura.",
                    "Las estrellitas empiezan a parpadear. Un deseo pequeñito flota en el aire: {{spark}}. Y así nace una aventura gentil."
                ],
                [
                    "Un camino quieto se abre delante para {{e0}} {{e1}}. Colores suaves y una brisa leve marcan el lugar. La curiosidad crece sin prisa.",
                    "Cerca de casa, {{e0}} {{e1}} encuentra un sendero de luz plateada. Cada paso es lento y tranquilo. La noche parece sonreír.",
                    "El mundo parece grande y bondadoso. {{E0}} {{e1}} da un pasito, luego otro, y el camino brilla suave."
                ],
                [
                    "Aparece un problemilla manso, ligero para corazones pequeños. Nada de miedo—solo un momento que pide cariño.",
                    "Entonces—¡uy!—aparece un pequeño acertijo sobre {{e2}}. No asusta; solo pide una idea cariñosa.",
                    "Algo no va del todo bien con {{e2}}. Es una cosa pequeña, de esas que un corazón valiente puede ayudar."
                ],
                [
                    "Los sentimientos se acomodan como mantas calentitas. Hay un poco de preocupación y un poco de valor, juntos.",
                    "Por un instante hay una preocupación chiquitita, suave como una nube. Debajo, el valor espera, calentito como chocolate.",
                    "{{E0}} {{e1}} respira hondo. Las mariposas de la barriga se calman. Sentir un poquito de nervios está bien."
                ],
                [
                    "Un plan bondadoso toma forma. Pasos simples, voces bajitas y paciencia hacen que el plan se sienta seguro.",
                    "Junto con la luz de la luna nace una idea: gentil, sencilla y perfecta para ayudar a {{e2}}.",
                    "El plan es pequeño y lleno de cariño: un paso cuidadoso cada vez, con {{e2}} esperando al final."
                ],
                [
                    "El primer intento cuidadoso ocurre despacio. Manos y corazones trabajan con cariño. Se permiten errores.",
                    "El primer paso sale despacito, y está bien. {{E0}} {{e1}} lo intenta otra vez, con cuidado. Practicar lo hace todo acogedor.",
                    "El intento sale un poco torcido, como los primeros pasos de un potrillo. Pero los tropiezos son bienvenidos aquí."
                ],
                [
                    "Llega una ayuda amiga. Juntos es más fácil. El lugar se siente más brillante un momento.",
                    "Un amigo bondadoso aparece, atraído por el brillo de {{e2}}. Dos corazones que ayudan pesan la mitad.",
                    "La ayuda llega despacito, justo a tiempo. Nadie tiene que ser valiente en soledad."
                ],
                [
                    "Las cosas mejoran. Vuelven las sonrisas. El aire se siente más ligero, y la esperanza es fácil de sostener.",
                    "Despacio y con cariño, {{e2}} vuelve a estar bien. Un calorcito se extiende como el sol de la mañana.",
                    "La preocupación se derrite como nieve al sol. Todo va a salir bien."
                ],
                [
                    "La lección de la aventura aparece sin sermón, tejida en un sentimiento cálido de cariño y valor.",
                    "{{E0}} {{e1}} aprendió algo quieto y precioso: los corazones gentiles pueden hacer cosas grandes.",
                    "Nadie explica la lección en voz alta. Vive calentita en el pecho: ser amable es magia de verdad."
                ],
                [
                    "La noche llega suave. Las estrellas guiñan como lamparitas. Es hora de dormir, soñar y estar en paz.",
                    "La luna arropa al mundo. {{E0}} {{e1}} bosteza un bostezo pequeñito. El sueño llega gentil y profundo.",
                    "Todo tranquilo, todo iluminado. El cuento se enrosca como un gatito dormilón. Buenas noches, pequeño soñador."
                ]
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
