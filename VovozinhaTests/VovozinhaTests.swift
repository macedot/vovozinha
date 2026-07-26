import XCTest
@testable import Vovozinha

final class VovozinhaTests: XCTestCase {
    func testLanguagePinnedCodes() {
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "pt-BR"), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "en-US"), .englishUS)
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "es-ES"), .spanishSpain)
    }

    func testLaunchTabPrefersCreateWhenEmpty() {
        XCTAssertEqual(AppTab.launchTab(hasStories: false), .create)
        XCTAssertEqual(AppTab.launchTab(hasStories: true), .library)
    }

    func testGraphicsPipelineEnabledForSceneArt() {
        XCTAssertTrue(FeatureFlags.graphicsEnabled)
        XCTAssertEqual(FeatureFlags.fixedPageCount, 10)
    }

    @MainActor
    func testProceduralIllustratorProducesImage() async throws {
        let character = CharacterProfile.fromManual(
            name: "Luma",
            description: "soft blue bear",
            language: .englishUS
        )
        let page = StoryPlanPage(
            index: 0,
            text: "Luma walks in a green forest. Birds sing. Soft light shines.",
            imagePrompt: "forest kids book",
            narrationHint: "calm",
            sceneTag: "explore"
        )
        let plan = StoryPlan(
            title: "Forest night",
            summary: "A walk",
            character: character,
            setting: "Enchanted forest",
            lesson: "kindness",
            ageBand: .threeToFive,
            artStyle: .pastel,
            pages: [page]
        )
        let brief = ScenePromptBuilder.brief(
            pageText: page.text,
            sceneTag: page.sceneTag,
            character: character,
            setting: plan.setting,
            artStyle: .pastel,
            language: .englishUS,
            pageIndex: 0,
            totalPages: 10
        )
        let request = IllustrationRequest(
            page: page,
            plan: plan,
            referencePhoto: nil,
            previousPageImage: nil,
            heroReferenceImage: nil,
            storySeed: 42,
            pageSeed: 42,
            continuityStrength: 0,
            brief: brief
        )
        let image = try await ProceduralKidsIllustrator().illustrate(request)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertTrue(brief.positivePrompt.localizedCaseInsensitiveContains("luma")
            || brief.positivePrompt.localizedCaseInsensitiveContains("bear"))
        // Page paragraph drives the prompt (front-loaded for CLIP).
        XCTAssertTrue(brief.positivePrompt.localizedCaseInsensitiveContains("NEW SCENE")
            || brief.positivePrompt.localizedCaseInsensitiveContains("PAGE"))
        XCTAssertTrue(
            brief.sceneDescription.localizedCaseInsensitiveContains("forest")
                || brief.sceneDescription.localizedCaseInsensitiveContains("walks")
                || brief.sceneDescription.localizedCaseInsensitiveContains("bird")
        )
        XCTAssertTrue(brief.positivePrompt.localizedCaseInsensitiveContains("forest")
            || brief.positivePrompt.localizedCaseInsensitiveContains("walks")
            || brief.positivePrompt.localizedCaseInsensitiveContains("bird"))
        // Scene text must appear before the long character lock (otherwise pages clone).
        if let sceneRange = brief.positivePrompt.range(of: "walks", options: .caseInsensitive)
            ?? brief.positivePrompt.range(of: "forest", options: .caseInsensitive),
           let lockRange = brief.positivePrompt.range(of: "LOCKED CHARACTER", options: .caseInsensitive) {
            XCTAssertLessThan(sceneRange.lowerBound, lockRange.lowerBound)
        }
        XCTAssertFalse(brief.negativePrompt.isEmpty)
    }

    func testSceneBriefLocksHeroAcrossPages() {
        let character = CharacterProfile.fromManual(
            name: "Ted",
            description: "blue teddy with red scarf",
            language: .englishUS
        )
        var memory = StoryArtMemory.seed(
            character: character,
            setting: "forest",
            artStyle: .watercolor
        )
        let e0 = ScenePromptBuilder.brief(
            pageText: "Ted wakes up in a cozy den.",
            sceneTag: "setup",
            character: character,
            setting: "forest",
            artStyle: .watercolor,
            language: .englishUS,
            pageIndex: 0,
            totalPages: 10,
            memory: memory
        )
        memory = e0.memory
        let establish = e0.brief

        let e1 = ScenePromptBuilder.brief(
            pageText: "Ted walks in the forest.",
            sceneTag: "explore",
            character: character,
            setting: "forest",
            artStyle: .watercolor,
            language: .englishUS,
            pageIndex: 1,
            totalPages: 10,
            memory: memory
        )
        memory = e1.memory
        let a = e1.brief

        let e2 = ScenePromptBuilder.brief(
            pageText: "Ted helps a bird at night.",
            sceneTag: "help",
            character: character,
            setting: "forest",
            artStyle: .watercolor,
            language: .englishUS,
            pageIndex: 6,
            totalPages: 10,
            memory: memory
        )
        let b = e2.brief
        memory = e2.memory

        // Same actor visual every page.
        XCTAssertEqual(establish.heroLock, a.heroLock)
        XCTAssertEqual(a.heroLock, b.heroLock)
        XCTAssertTrue(establish.isEstablishShot)
        XCTAssertFalse(a.isEstablishShot)

        // Custom section prompts differ by beat.
        XCTAssertTrue(establish.sectionPrompt.localizedCaseInsensitiveContains("setup"))
        XCTAssertTrue(a.sectionPrompt.localizedCaseInsensitiveContains("explore"))
        XCTAssertTrue(b.sectionPrompt.localizedCaseInsensitiveContains("help"))
        XCTAssertNotEqual(establish.sectionPrompt, a.sectionPrompt)
        XCTAssertNotEqual(a.sectionPrompt, b.sectionPrompt)

        // Page text still embedded and distinct per page.
        XCTAssertTrue(a.positivePrompt.localizedCaseInsensitiveContains("NEW SCENE")
            || a.positivePrompt.localizedCaseInsensitiveContains("PAGE"))
        XCTAssertTrue(a.sceneDescription.localizedCaseInsensitiveContains("walks")
            || a.sceneDescription.localizedCaseInsensitiveContains("forest"))
        XCTAssertTrue(b.sceneDescription.localizedCaseInsensitiveContains("bird")
            || b.sceneDescription.localizedCaseInsensitiveContains("helps"))
        XCTAssertTrue(b.positivePrompt.localizedCaseInsensitiveContains("bird")
            || b.positivePrompt.localizedCaseInsensitiveContains("helps"))
        XCTAssertNotEqual(a.positivePrompt, b.positivePrompt)
        XCTAssertNotEqual(a.sceneDescription, b.sceneDescription)

        // Bird introduced on help page stays locked in memory afterward.
        XCTAssertTrue(memory.lockedElements.contains(where: { $0.localizedCaseInsensitiveContains("bird") }))
        XCTAssertTrue(b.continuityLock.localizedCaseInsensitiveContains("LOCKED CHARACTER")
            || b.positivePrompt.localizedCaseInsensitiveContains("LOCKED CHARACTER"))
        // Explore page should not force "show every locked prop" — only scene-relevant props.
        XCTAssertFalse(a.positivePrompt.localizedCaseInsensitiveContains("LOCKED STORY ELEMENTS"))
    }

    func testSectionPromptsCoverAllStoryBeats() {
        for tag in StorySceneTags.ordered {
            let s = ScenePromptBuilder.sectionPrompt(beat: tag, pageIndex: 0, totalPages: 10)
            XCTAssertFalse(s.isEmpty, "missing section prompt for \(tag)")
            XCTAssertTrue(s.localizedCaseInsensitiveContains("SECTION")
                || s.localizedCaseInsensitiveContains(tag))
        }
    }

    func testAppearanceMapsToEnglishVisualTags() {
        let pt = CharacterProfile.visualAppearanceEnglish("urso azul fofo com cachecol vermelho")
        XCTAssertTrue(pt.localizedCaseInsensitiveContains("bear") || pt.localizedCaseInsensitiveContains("blue"))
        XCTAssertTrue(pt.localizedCaseInsensitiveContains("scarf") || pt.localizedCaseInsensitiveContains("red"))
    }

    func testImagePackCopyIsParentFriendly() {
        for lang in AppLanguage.allCases {
            let missing = ImagePackStore.statusSummary(lang: lang)
            XCTAssertFalse(missing.localizedCaseInsensitiveContains("VAEEncoder"))
            XCTAssertFalse(missing.localizedCaseInsensitiveContains("img2img"))
            XCTAssertFalse(missing.localizedCaseInsensitiveContains("Anything V5"))
            XCTAssertFalse(missing.localizedCaseInsensitiveContains("Core ML"))

            let title = L10n.t(.settingsImagePack, lang)
            let cta = L10n.t(.settingsImagePackDownload, lang)
            let intro = L10n.t(.settingsImagePackIntro, lang)
            XCTAssertFalse(title.isEmpty)
            XCTAssertFalse(cta.isEmpty)
            XCTAssertFalse(intro.isEmpty)
            XCTAssertFalse(title.localizedCaseInsensitiveContains("Core ML"))
            XCTAssertFalse(cta.localizedCaseInsensitiveContains("Core ML"))
            XCTAssertFalse(L10n.t(.settingsImagePackPhaseExtracting, lang).isEmpty)
        }
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

    func testSimulatorUnlocksAllResources() {
        // Even a weak OS + A16-class sim identity still unlocks every resource for development.
        let sim = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            chipClass: .a16,
            isSimulator: true,
            localLLMPackInstalled: false,
            localImagePackInstalled: false
        )
        XCTAssertTrue(sim.isSimulator)
        XCTAssertTrue(sim.appleIntelligenceLikely)
        XCTAssertTrue(sim.localLLMPackInstalled)
        XCTAssertTrue(sim.localImagePackInstalled)
        XCTAssertTrue(sim.canGenerateStories)
        XCTAssertEqual(sim.preferredStoryPlannerKind, .foundationModels)
        for feature in AppFeature.userVisible {
            XCTAssertTrue(
                sim.isEnabled(feature),
                "Simulator should enable \(feature.rawValue)"
            )
        }
    }

    func testSimulatorCanGenerateStoriesEvenWithoutPackFlags() {
        let sim = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            chipClass: .unknown,
            isSimulator: true
        )
        XCTAssertTrue(sim.canGenerateStories)
        XCTAssertEqual(sim.preferredStoryPlannerKind, .foundationModels)
    }

    func testSimulatorDevPlannerBuildsShipableStory() async throws {
        let input = StoryDraftInput.randomized(
            actorDescription: "Alice is a very smart little girl",
            photoData: nil,
            language: .englishUS
        )
        let character = CharacterProfile.fromManual(
            name: "Alice",
            description: "a very smart little girl",
            language: .englishUS
        )
        let plan = try await SimulatorDevStoryPlanner().plan(input: input, character: character)
        XCTAssertEqual(plan.pages.count, 10)
        XCTAssertTrue(plan.pages[0].text.localizedCaseInsensitiveContains("Alice"))
        XCTAssertTrue(KidsSafetyFilter.safetyIssues(plan: plan).isEmpty)
        // Pages must differ (not a single repeated blob).
        XCTAssertNotEqual(plan.pages[0].text, plan.pages[5].text)
    }

    func testSimulatorAwareNeverSurfacesLLMUnavailable() async throws {
        // Always succeeds on sim path (FM optional; dev builder is guaranteed).
        let input = StoryDraftInput.randomized(
            actorDescription: "Ted the blue teddy",
            photoData: nil,
            language: .englishUS
        )
        let character = CharacterProfile.fromManual(
            name: "Ted",
            description: "blue teddy with red scarf",
            language: .englishUS
        )
        do {
            let plan = try await SimulatorAwareStoryPlanner().plan(input: input, character: character)
            XCTAssertEqual(plan.pages.count, 10)
            XCTAssertFalse(plan.pages[0].text.isEmpty)
        } catch let err as StoryPlanningError {
            XCTAssertNotEqual(err, .llmUnavailable, "Simulator must never surface llmUnavailable")
            XCTFail("Unexpected planning error on simulator path: \(err)")
        }
    }

    func testPlannerKindOnSimulatorIsDev() {
        let sim = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            chipClass: .a16,
            isSimulator: true
        )
        // When tests run in the Simulator test host, compile-time gate forces .simulatorDev.
        // When they run on device host (rare), profile.isSimulator still maps to .simulatorDev
        // via runtime branch on device builds — either way must not be .unavailable.
        let kind = StoryGenerationService.plannerKind(for: sim)
        XCTAssertNotEqual(kind, .unavailable)
        #if targetEnvironment(simulator)
        XCTAssertEqual(kind, .simulatorDev)
        #endif
    }

    func testUserFacingErrorHidesLLMUnavailableWhenDevFallback() {
        let ptLLM = StoryPlanningError.llmUnavailable.localizedDescription(for: .portugueseBrazil)
        XCTAssertTrue(ptLLM.localizedCaseInsensitiveContains("LLM"))

        let hidden = StoryPlanningError.displayMessage(
            for: StoryPlanningError.llmUnavailable,
            language: .portugueseBrazil,
            allowsDevFallback: true
        )
        XCTAssertFalse(
            hidden.localizedCaseInsensitiveContains("LLM no aparelho indisponível"),
            "Dev fallback UI must not show the product LLM-unavailable string"
        )
        XCTAssertEqual(
            hidden,
            StoryPlanningError.failed.localizedDescription(for: .portugueseBrazil)
        )

        let deviceMsg = StoryPlanningError.displayMessage(
            for: StoryPlanningError.llmUnavailable,
            language: .portugueseBrazil,
            allowsDevFallback: false
        )
        XCTAssertTrue(deviceMsg.localizedCaseInsensitiveContains("LLM"))
    }

    func testPlannerKindIsDevWhenAllowsDevFallback() {
        // In DEBUG / Simulator / Mac test hosts, allowsDevStoryFallback is true.
        XCTAssertTrue(
            DeviceProfile.allowsDevStoryFallback,
            "Test host should allow offline dev stories"
        )
        let deviceShaped = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            chipClass: .a16,
            isSimulator: false
        )
        XCTAssertEqual(StoryGenerationService.plannerKind(for: deviceShaped), .simulatorDev)
    }

    func testAllowsDevStoryFallbackCoversMacAndDebug() {
        // Runtime flag must be true on this test host (sim or DEBUG).
        XCTAssertTrue(DeviceProfile.allowsDevStoryFallback)
        XCTAssertTrue(DeviceProfile.current.canGenerateStories)
    }

    func testSimulatorDevPlannerNotFixedLibrary() async throws {
        let alice = try await SimulatorDevStoryPlanner().plan(
            input: StoryDraftInput.randomized(
                actorDescription: "Alice is a clever girl",
                photoData: nil,
                language: .englishUS
            ),
            character: CharacterProfile.fromManual(
                name: "Alice",
                description: "clever girl",
                language: .englishUS
            )
        )
        let ted = try await SimulatorDevStoryPlanner().plan(
            input: StoryDraftInput.randomized(
                actorDescription: "Ted is a blue teddy",
                photoData: nil,
                language: .englishUS
            ),
            character: CharacterProfile.fromManual(
                name: "Ted",
                description: "blue teddy",
                language: .englishUS
            )
        )
        XCTAssertTrue(alice.title.localizedCaseInsensitiveContains("Alice"))
        XCTAssertTrue(ted.title.localizedCaseInsensitiveContains("Ted"))
        XCTAssertNotEqual(alice.pages[0].text, ted.pages[0].text)
    }

    @MainActor
    func testSimMakeDefaultPlanningNeverThrowsLLMUnavailable() async throws {
        let profile = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            chipClass: .a16,
            isSimulator: true
        )
        XCTAssertNotEqual(StoryGenerationService.plannerKind(for: profile), .unavailable)

        let input = StoryDraftInput.randomized(
            actorDescription: "Luma soft bear",
            photoData: nil,
            language: .englishUS
        )
        let character = CharacterProfile.fromManual(
            name: "Luma",
            description: "soft bear",
            language: .englishUS
        )
        // Same planner makeDefault wires on sim builds.
        let plan = try await SimulatorDevStoryPlanner().plan(input: input, character: character)
        XCTAssertEqual(plan.pages.count, 10)
    }

    func testPhysicalA16StillBlockedForFoundationModelsHardware() {
        let device = DeviceProfile.make(
            os: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            chipClass: .a16,
            isSimulator: false
        )
        XCTAssertFalse(device.appleIntelligenceLikely)
        if case .unavailableHardware = device.availability(for: .foundationModelsStory, lang: .englishUS) {
            // expected
        } else {
            XCTFail("Physical A16 should still be hardware-gated for FM")
        }
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

    func testPromptCatalogLoadsStoryAndArtTemplates() {
        let system = PromptCatalog.text("story/system_instructions.txt", vars: [
            "langName": "English",
            "sceneList": "1) setup",
            "target": "280",
            "minW": "150",
            "maxW": "480"
        ])
        XCTAssertFalse(system.isEmpty)
        XCTAssertTrue(system.localizedCaseInsensitiveContains("bedtime"))
        let neg = PromptCatalog.text("art/negative.txt")
        XCTAssertTrue(neg.localizedCaseInsensitiveContains("lowres"))
        let section = PromptCatalog.text("art/section.setup.txt")
        XCTAssertTrue(section.localizedCaseInsensitiveContains("setup"))
    }

    func testStoryPromptIsSingleShotSceneParagraphs() {
        let character = CharacterProfile.fromManual(
            name: "Alice",
            description: "clever girl with a blue coat",
            language: .englishUS
        )
        let input = StoryDraftInput.randomized(
            actorDescription: "Alice clever girl",
            photoData: nil,
            language: .englishUS
        )
        let system = FoundationModelsStoryPlanner.systemInstructions(language: .englishUS)
        let user = FoundationModelsStoryPlanner.userPrompt(input: input, character: character)

        // Named scene order in the single prompt.
        for tag in StorySceneTags.ordered {
            XCTAssertTrue(
                system.localizedCaseInsensitiveContains(tag) || user.localizedCaseInsensitiveContains(tag),
                "Missing scene tag \(tag) in prompts"
            )
        }
        XCTAssertTrue(system.localizedCaseInsensitiveContains("exactly 10"))
        XCTAssertTrue(
            system.localizedCaseInsensitiveContains("do not restate")
                || user.localizedCaseInsensitiveContains("do not")
                || user.localizedCaseInsensitiveContains("identity reference")
        )
        // Appearance is reference, not per-page costume inventory.
        XCTAssertTrue(user.localizedCaseInsensitiveContains("identity"))
    }

    func testDevPlannerPagesMapToOrderedScenes() async throws {
        let plan = try await SimulatorDevStoryPlanner().plan(
            input: StoryDraftInput.randomized(
                actorDescription: "Mira soft rabbit",
                photoData: nil,
                language: .englishUS
            ),
            character: CharacterProfile.fromManual(
                name: "Mira",
                description: "soft rabbit",
                language: .englishUS
            )
        )
        XCTAssertEqual(plan.pages.count, 10)
        for (i, page) in plan.pages.enumerated() {
            XCTAssertEqual(page.sceneTag, StorySceneTags.tag(at: i))
            XCTAssertFalse(page.text.isEmpty)
        }
        // Scene-led: later pages should not all restate a long look string.
        let lookHeavy = plan.pages.filter { $0.text.localizedCaseInsensitiveContains("soft rabbit") }.count
        XCTAssertLessThanOrEqual(lookHeavy, 2)
        XCTAssertNotEqual(plan.pages[1].text, plan.pages[9].text)
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


