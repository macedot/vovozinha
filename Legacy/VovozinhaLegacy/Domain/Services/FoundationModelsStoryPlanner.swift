import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

private let plannerLog = Logger(subsystem: "app.vovozinha", category: "StoryPlanner")

/// On-device LLM: **one** generation call → title, summary, exactly 10 scene paragraphs.
/// Each paragraph becomes one book page; images follow that page’s scene text.
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
        let maxAttempts = min(FeatureFlags.kidsFilterMaxAttempts, 6)

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()

            let temperature = max(0.4, 0.7 - Double(attempt - 1) * 0.05)
            let options = GenerationOptions(temperature: temperature, maximumResponseTokens: 2048)
            let retrySuffix = previousHint.isEmpty
                ? ""
                : "\n\nRETRY \(attempt): \(previousHint)"

            let session = LanguageModelSession(model: model, instructions: instructions)

            do {
                // Single respond call — full story in one structured output.
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

                if safety.isEmpty, !structure.isEmpty {
                    plan = StoryDraftRepair.repair(plan, language: input.language)
                    if KidsSafetyFilter.canShip(plan) {
                        return plan
                    }
                }

                if !safety.isEmpty {
                    previousHint =
                        "Unsafe content (\(safety.joined(separator: ", "))). Rewrite a fully gentle bedtime story. Exactly 10 scene paragraphs in the fixed scene order. No scary or adult words."
                    lastError = .unsafeContent
                } else {
                    previousHint =
                        "Structure off (\(structure.prefix(4).joined(separator: ", "))). Exactly 10 paragraphs for the 10 scenes; ~\(FeatureFlags.targetStoryWordCount) words total; 3–5 sentences per scene with place detail; do not restate the hero's full appearance every page."
                    lastError = .failed
                }
                continue
            } catch is CancellationError {
                throw CancellationError()
            } catch let planning as StoryPlanningError {
                if case .llmUnavailable = planning { throw planning }
                previousHint =
                    "Return exactly 10 safe scene paragraphs for the fixed arc, one continuous story, ~\(FeatureFlags.targetStoryWordCount) words total."
                lastError = planning
                continue
            } catch {
                let mapped = Self.mapGenerationError(error)
                if case .llmUnavailable = mapped { throw mapped }
                previousHint =
                    "Write one cozy bedtime story as exactly 10 scene paragraphs (setup through bedtime)."
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
        return PromptCatalog.text(
            "story/system_instructions.txt",
            vars: [
                "langName": langName,
                "sceneList": StorySceneTags.promptSceneList,
                "target": "\(FeatureFlags.targetStoryWordCount)",
                "minW": "\(FeatureFlags.minStoryWordCount)",
                "maxW": "\(FeatureFlags.maxStoryWordCount)"
            ]
        )
    }

    static func userPrompt(input: StoryDraftInput, character: CharacterProfile) -> String {
        let seed = Int.random(in: 1000...999_999)
        let idea = input.trimmedStoryIdea.isEmpty ? "(gentle original plot)" : input.trimmedStoryIdea
        let heroName = character.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let look = character.lockedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        return PromptCatalog.text(
            "story/user_prompt.txt",
            vars: [
                "seed": "\(seed)",
                "languageCode": input.language.rawValue,
                "ageBand": input.ageBand.rawValue,
                "ageHint": input.ageBand.generationHint(input.language),
                "setting": input.trimmedSetting,
                "lesson": input.trimmedLesson,
                "idea": idea,
                "heroName": heroName.isEmpty ? "the little hero" : heroName,
                "heroLook": look.isEmpty ? "cute gentle kids character" : look,
                "target": "\(FeatureFlags.targetStoryWordCount)",
                "sceneTagsJoined": StorySceneTags.ordered.joined(separator: " / ")
            ]
        )
    }

    /// Density shape only (not a content template). Used in tests.
    static func paragraphExample(language: AppLanguage, hero: String) -> String {
        let name = hero.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = name.isEmpty ? "Luma" : name
        let file: String
        switch language {
        case .portugueseBrazil: file = "story/paragraph_example.pt-BR.txt"
        case .englishUS: file = "story/paragraph_example.en-US.txt"
        case .spanishSpain: file = "story/paragraph_example.es-ES.txt"
        }
        return PromptCatalog.text(file, vars: ["hero": h])
    }
}

// MARK: - Guided generation (single structured response)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "One bedtime story: title, summary, and exactly 10 scene paragraphs in fixed order")
struct GenerableKidsStory {
    @Guide(description: "Short kid-safe title")
    var title: String

    @Guide(description: "One or two gentle sentences summarizing the whole plot")
    var summary: String

    @Guide(
        description: """
        Exactly 10 paragraphs of ONE continuous story. Index maps to scenes in order: \
        0 setup, 1 explore, 2 inciting, 3 feel, 4 plan, 5 try, 6 help, 7 turn, 8 lesson, 9 bedtime. \
        Each paragraph is that scene only (3-5 sentences, setting + sense + action + feeling). \
        Hero name for actions; do not restate full appearance every paragraph. \
        Last paragraph is cozy bedtime. Total about 250-350 words.
        """,
        .count(10)
    )
    var paragraphs: [String]
}

@available(iOS 26.0, *)
extension GenerableKidsStory {
    /// Extract each paragraph into a page; sceneTag from ordered beats; image follows scene text.
    func toStoryPlan(input: StoryDraftInput, character: CharacterProfile) throws -> StoryPlan {
        var texts = paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard texts.count >= 6 else {
            throw StoryPlanningError.failed
        }
        if texts.count > 12 {
            texts = Array(texts.prefix(12))
        }

        let soft = input.ageBand == .threeToFive
        let narration: String
        switch input.language {
        case .portugueseBrazil: narration = soft ? "lento e carinhoso" : "calmo e expressivo"
        case .englishUS: narration = soft ? "slow and caring" : "calm and expressive"
        case .spanishSpain: narration = soft ? "lento y cariñoso" : "calmo y expresivo"
        }

        let pages: [StoryPlanPage] = texts.enumerated().map { index, text in
            let tag = StorySceneTags.tag(at: index)
            // Image prompt from THIS scene paragraph (hero lock only for art identity).
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
