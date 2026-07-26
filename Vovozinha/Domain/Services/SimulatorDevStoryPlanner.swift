import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

private let simPlannerLog = Logger(subsystem: "app.vovozinha", category: "SimDevPlanner")

/// **Simulator-only entry point for story planning.**
///
/// Invariant: never surfaces `StoryPlanningError.llmUnavailable` to the UI.
/// Tries Foundation Models when assets exist; on any failure (or if FM is missing),
/// builds a draft-parameterized 10-page arc so Create/Generate always completes in sim.
///
/// Not used on physical devices. Not a fixed story library — pages use the current
/// actor / world / lesson / language.
struct SimulatorAwareStoryPlanner: StoryPlanning {
    func plan(input: StoryDraftInput, character: CharacterProfile) async throws -> StoryPlan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            let ready = model.isAvailable || SystemLanguageModel.default.isAvailable
            if ready {
                do {
                    simPlannerLog.info("Simulator: trying Foundation Models")
                    return try await FoundationModelsStoryPlanner().plan(input: input, character: character)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // FM claimed ready then failed (common when assets flaky) → always recover.
                    simPlannerLog.notice(
                        "Simulator: FM failed (\(String(describing: error), privacy: .public)) — dev story builder"
                    )
                }
            } else {
                simPlannerLog.notice("Simulator: Foundation Models not ready — dev story builder")
            }
        } else {
            simPlannerLog.notice("Simulator: iOS < 26 — dev story builder")
        }
        #else
        simPlannerLog.notice("Simulator: FoundationModels not linked — dev story builder")
        #endif

        return try await SimulatorDevStoryPlanner().plan(input: input, character: character)
    }
}

/// Builds a gentle continuous 10-page story from the draft (Simulator development only).
/// Prefer never throwing (except cancellation).
struct SimulatorDevStoryPlanner: StoryPlanning {
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
            simPlannerLog.notice("Simulator dev plan safety issues — using ultra-safe pages")
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

        simPlannerLog.info("Simulator dev story ready words=\(KidsSafetyFilter.wordCount(plan))")
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
            name: name,
            look: look,
            world: world,
            character: character,
            ageBand: ageBand,
            artStyle: artStyle,
            lesson: lesson
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
        let bodies: [String]
        switch language {
        case .portugueseBrazil:
            bodies = (0..<10).map { i in
                "\(n) vive um momento calmo em \(w). O sol é suave e o ar é doce. \(n) sorri e aprende sobre \(lesson). Tudo é seguro e gentil. Página \(i + 1) do conto de ninar."
            }
        case .englishUS:
            bodies = (0..<10).map { i in
                "\(n) has a calm moment in \(w). The sun is soft and the air is sweet. \(n) smiles and learns about \(lesson). Everything is safe and kind. Bedtime page \(i + 1)."
            }
        case .spanishSpain:
            bodies = (0..<10).map { i in
                "\(n) vive un momento calmado en \(w). El sol es suave y el aire es dulce. \(n) sonríe y aprende sobre \(lesson). Todo es seguro y amable. Página \(i + 1) del cuento."
            }
        }
        return makePlan(
            title: title(name: n, world: w, language: language),
            summary: summary(name: n, world: w, lesson: lesson, language: language),
            bodies: bodies,
            name: n,
            look: "cute kids character",
            world: w,
            character: character,
            ageBand: ageBand,
            artStyle: artStyle,
            lesson: lesson
        )
    }

    private static func makePlan(
        title: String,
        summary: String,
        bodies: [String],
        name: String,
        look: String,
        world: String,
        character: CharacterProfile,
        ageBand: AgeBand,
        artStyle: ArtStyle,
        lesson: String
    ) -> StoryPlan {
        let tags = StorySceneTags.ordered
        var pages: [StoryPlanPage] = []
        for (i, body) in bodies.enumerated() {
            let tag = i < tags.count ? tags[i] : "story"
            pages.append(
                StoryPlanPage(
                    index: i,
                    text: body,
                    imagePrompt: "\(name), \(look), \(world), \(tag), kids bedtime illustration",
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

    private static func pageTexts(
        name: String,
        look: String,
        world: String,
        lesson: String,
        idea: String,
        language: AppLanguage
    ) -> [String] {
        let extra: String = {
            guard !idea.isEmpty else { return "" }
            switch language {
            case .portugueseBrazil: return " \(name) também pensa em \(idea)."
            case .englishUS: return " \(name) also thinks about \(idea)."
            case .spanishSpain: return " \(name) también piensa en \(idea)."
            }
        }()

        switch language {
        case .portugueseBrazil:
            return [
                "\(name) acorda com um sorriso. \(name) é \(look). O ar cheira a manhã em \(world). Um raio de sol quente toca o chão. Hoje parece um dia especial e calmo.",
                "\(name) dá passos leves por \(world). Folhas suaves balançam. Um pássaro pequenino canta. As cores são claras e amigas. \(name) olha em volta com curiosidade boa.",
                "De repente, \(name) vê um amiguinho um pouco triste. Algo pequeno caiu do ninho. \(name) sente um puxão gentil no peito. Posso ajudar, pensa \(name) com carinho.",
                "\(name) respira fundo. O vento traz um perfume doce. \(name) sente um pouco de preocupação, mas também coragem mansa. As mãos de \(name) querem ser úteis.",
                "Então \(name) tem uma ideia bondosa. Vamos tentar com calma e paciência. \(name) escolhe um caminho seguro entre as flores de \(world). A luz da tarde é dourada e macia.",
                "\(name) tenta a primeira vez com muito cuidado. O amiguinho espera. \(name) fala baixinho palavras de ânimo. Nada precisa ser perfeito. Só precisa ser gentil.",
                "Um vizinho amável chega para ajudar também. Juntos, \(name) e o amigo levantam o que caiu. \(world) parece mais brilhante. \(name) sente o peito quentinho de alegria.",
                "Agora o pequenino sorri de novo. \(name) ri baixinho. As nuvens passam devagar. O sol pinta o céu de laranja suave. Tudo fica mais leve e feliz em \(world).",
                "\(name) entende a lição de \(lesson). Ajudar com calma faz o dia crescer. \(name) guarda esse sentimento como um abraço.\(extra) O coração de \(name) fica sereno.",
                "A noite chega mansa sobre \(world). \(name) boceja e se aconchega. Estrelas piscam como lâmpadas de ninar. Boa noite, sussurra \(name). É hora de sonhar com paz."
            ]
        case .englishUS:
            return [
                "\(name) wakes with a soft smile. \(name) is \(look). Morning air smells fresh in \(world). Warm sunlight touches the ground. Today feels special and calm.",
                "\(name) takes gentle steps through \(world). Soft leaves sway. A tiny bird sings. The colors look friendly and bright. \(name) looks around with kind curiosity.",
                "Suddenly \(name) notices a little friend who seems sad. Something small has fallen from a nest. \(name) feels a gentle tug in the heart. I can help, thinks \(name) kindly.",
                "\(name) takes a deep breath. The breeze smells sweet. \(name) feels a little worry and also quiet courage. \(name) wants to be useful and careful.",
                "Then \(name) has a kind idea. We will try with calm and patience. \(name) chooses a safe path among the flowers of \(world). Afternoon light is golden and soft.",
                "\(name) tries the first careful attempt. The little friend waits. \(name) whispers brave, gentle words. Nothing needs to be perfect. It only needs to be kind.",
                "A friendly neighbor comes to help too. Together, \(name) and the friend lift what fell. \(world) looks brighter. \(name) feels a warm, happy glow inside.",
                "Now the little one smiles again. \(name) laughs softly. Clouds drift slowly. The sun paints the sky soft orange. Everything feels lighter and happier in \(world).",
                "\(name) understands the lesson of \(lesson). Helping with calm makes the day grow. \(name) keeps that feeling like a hug.\(extra) \(name) feels peaceful.",
                "Night settles gently over \(world). \(name) yawns and snuggles close. Stars twinkle like bedtime lamps. Good night, whispers \(name). It is time to dream of peace."
            ]
        case .spanishSpain:
            return [
                "\(name) despierta con una sonrisa suave. \(name) es \(look). El aire de la mañana huele fresco en \(world). Un rayo de sol cálido toca el suelo. Hoy parece un día especial y calmado.",
                "\(name) da pasos suaves por \(world). Las hojas se mueven despacio. Un pajarito canta. Los colores son claros y amables. \(name) mira alrededor con buena curiosidad.",
                "De pronto, \(name) ve a un amiguito un poco triste. Algo pequeño se cayó del nido. \(name) siente un tironcito tierno en el pecho. Puedo ayudar, piensa \(name) con cariño.",
                "\(name) respira hondo. El viento trae un perfume dulce. \(name) siente un poco de preocupación y también valor manso. Las manos de \(name) quieren ser útiles.",
                "Entonces \(name) tiene una idea bondadosa. Vamos a intentar con calma y paciencia. \(name) elige un camino seguro entre las flores de \(world). La luz de la tarde es dorada y suave.",
                "\(name) prueba la primera vez con mucho cuidado. El amiguito espera. \(name) dice bajito palabras de ánimo. Nada tiene que ser perfecto. Solo tiene que ser amable.",
                "Un vecino amable también llega a ayudar. Juntos, \(name) y el amigo levantan lo que cayó. \(world) parece más brillante. \(name) siente el pecho calentito de alegría.",
                "Ahora el pequenín sonríe otra vez. \(name) ríe bajito. Las nubes pasan despacio. El sol pinta el cielo de naranja suave. Todo se siente más ligero y feliz en \(world).",
                "\(name) entiende la lección de \(lesson). Ayudar con calma hace crecer el día. \(name) guarda ese sentimiento como un abrazo.\(extra) El corazón de \(name) queda sereno.",
                "La noche llega mansa sobre \(world). \(name) bosteza y se acurruca. Las estrellas parpadean como lamparitas de dormir. Buenas noches, susurra \(name). Es hora de soñar en paz."
            ]
        }
    }
}
