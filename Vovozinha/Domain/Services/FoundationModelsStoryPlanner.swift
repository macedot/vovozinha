import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

private let plannerLog = Logger(subsystem: "app.vovozinha", category: "StoryPlanner")

/// On-device LLM planner: continuous story → 10 pages.
/// Structural validation is applied after **deterministic repair** so FM drafts can ship
/// even when the model ignores punctuation / length. LLM retries are mainly for safety.
struct FoundationModelsStoryPlanner: StoryPlanning {
    func plan(input: StoryDraftInput, character: CharacterProfile) async throws -> StoryPlan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await planWithFoundationModels(input: input, character: character)
        }
        #endif
        throw StoryPlanningError.llmUnavailable
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func planWithFoundationModels(input: StoryDraftInput, character: CharacterProfile) async throws -> StoryPlan {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else {
            throw StoryPlanningError.llmUnavailable
        }

        let instructions = Self.systemInstructions(language: input.language)
        let basePrompt = Self.userPrompt(input: input, character: character)
        var lastError: StoryPlanningError = .failed
        var previousHint = ""
        // Fewer LLM rounds: repair does the heavy lifting for structure.
        let maxAttempts = min(FeatureFlags.kidsFilterMaxAttempts, 6)

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()

            let temperature = max(0.4, 0.7 - Double(attempt - 1) * 0.05)
            // Room for ~10 descriptive paragraphs (~280–400 words) + title/summary.
            let options = GenerationOptions(temperature: temperature, maximumResponseTokens: 2048)
            let retrySuffix = previousHint.isEmpty
                ? ""
                : "\n\nRETRY \(attempt): \(previousHint)"

            let session = LanguageModelSession(model: model, instructions: instructions)

            do {
                let response = try await session.respond(
                    to: basePrompt + retrySuffix,
                    generating: GenerableKidsStory.self,
                    options: options
                )
                var plan = try response.content.toStoryPlan(input: input, character: character)
                plan = StoryDraftRepair.repair(plan, language: input.language)

                let safety = KidsSafetyFilter.safetyIssues(plan: plan)
                let structure = KidsSafetyFilter.structureIssues(plan: plan)
                plannerLog.info(
                    "attempt=\(attempt) words=\(KidsSafetyFilter.wordCount(plan)) safety=\(safety.count) structure=\(structure.count)"
                )

                if KidsSafetyFilter.canShip(plan) {
                    return plan
                }

                // Second repair pass if only structure remains (edge cases).
                if safety.isEmpty, !structure.isEmpty {
                    plan = StoryDraftRepair.repair(plan, language: input.language)
                    if KidsSafetyFilter.canShip(plan) {
                        return plan
                    }
                }

                if !safety.isEmpty {
                    previousHint =
                        "Previous draft had unsafe content (\(safety.joined(separator: ", "))). Rewrite a fully gentle bedtime story with no scary or adult words. Exactly 10 descriptive paragraphs, ~\(FeatureFlags.targetStoryWordCount) words total, 3–5 sentences per page with sensory detail."
                    lastError = .unsafeContent
                } else {
                    previousHint =
                        "Structure/length off (\(structure.prefix(4).joined(separator: ", "))). Exactly 10 paragraphs; aim ~\(FeatureFlags.targetStoryWordCount) words total (band \(FeatureFlags.minStoryWordCount)–\(FeatureFlags.maxStoryWordCount)); each page 3–5 short sentences with setting details; end sentences with periods."
                    lastError = .failed
                }
                continue
            } catch is CancellationError {
                throw CancellationError()
            } catch let planning as StoryPlanningError {
                if case .llmUnavailable = planning { throw planning }
                previousHint =
                    "Generation failed. Return exactly 10 safe descriptive paragraphs, ~\(FeatureFlags.targetStoryWordCount) words total, 3–5 sentences each with colors/sounds/feelings."
                lastError = planning
                continue
            } catch {
                let mapped = Self.mapGenerationError(error)
                if case .llmUnavailable = mapped { throw mapped }
                previousHint =
                    "Model error. Write a cozy descriptive bedtime story: 10 paragraphs, ~\(FeatureFlags.targetStoryWordCount) words, 3–5 sentences per scene."
                lastError = mapped
                continue
            }
        }

        throw lastError
    }

    @available(iOS 26.0, *)
    private static func mapGenerationError(_ error: Error) -> StoryPlanningError {
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .exceededContextWindowSize:
                return .contextExceeded
            default:
                break
            }
        }
        return StoryPlanningError.from(systemError: error)
    }
    #endif

    static func systemInstructions(language: AppLanguage) -> String {
        let langName: String
        switch language {
        case .portugueseBrazil: langName = "Brazilian Portuguese (pt-BR)"
        case .englishUS: langName = "American English (en-US)"
        case .spanishSpain: langName = "Spanish from Spain (es-ES)"
        }
        let target = FeatureFlags.targetStoryWordCount
        let minW = FeatureFlags.minStoryWordCount
        let maxW = FeatureFlags.maxStoryWordCount

        return """
        You are a children's BEDTIME storyteller for ages 3–8. Write ONLY in \(langName).

        METHOD:
        1) Invent ONE continuous chronological story (time only moves forward).
        2) Split it into EXACTLY 10 paragraphs (one scene / book page each).
        3) Paragraph i continues from paragraph i-1. Last paragraph is a soft good-night close.

        LENGTH (important — pages must feel full, not tiny):
        - Whole story: about \(target) words total (acceptable \(minW)–\(maxW)).
        - Each paragraph: about 25–40 words.
        - Each paragraph: 3 to 5 short sentences. Every sentence ends with "." or "!".

        SCENE DETAIL (each page must paint a picture):
        - Name what the hero sees (colors, light, objects in the setting).
        - Add one soft sense: sound, smell, temperature, or texture.
        - Show a small action and a warm feeling.
        - Keep the hero's appearance consistent when relevant.
        - Do NOT write one-line empty scenes. Avoid vague lines like only "Then they went."

        TONE & SAFETY:
        - Kind, cozy, gentle. Soft problem only; always repaired.
        - No horror, blood, weapons, drugs, adult themes, or permanent harm.
        - Weave the lesson naturally; never lecture.

        OUTPUT fields: title, summary, paragraphs (exactly 10 strings).
        """
    }

    static func userPrompt(input: StoryDraftInput, character: CharacterProfile) -> String {
        let seed = Int.random(in: 1000...999_999)
        let idea = input.trimmedStoryIdea.isEmpty ? "(gentle original plot)" : input.trimmedStoryIdea
        let example = paragraphExample(language: input.language, hero: character.name)
        let target = FeatureFlags.targetStoryWordCount

        return """
        Write a continuous kids bedtime story (seed \(seed)).
        Language: \(input.language.rawValue) ONLY.
        Age: \(input.ageBand.rawValue) — \(input.ageBand.generationHint(input.language))
        World/setting: \(input.trimmedSetting)
        Lesson: \(input.trimmedLesson)
        Parent idea: \(idea)
        Hero: \(character.name)
        Look (keep consistent): \(character.lockedDescription)
        Personality: \(character.personality)

        HARD REQUIREMENTS:
        - Exactly 10 paragraphs = 10 scenes in time order.
        - About \(target) words for the FULL story (~25–40 words per paragraph).
        - Each paragraph: 3–5 short sentences ending with . or !
        - Each scene is DESCRIPTIVE: place details + one sense (sound/color/smell/touch) + action + feeling.
        - Continuous plot; cozy and safe; lesson "\(input.trimmedLesson)" woven in; soft bedtime ending.

        Paragraph density example (match this fullness, invent new content):
        \(example)

        Story arc across the 10 pages:
        meet hero in the world → explore with sensory detail → small gentle problem appears → feelings → kind idea → try → friend helps → things get better → lesson shines → good night sleep.
        """
    }

    static func paragraphExample(language: AppLanguage, hero: String) -> String {
        let name = hero.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = name.isEmpty ? "Luma" : name
        switch language {
        case .portugueseBrazil:
            return "\(h) entra na floresta dourada e vê folhas verdes brilhantes. Um vento macio traz cheiro de flores. \(h) sorri e dá um passo leve no caminho macio."
        case .englishUS:
            return "\(h) steps into the golden forest and sees bright green leaves. A soft wind carries the smell of flowers. \(h) smiles and takes a gentle step on the soft path."
        case .spanishSpain:
            return "\(h) entra en el bosque dorado y ve hojas verdes brillantes. Un viento suave trae olor a flores. \(h) sonríe y da un paso ligero en el camino blando."
        }
    }
}

// MARK: - Guided generation

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "Kids bedtime story: title, summary, exactly 10 descriptive scene paragraphs")
struct GenerableKidsStory {
    @Guide(description: "Short kid-safe title")
    var title: String

    @Guide(description: "One or two gentle sentences summarizing the whole plot")
    var summary: String

    @Guide(
        description: "Exactly 10 paragraphs of ONE continuous chronological story. Each paragraph is one full scene: 3-5 short sentences with setting detail, a soft sense (color/sound/smell/touch), an action, and a feeling. About 25-40 words per paragraph. Total story about 250-350 words. Every sentence ends with . or !. Last paragraph is a cozy bedtime close.",
        .count(10)
    )
    var paragraphs: [String]
}

@available(iOS 26.0, *)
extension GenerableKidsStory {
    func toStoryPlan(input: StoryDraftInput, character: CharacterProfile) throws -> StoryPlan {
        var texts = paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Allow 8–12 from model; repair will pad/trim to 10.
        guard texts.count >= 6 else {
            throw StoryPlanningError.failed
        }
        if texts.count > 12 {
            texts = Array(texts.prefix(12))
        }

        let tags = StorySceneTags.ordered
        let soft = input.ageBand == .threeToFive
        let narration: String
        switch input.language {
        case .portugueseBrazil: narration = soft ? "lento e carinhoso" : "calmo e expressivo"
        case .englishUS: narration = soft ? "slow and caring" : "calm and expressive"
        case .spanishSpain: narration = soft ? "lento y cariñoso" : "calmo y expresivo"
        }

        let pages: [StoryPlanPage] = texts.enumerated().map { index, text in
            let tag = index < tags.count ? tags[index] : tags[tags.count - 1]
            let imagePrompt = ScenePromptBuilder.prompt(
                pageText: text,
                sceneTag: tag,
                character: character,
                setting: input.trimmedSetting,
                artStyle: input.artStyle,
                language: input.language,
                pageIndex: index,
                totalPages: texts.count
            )
            return StoryPlanPage(
                index: index,
                text: text,
                imagePrompt: imagePrompt,
                narrationHint: narration,
                sceneTag: tag
            )
        }

        // Do not hard-fail on word count — StoryDraftRepair fits the band.
        return StoryPlan(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            character: character,
            setting: input.trimmedSetting,
            lesson: input.trimmedLesson,
            ageBand: input.ageBand,
            artStyle: input.artStyle,
            pages: pages
        )
    }
}
#endif
