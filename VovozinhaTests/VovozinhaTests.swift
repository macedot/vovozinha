import XCTest
@testable import Vovozinha

final class VovozinhaTests: XCTestCase {
    func testLanguagePinnedCodes() {
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "pt-BR"), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "en-US"), .englishUS)
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "es-ES"), .spanishSpain)
    }

    func testGraphicsFlagOffForTextPhase() {
        XCTAssertFalse(FeatureFlags.graphicsEnabled)
        XCTAssertEqual(FeatureFlags.fixedPageCount, 10)
    }

    func testStoryGenerationRequiresLLMNotTemplates() {
        let ios18 = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            chipClass: .a16,
            isSimulator: false
        )
        // No Foundation Models / pack on iOS 18 A16 → cannot generate (no template fallback).
        XCTAssertEqual(ios18.preferredStoryPlannerKind, .none)
        XCTAssertFalse(ios18.canGenerateStories)
    }

    func testFoundationModelsRequiresIOS26AndAIHardware() {
        let ios18Pro = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            chipClass: .a17OrNewer,
            isSimulator: false
        )
        XCTAssertFalse(ios18Pro.isEnabled(.foundationModelsStory))

        let ios26A16 = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            chipClass: .a16,
            isSimulator: false
        )
        XCTAssertFalse(ios26A16.isEnabled(.foundationModelsStory))
    }

    func testUnavailablePlannerThrowsLLMError() async {
        let planner = UnavailableLLMStoryPlanner()
        let input = StoryDraftInput.randomized(
            actorDescription: "blue teddy",
            photoData: nil,
            language: .englishUS
        )
        let character = CharacterProfile.fromManual(name: "Ted", description: "blue teddy")
        do {
            _ = try await planner.plan(input: input, character: character)
            XCTFail("Expected llmUnavailable")
        } catch let error as StoryPlanningError {
            XCTAssertEqual(error, .llmUnavailable)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testNarrativeSceneTagOrder() {
        XCTAssertEqual(StorySceneTags.count, 10)
        XCTAssertEqual(StorySceneTags.ordered.first, "setup")
        XCTAssertEqual(StorySceneTags.ordered.last, "bedtime")
    }

    func testKidsSafetyRequiresTenPagesWithTags() {
        let character = CharacterProfile.fromManual(name: "A", description: "a", language: .englishUS)
        // Golden plan: descriptive scenes (~25+ words each, 3 sentences).
        let texts = [
            "Luma wakes in a soft blue room. Warm morning light paints the walls gold. She smiles and stretches her small paws.",
            "She walks outside into a green forest path. Sweet flowers perfume the gentle air. Birds chirp a happy little song.",
            "A small bird looks sad beside a tilted nest. Brown leaves rustle under Luma's feet. She feels a quiet worry in her chest.",
            "Luma breathes slowly and listens to the wind. Soft moss cools her paws. She wants to help with kindness.",
            "She finds a wide green leaf shining with dew. The leaf smells fresh like rain. Luma makes a careful gentle plan.",
            "She lifts the nest with both careful paws. Sunlight sparkles on the feathers nearby. The bird watches with bright eyes.",
            "A friendly squirrel hurries down with a soft swish. Together they tuck the nest into a safe branch. Warm pride fills Luma's heart.",
            "The bird sings a bright silver song. The forest feels open and friendly again. Soft light dances through the leaves.",
            "Luma learns that kindness makes hard work lighter. Friends can share a quiet brave moment. Her smile feels warm and true.",
            "Night comes with purple sky and cool air. Stars wink above the sleepy trees. Luma curls up and drifts into soft dreams."
        ]
        XCTAssertEqual(texts.count, 10)
        let pages = texts.enumerated().map { i, text in
            StoryPlanPage(
                index: i,
                text: text,
                imagePrompt: "soft kids scene",
                narrationHint: "calm",
                sceneTag: StorySceneTags.ordered[i]
            )
        }
        let plan = StoryPlan(
            title: "A gentle night",
            summary: "Luma helps a bird and learns kindness.",
            character: character,
            setting: "forest",
            lesson: "kindness",
            ageBand: .threeToFive,
            artStyle: .pastel,
            pages: pages
        )
        let issues = KidsSafetyFilter.validate(plan: plan)
        XCTAssertTrue(issues.isEmpty, "Unexpected issues: \(issues)")
        let words = texts.joined(separator: " ").split(whereSeparator: \.isWhitespace).count
        XCTAssertGreaterThanOrEqual(words, FeatureFlags.minStoryWordCount)
        XCTAssertLessThanOrEqual(words, FeatureFlags.maxStoryWordCount)
    }

    func testParagraphExampleIsDescriptive() {
        let ex = FoundationModelsStoryPlanner.paragraphExample(language: .englishUS, hero: "Ted")
        XCTAssertTrue(ex.contains("."))
        XCTAssertTrue(ex.localizedCaseInsensitiveContains("ted"))
        let words = ex.split(whereSeparator: \.isWhitespace).count
        XCTAssertGreaterThanOrEqual(words, 20)
    }

    func testKidsSafetyRejectsUnsafeAndEmpty() {
        let character = CharacterProfile.fromManual(name: "A", description: "a", language: .englishUS)
        let pages = (0..<10).map { i in
            StoryPlanPage(
                index: i,
                text: i == 0 ? "Horror and blood fill the night." : "Safe page. Friends smile. Kind hearts.",
                imagePrompt: "soft",
                narrationHint: "calm",
                sceneTag: StorySceneTags.ordered[i]
            )
        }
        let plan = StoryPlan(
            title: "Bad",
            summary: "x",
            character: character,
            setting: "forest",
            lesson: "kindness",
            ageBand: .threeToFive,
            artStyle: .pastel,
            pages: pages
        )
        let safety = KidsSafetyFilter.safetyIssues(plan: plan)
        XCTAssertFalse(safety.isEmpty)
        XCTAssertTrue(safety.contains { $0.contains("unsafe") })
    }

    func testBlocklistUsesWordBoundaries() {
        XCTAssertTrue(KidsSafetyFilter.isTextSafe("She has skill and kindness."))
        XCTAssertTrue(KidsSafetyFilter.isTextSafe("Es el sexto día de paz."))
        XCTAssertFalse(KidsSafetyFilter.isTextSafe("They kill the monster."))
        XCTAssertFalse(KidsSafetyFilter.isTextSafe("Hay sexo en la historia."))
    }

    func testRepairMakesUnderspecifiedDraftShippable() {
        let character = CharacterProfile.fromManual(
            name: "Luma",
            description: "soft blue bear",
            language: .englishUS
        )
        // Typical FM miss: one unpunctuated sentence per page, uneven length.
        let raw = (0..<10).map { i in
            StoryPlanPage(
                index: i,
                text: "Luma walks into the quiet forest and looks around carefully number \(i)",
                imagePrompt: "soft",
                narrationHint: "calm",
                sceneTag: ""
            )
        }
        let plan = StoryPlan(
            title: "Luma night",
            summary: "A walk",
            character: character,
            setting: "forest",
            lesson: "kindness",
            ageBand: .threeToFive,
            artStyle: .pastel,
            pages: raw
        )
        XCTAssertFalse(KidsSafetyFilter.canShip(plan), "raw should fail structure")
        let repaired = StoryDraftRepair.repair(plan, language: .englishUS)
        let issues = KidsSafetyFilter.validate(plan: repaired)
        XCTAssertTrue(KidsSafetyFilter.canShip(repaired), "repaired should ship: \(issues)")
        XCTAssertEqual(repaired.pages.count, 10)
    }

    func testKidsFilterMaxAttemptsIsPositive() {
        XCTAssertGreaterThanOrEqual(FeatureFlags.kidsFilterMaxAttempts, 2)
    }

    func testMapsContextExceededSystemErrors() {
        let ns = NSError(
            domain: "FoundationModels",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The transcript exceeded the model context size."]
        )
        XCTAssertEqual(StoryPlanningError.from(systemError: ns), .contextExceeded)

        let pt = StoryPlanningError.contextExceeded.localizedDescription(for: .portugueseBrazil)
        XCTAssertFalse(pt.localizedCaseInsensitiveContains("transcript"))
        XCTAssertTrue(pt.localizedCaseInsensitiveContains("espaço") || pt.localizedCaseInsensitiveContains("tente"))
    }

    func testPlanningErrorsNeverExposeEnglishOnPortugueseUI() {
        let cases: [StoryPlanningError] = [.failed, .unsafeContent, .llmUnavailable, .contextExceeded]
        for err in cases {
            let msg = err.localizedDescription(for: .portugueseBrazil)
            XCTAssertFalse(msg.isEmpty)
            // Raw FM phrasing should not leak.
            XCTAssertFalse(msg.localizedCaseInsensitiveContains("transcript"))
            XCTAssertFalse(msg.localizedCaseInsensitiveContains("context window"))
        }
    }

    func testCharacterDefaultsFollowLanguage() {
        let en = CharacterProfile.fromManual(name: "", description: "blue bear", language: .englishUS)
        XCTAssertEqual(en.name, "the hero")
        XCTAssertTrue(en.personality.localizedCaseInsensitiveContains("curious")
            || en.personality.localizedCaseInsensitiveContains("kind"))

        let pt = CharacterProfile.fromManual(name: "", description: "urso azul", language: .portugueseBrazil)
        XCTAssertEqual(pt.name, "o herói")
    }

    func testStoryLanguagePersists() {
        let story = Story(
            title: "T",
            summary: "S",
            characterName: "A",
            characterAppearance: "cute",
            setting: "forest",
            lesson: "kindness",
            ageBand: .threeToFive,
            artStyle: .pastel,
            language: .spanishSpain
        )
        XCTAssertEqual(story.language, .spanishSpain)
        XCTAssertEqual(story.languageRaw, "es-ES")
    }

    func testUserVisibleFeaturesIncludeFoundationModels() {
        XCTAssertTrue(AppFeature.userVisible.contains(.foundationModelsStory))
        XCTAssertFalse(AppFeature.allCases.map(\.rawValue).contains("coreStoryStructured"))
    }
}


