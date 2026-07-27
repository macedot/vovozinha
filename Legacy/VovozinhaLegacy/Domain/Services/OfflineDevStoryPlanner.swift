import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

private let offlineDevPlannerLog = Logger(subsystem: "app.vovozinha", category: "OfflineDevPlanner")

/// **DEBUG / Mac (Designed for iPad) entry point for story planning.**
///
/// Invariant: never surfaces `StoryPlanningError.llmUnavailable` to the UI.
/// Tries Foundation Models when assets exist; on any failure (or if FM is missing),
/// builds a draft-parameterized 10-page arc so Create/Generate always completes in DEBUG/Mac.
///
/// Not a fixed story library — pages use the current
/// actor / world / lesson / language.
struct OfflineAwareStoryPlanner: StoryPlanning {
    func plan(input: StoryDraftInput, character: CharacterProfile) async throws -> StoryPlan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            let ready = model.isAvailable || SystemLanguageModel.default.isAvailable
            if ready {
                do {
                    offlineDevPlannerLog.info("Dev offline: trying Foundation Models")
                    return try await FoundationModelsStoryPlanner().plan(input: input, character: character)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // FM claimed ready then failed (common when assets flaky) → always recover.
                    offlineDevPlannerLog.notice(
                        "Dev offline: FM failed (\(String(describing: error), privacy: .public)) — dev story builder"
                    )
                }
            } else {
                offlineDevPlannerLog.notice("Dev offline: Foundation Models not ready — dev story builder")
            }
        } else {
            offlineDevPlannerLog.notice("Dev offline: iOS < 26 — dev story builder")
        }
        #else
        offlineDevPlannerLog.notice("Dev offline: FoundationModels not linked — dev story builder")
        #endif

        return try await OfflineDevStoryPlanner().plan(input: input, character: character)
    }
}

/// Builds a gentle continuous 10-page story from the draft (DEBUG development only).
/// Prefer never throwing (except cancellation).
struct OfflineDevStoryPlanner: StoryPlanning {
    func plan(input: StoryDraftInput, character: CharacterProfile) async throws -> StoryPlan {
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(200))

        let lang = input.language
        let name = Self.sanitize(
            character.name.isEmpty ? CharacterProfile.defaultHeroName(lang) : character.name
        )
        let look = Self.sanitize(
            character.appearance.isEmpty ? character.lockedDescription : character.appearance
        )
        let world = Self.sanitize(
            input.trimmedSetting.isEmpty
                ? (StoryDraftInput.settingSuggestions(for: lang).first ?? "garden")
                : input.trimmedSetting
        )
        let lesson = Self.sanitize(
            input.trimmedLesson.isEmpty
                ? (StoryDraftInput.lessonSuggestions(for: lang).first ?? "kindness")
                : input.trimmedLesson
        )
        let idea = Self.sanitize(input.storyIdea.trimmingCharacters(in: .whitespacesAndNewlines))

        var plan = Self.buildPlan(
            name: name,
            look: look,
            world: world,
            lesson: lesson,
            idea: idea,
            language: lang,
            character: character,
            ageBand: input.ageBand,
            artStyle: input.artStyle
        )
        plan = StoryDraftRepair.repair(plan, language: lang)

        if !KidsSafetyFilter.safetyIssues(plan: plan).isEmpty {
            offlineDevPlannerLog.notice("Offline dev plan safety issues — using ultra-safe pages")
            plan = Self.ultraSafePlan(
                name: name,
                world: world,
                lesson: lesson,
                language: lang,
                character: character,
                ageBand: input.ageBand,
                artStyle: input.artStyle
            )
            plan = StoryDraftRepair.repair(plan, language: lang)
        }

        // Last resort: guaranteed safe pages (sim must never fail with llmUnavailable).
        if !KidsSafetyFilter.safetyIssues(plan: plan).isEmpty {
            plan = Self.ultraSafePlan(
                name: "Luma",
                world: "garden",
                lesson: "kindness",
                language: lang,
                character: character,
                ageBand: input.ageBand,
                artStyle: input.artStyle
            )
        }

        offlineDevPlannerLog.info("Offline dev story ready words=\(KidsSafetyFilter.wordCount(plan))")
        return plan
    }

    // MARK: - Builders

    private static func buildPlan(
        name: String,
        look: String,
        world: String,
        lesson: String,
        idea: String,
        language: AppLanguage,
        character: CharacterProfile,
        ageBand: AgeBand,
        artStyle: ArtStyle
    ) -> StoryPlan {
        let bodies = pageTexts(
            name: name, look: look, world: world, lesson: lesson, idea: idea, language: language
        )
        return makePlan(
            title: title(name: name, world: world, language: language),
            summary: summary(name: name, world: world, lesson: lesson, language: language),
            bodies: bodies,
            world: world,
            character: character,
            ageBand: ageBand,
            artStyle: artStyle,
            lesson: lesson,
            language: language
        )
    }

    private static func ultraSafePlan(
        name: String,
        world: String,
        lesson: String,
        language: AppLanguage,
        character: CharacterProfile,
        ageBand: AgeBand,
        artStyle: ArtStyle
    ) -> StoryPlan {
        let n = name.isEmpty ? "Luma" : name
        let w = world.isEmpty ? "garden" : world
        // Distinct scene beats even in ultra-safe mode (not the same sentence 10 times).
        let bodies = pageTexts(
            name: n,
            look: "soft friendly character",
            world: w,
            lesson: lesson,
            idea: "",
            language: language
        )
        return makePlan(
            title: title(name: n, world: w, language: language),
            summary: summary(name: n, world: w, lesson: lesson, language: language),
            bodies: bodies,
            world: w,
            character: character,
            ageBand: ageBand,
            artStyle: artStyle,
            lesson: lesson,
            language: language
        )
    }

    private static func makePlan(
        title: String,
        summary: String,
        bodies: [String],
        world: String,
        character: CharacterProfile,
        ageBand: AgeBand,
        artStyle: ArtStyle,
        lesson: String,
        language: AppLanguage
    ) -> StoryPlan {
        var pages: [StoryPlanPage] = []
        for (i, body) in bodies.enumerated() {
            let tag = StorySceneTags.tag(at: i)
            let imagePrompt = ScenePromptBuilder.prompt(
                pageText: body,
                sceneTag: tag,
                character: character,
                setting: world,
                artStyle: artStyle,
                language: language,
                pageIndex: i,
                totalPages: bodies.count
            )
            pages.append(
                StoryPlanPage(
                    index: i,
                    text: body,
                    imagePrompt: imagePrompt,
                    narrationHint: i >= 8 ? "soft slow" : "calm",
                    sceneTag: tag
                )
            )
        }
        return StoryPlan(
            title: title,
            summary: summary,
            character: character,
            setting: world,
            lesson: lesson,
            ageBand: ageBand,
            artStyle: artStyle,
            pages: pages
        )
    }

    /// Drop characters that might confuse filters; keep letters/numbers/spaces/basic punctuation.
    private static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: ".,!?'-áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇñÑüÜ"))
        return String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Localized narrative (parameterized by draft)

    private static func title(name: String, world: String, language: AppLanguage) -> String {
        switch language {
        case .portugueseBrazil: return "\(name) e o \(world)"
        case .englishUS: return "\(name) and the \(world)"
        case .spanishSpain: return "\(name) y el \(world)"
        }
    }

    private static func summary(name: String, world: String, lesson: String, language: AppLanguage) -> String {
        switch language {
        case .portugueseBrazil:
            return "\(name) explora \(world) e aprende sobre \(lesson) num conto suave de ninar."
        case .englishUS:
            return "\(name) explores \(world) and learns about \(lesson) in a gentle bedtime story."
        case .spanishSpain:
            return "\(name) explora \(world) y aprende sobre \(lesson) en un cuento suave de dormir."
        }
    }

    /// Ten scene paragraphs (setup…bedtime). Look only on setup; later pages are scene-led.
    private static func pageTexts(
        name: String,
        look: String,
        world: String,
        lesson: String,
        idea: String,
        language: AppLanguage
    ) -> [String] {
        let ideaBit: String = {
            guard !idea.isEmpty else { return "" }
            switch language {
            case .portugueseBrazil: return " Um pedacinho da ideia: \(idea)."
            case .englishUS: return " A little of the idea: \(idea)."
            case .spanishSpain: return " Un poquito de la idea: \(idea)."
            }
        }()

        switch language {
        case .portugueseBrazil:
            return [
                // setup — light first look once
                "Em \(world), a manhã chega macia e dourada. \(name) aparece: \(look). O chão é quente de sol e o ar cheira a dia novo. \(name) sorri para o começo da aventura.",
                // explore
                "O caminho em \(world) mostra cores vivas e sombras suaves. Um barulhinho alegre vem de longe. \(name) anda devagar e descobre um canto cheio de detalhes bonitos.",
                // inciting
                "Num cantinho, algo pequenino parece fora do lugar. Uma folha caiu sobre um ninho baixo. \(name) para e entende que alguém precisa de ajuda mansa.",
                // feel
                "O peito de \(name) fica apertado e também corajoso. O vento traz um perfume doce. \(name) respira fundo e quer fazer o bem com calma.",
                // plan
                "Então nasce uma ideia gentil. \(name) imagina um jeito simples e seguro de ajudar. A luz da tarde pinta \(world) de ouro manso.",
                // try
                "Com muito cuidado, \(name) tenta a primeira vez. As mãos se movem devagar. Nada precisa ser perfeito; só precisa ser bondoso.",
                // help
                "Uma ajuda amiga chega perto. Juntos levantam o que caiu e ajeitam o cantinho. \(world) parece mais brilhante e leve.",
                // turn
                "O pequenino amigo fica aliviado. As nuvens passam lentas no céu. \(name) ri baixinho e a tristeza se desfaz no ar macio.",
                // lesson
                "A lição de \(lesson) brilha sem sermão. Ajudar com paciência aquece o coração.\(ideaBit) \(name) guarda esse sentimento como um abraço quieto.",
                // bedtime
                "A noite desce suave sobre \(world). Estrelas piscam como lâmpadas de ninar. \(name) boceja, se aconchega e sussurra boa noite. É hora de sonhar em paz."
            ]
        case .englishUS:
            return [
                "In \(world), morning light is soft and golden. \(name) appears: \(look). Warm sun touches the ground and the air smells like a new day. \(name) smiles at the start of a gentle adventure.",
                "The path through \(world) shows bright colors and soft shadows. A happy little sound comes from far away. \(name) walks slowly and finds a corner full of lovely details.",
                "In a small nook, something tiny is out of place. A leaf has fallen on a low nest. \(name) stops and sees that someone needs soft help.",
                "\(name) feels a tight chest and quiet courage. The breeze smells sweet. \(name) breathes deep and wants to help with calm care.",
                "Then a kind idea grows. \(name) imagines a simple, safe way to help. Afternoon light paints \(world) in gentle gold.",
                "With great care, \(name) tries for the first time. Hands move slowly. Nothing needs to be perfect; it only needs to be kind.",
                "Friendly help comes near. Together they lift what fell and tidy the little place. \(world) looks brighter and lighter.",
                "The little friend feels better. Clouds drift slowly across the sky. \(name) laughs softly and the sadness melts in the mild air.",
                "The lesson of \(lesson) shines without a lecture. Helping with patience warms the heart.\(ideaBit) \(name) keeps that feeling like a quiet hug.",
                "Night settles gently over \(world). Stars twinkle like bedtime lamps. \(name) yawns, snuggles close, and whispers good night. It is time to dream in peace."
            ]
        case .spanishSpain:
            return [
                "En \(world), la mañana llega suave y dorada. Aparece \(name): \(look). El suelo está cálido de sol y el aire huele a día nuevo. \(name) sonríe al comienzo de la aventura.",
                "El camino de \(world) muestra colores vivos y sombras suaves. Un ruidito alegre viene de lejos. \(name) camina despacio y descubre un rincón lleno de detalles bonitos.",
                "En un rinconcito, algo pequeño está fuera de lugar. Una hoja cayó sobre un nido bajo. \(name) se detiene y ve que alguien necesita ayuda mansa.",
                "El pecho de \(name) se aprieta y también se llena de valor. El viento trae un perfume dulce. \(name) respira hondo y quiere ayudar con calma.",
                "Entonces nace una idea bondadosa. \(name) imagina una forma simple y segura de ayudar. La luz de la tarde pinta \(world) de oro suave.",
                "Con mucho cuidado, \(name) lo intenta la primera vez. Las manos se mueven despacio. Nada tiene que ser perfecto; solo tiene que ser amable.",
                "Llega una ayuda amiga. Juntos levantan lo caído y arreglan el rinconcito. \(world) parece más brillante y ligero.",
                "El amiguito se siente aliviado. Las nubes pasan lentas por el cielo. \(name) ríe bajito y la tristeza se deshace en el aire manso.",
                "La lección de \(lesson) brilla sin sermón. Ayudar con paciencia calienta el corazón.\(ideaBit) \(name) guarda ese sentimiento como un abrazo quieto.",
                "La noche baja suave sobre \(world). Las estrellas parpadean como lamparitas. \(name) bosteza, se acurruca y susurra buenas noches. Es hora de soñar en paz."
            ]
        }
    }
}
