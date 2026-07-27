import XCTest
@testable import StoryPromptKit
import VovoUI

final class StoryPromptKitTests: XCTestCase {
    func testWordCountBounds() {
        let short = StorySeedPrompt(text: "one two three")
        XCTAssertEqual(short.wordCount, 3)
        XCTAssertFalse(short.isValid)

        let ok = StorySeedPrompt(
            text: "a cozy forest friend helps a lost star find home at night"
        )
        XCTAssertEqual(ok.wordCount, 12)
        XCTAssertTrue(ok.isValid)

        let long = StorySeedPrompt(
            text: "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone"
        )
        XCTAssertGreaterThan(long.wordCount, StorySeedPrompt.maxWords)
        XCTAssertFalse(long.isValid)
    }

    func testOfflineGeneratorProducesTenScenes() async throws {
        let seed = StorySeedPrompt(
            text: "a little rabbit finds a glowing pebble under the moon and smiles",
            language: .englishUS
        )
        XCTAssertTrue(seed.isValid)
        let draft = try await OfflineStoryFromPromptGenerator().generate(from: seed)
        XCTAssertEqual(draft.paragraphs.count, 10)
        XCTAssertEqual(draft.language, .englishUS)
        XCTAssertFalse(draft.title.isEmpty)
        XCTAssertTrue(draft.fullText.localizedCaseInsensitiveContains("pebble")
            || draft.summary.localizedCaseInsensitiveContains("rabbit")
            || draft.seedPrompt.localizedCaseInsensitiveContains("rabbit"))
    }

    func testGeneratorRejectsShortPrompt() async {
        let seed = StorySeedPrompt(text: "too short", language: .englishUS)
        do {
            _ = try await OfflineStoryFromPromptGenerator().generate(from: seed)
            XCTFail("expected validation error")
        } catch let e as StorySeedPrompt.ValidationError {
            if case .tooShort = e { /* ok */ } else { XCTFail("\(e)") }
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testOfflineGeneratorAllThreeLanguages() async throws {
        // Deterministic variant selection (index 0) so copy assertions are stable.
        let generator = OfflineStoryFromPromptGenerator(pickVariant: { _ in 0 })
        let cases: [(AppLanguage, String, String)] = [
            (
                .englishUS,
                "a little rabbit finds a glowing pebble under the soft moon light",
                "gentle bedtime"
            ),
            (
                .portugueseBrazil,
                "um coelhinho acha um seixo brilhante sob a lua macia e sorri",
                "história suave"
            ),
            (
                .spanishSpain,
                "un conejito halla un guijarro brillante bajo la luna suave y sonríe",
                "cuento suave"
            )
        ]

        for (lang, text, summaryMarker) in cases {
            let seed = StorySeedPrompt(text: text, language: lang)
            XCTAssertTrue(seed.isValid, "seed should be valid for \(lang.rawValue)")
            let draft = try await generator.generate(from: seed)
            XCTAssertEqual(draft.paragraphs.count, 10, lang.rawValue)
            XCTAssertEqual(draft.language, lang)
            XCTAssertTrue(
                draft.summary.localizedCaseInsensitiveContains(summaryMarker),
                "summary should be localized for \(lang.rawValue): \(draft.summary)"
            )
            XCTAssertFalse(draft.title.isEmpty, lang.rawValue)
            // Scene text should not be English-only when PT/ES is selected.
            switch lang {
            case .englishUS:
                XCTAssertTrue(draft.paragraphs[0].contains("Evening light"))
            case .portugueseBrazil:
                XCTAssertTrue(draft.paragraphs[0].localizedCaseInsensitiveContains("luz"))
            case .spanishSpain:
                XCTAssertTrue(draft.paragraphs[0].localizedCaseInsensitiveContains("luz"))
            }
        }
    }

    func testVovoL10nCoversStoryKeysInAllLanguages() {
        let keys: [VovoL10n.Key] = [
            .language, .storySeedTitle, .storyCreate, .storyGenerateFailed, .storySeedPlaceholder
        ]
        for lang in AppLanguage.allCases {
            for key in keys {
                let s = VovoL10n.t(key, lang)
                XCTAssertFalse(s.isEmpty, "\(key) \(lang)")
                XCTAssertNotEqual(s, key.rawValue, "missing translation \(key) \(lang)")
            }
            XCTAssertEqual(VovoL10n.scene(1, lang: lang).contains("1"), true)
        }
        XCTAssertEqual(VovoL10n.t(.storyCreate, .portugueseBrazil), "Criar história")
        XCTAssertEqual(VovoL10n.t(.storyCreate, .englishUS), "Create story")
        XCTAssertEqual(VovoL10n.t(.storyCreate, .spanishSpain), "Crear cuento")
    }

    func testAppLanguageResolve() {
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "pt-BR"), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "en-US"), .englishUS)
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "es-ES"), .spanishSpain)
        XCTAssertEqual(AppLanguage.allCases.count, 3)
    }

    func testMarkdownCatalogParsesSectionsAndPlaceholders() {
        let md = """
        # Title

        ## greeting
        Hello {{name}}!

        ## scene1
        First paragraph.
        """
        let sections = MarkdownTextCatalog.parseSections(md)
        XCTAssertEqual(sections["greeting"], "Hello {{name}}!")
        XCTAssertEqual(sections["scene1"], "First paragraph.")
        XCTAssertEqual(
            MarkdownTextCatalog.render(sections["greeting"]!, vars: ["name": "Ada"]),
            "Hello Ada!"
        )
    }

    func testMarkdownResourcesLoadFromDisk() {
        XCTAssertEqual(VovoL10n.t(.storyCreate, .englishUS), "Create story")
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/StoryPromptKit/Resources")
        let raw = MarkdownTextCatalog.loadFile(
            "Prompts/offline.en-US.md",
            bundle: .module,
            sourceFallbackRoot: root
        )
        XCTAssertFalse(raw.isEmpty, "offline generation prompt should load")
        XCTAssertTrue(raw.contains("[INSERT STORY DESCRIPTION HERE]"))
    }

    func testGenerationPromptReplacesDescriptionPlaceholdersInAllLanguages() {
        let cases: [(AppLanguage, String)] = [
            (.englishUS, "a little rabbit finds a glowing pebble under the soft moon"),
            (.portugueseBrazil, "um coelhinho acha um seixo brilhante sob a lua macia"),
            (.spanishSpain, "un conejito halla un guijarro brillante bajo la luna suave")
        ]
        for (lang, description) in cases {
            let filled = OfflineStoryFromPromptGenerator.filledGenerationPrompt(
                description: description,
                language: lang
            )
            XCTAssertFalse(filled.isEmpty, lang.rawValue)
            XCTAssertFalse(
                OfflineStoryFromPromptGenerator.containsUnresolvedDescriptionPlaceholder(filled),
                "unresolved placeholder in \(lang.rawValue): \(filled.prefix(200))"
            )
            XCTAssertTrue(
                filled.contains(description),
                "filled prompt should include the story description for \(lang.rawValue)"
            )
        }
    }

    // Regression: the offline story must weave the full seed text in exactly ONCE (the spark
    // paragraph). Individual extracted elements may appear in several paragraphs (that's the
    // point of the seed analysis), but the parent's typed text as a whole is never pasted twice.
    func testOfflineFullSeedAppearsExactlyOnce() async throws {
        let marker = "glowingpebblexyz" // unlikely to occur naturally; used verbatim
        let seedText = "a little rabbit finds a \(marker) under the soft moon light"
        let seed = StorySeedPrompt(text: seedText, language: .englishUS)
        let draft = try await OfflineStoryFromPromptGenerator(pickVariant: { _ in 0 }).generate(from: seed)

        let fullSeedOccurrences = draft.paragraphs.reduce(0) { $0 + ($1.contains(seedText) ? 1 : 0) }
        XCTAssertEqual(fullSeedOccurrences, 1, "full seed should be woven in once, not repeated")
        XCTAssertEqual(draft.paragraphs.first?.contains(seedText), true, "seed should open the story")

        let markerOccurrences = draft.paragraphs.reduce(0) { $0 + ($1.contains(marker) ? 1 : 0) }
        XCTAssertGreaterThanOrEqual(markerOccurrences, 1, "the seed's key element should appear")
    }

    // The seed is *analyzed*: extracted key elements are woven through the story, not just the
    // opening. With variant index 1 several beats reference the third element (the marker).
    func testOfflineSeedElementsAreWovenThroughStory() async throws {
        let marker = "glowingpebblexyz"
        let seed = StorySeedPrompt(
            text: "a little rabbit finds a \(marker) under the soft moon light",
            language: .englishUS
        )
        let draft = try await OfflineStoryFromPromptGenerator(pickVariant: { _ in 1 }).generate(from: seed)
        let markerOccurrences = draft.paragraphs.reduce(0) { $0 + ($1.contains(marker) ? 1 : 0) }
        XCTAssertGreaterThanOrEqual(
            markerOccurrences, 2,
            "key elements should be woven beyond the opening paragraph; got \(markerOccurrences)"
        )
        // "rabbit" (element 1) should also appear beyond the spark paragraph.
        let rabbitOccurrences = draft.paragraphs.dropFirst().reduce(0) {
            $0 + ($1.localizedCaseInsensitiveContains("rabbit") ? 1 : 0)
        }
        XCTAssertGreaterThanOrEqual(rabbitOccurrences, 1)
    }

    // Key-element extraction filters stopwords and common verbs, keeping original order/casing,
    // and pads with localized generics when the seed has fewer than 3 content words.
    func testKeyElementsExtraction() {
        XCTAssertEqual(
            OfflineStoryFromPromptGenerator.keyElements(
                from: "a little rabbit finds a glowing pebble under the soft moon light",
                language: .englishUS
            ),
            ["little", "rabbit", "glowing"]
        )
        XCTAssertEqual(
            OfflineStoryFromPromptGenerator.keyElements(
                from: "the and of in on at to for by with",
                language: .englishUS
            ),
            ["a little friend", "a quiet place", "a small wish"]
        )
    }

    // Regression: the same seed must NOT produce the same story every time (randomized
    // variant selection). Retry a few times so a chance collision can't flake the test.
    func testOfflineSameSeedDoesNotRepeatStory() async throws {
        let seed = StorySeedPrompt(
            text: "a little rabbit finds a glowing pebble under the soft moon light",
            language: .englishUS
        )
        let generator = OfflineStoryFromPromptGenerator()
        var stories: Set<[String]> = []
        for _ in 0..<4 {
            stories.insert(try await generator.generate(from: seed).paragraphs)
        }
        XCTAssertGreaterThan(stories.count, 1, "same seed should vary across generations")
    }

    // Injected variant selection makes generation fully deterministic (used by other tests).
    func testOfflineInjectedPickIsDeterministic() async throws {
        let seed = StorySeedPrompt(
            text: "a little rabbit finds a glowing pebble under the soft moon light",
            language: .englishUS
        )
        let a = try await OfflineStoryFromPromptGenerator(pickVariant: { _ in 0 }).generate(from: seed)
        let b = try await OfflineStoryFromPromptGenerator(pickVariant: { _ in 0 }).generate(from: seed)
        XCTAssertEqual(a.title, b.title)
        XCTAssertEqual(a.summary, b.summary)
        XCTAssertEqual(a.paragraphs, b.paragraphs)

        let c = try await OfflineStoryFromPromptGenerator(pickVariant: { _ in 1 }).generate(from: seed)
        XCTAssertNotEqual(a.paragraphs, c.paragraphs, "different variant picks should differ")
    }

    // Regression: different seeds must produce different offline stories (no fixed boilerplate
    // that ignores the seed).
    func testOfflineDifferentSeedsProduceDifferentStories() async throws {
        let a = try await OfflineStoryFromPromptGenerator().generate(from: StorySeedPrompt(
            text: "a brave little boat sails across a calm silver lake", language: .englishUS
        ))
        let b = try await OfflineStoryFromPromptGenerator().generate(from: StorySeedPrompt(
            text: "a sleepy bear finds a glowing star in winter forest", language: .englishUS
        ))
        XCTAssertNotEqual(a.paragraphs, b.paragraphs, "different seeds should yield different stories")
        XCTAssertTrue(a.fullText.contains("boat"))
        XCTAssertTrue(b.fullText.contains("bear"))
    }
}
