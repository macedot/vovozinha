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

    func testAppLanguageResolve() {
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "pt-BR"), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "en-US"), .englishUS)
        XCTAssertEqual(AppLanguage.resolve(preferenceRaw: "es-ES"), .spanishSpain)
        XCTAssertEqual(AppLanguage.allCases.count, 3)
    }

    func testVovoL10nCoversStoryKeysInAllLanguages() {
        let keys: [VovoL10n.Key] = [
            .language, .storySeedTitle, .storyCreate, .storyGenerateFailed,
            .storyModelNotInstalled, .storySeedPlaceholder
        ]
        for lang in AppLanguage.allCases {
            for key in keys {
                let s = VovoL10n.t(key, lang)
                XCTAssertFalse(s.isEmpty, "\(key) \(lang)")
                XCTAssertNotEqual(s, key.rawValue, "missing translation \(key) \(lang)")
            }
        }
        XCTAssertEqual(VovoL10n.t(.storyCreate, .englishUS), "Create story")
    }

    func testMarkdownCatalogParsesSectionsAndPlaceholders() {
        let md = """
        # Title

        ## greeting
        Hello {{name}}!
        """
        let sections = MarkdownTextCatalog.parseSections(md)
        XCTAssertEqual(sections["greeting"], "Hello {{name}}!")
        XCTAssertEqual(
            MarkdownTextCatalog.render(sections["greeting"]!, vars: ["name": "Ada"]),
            "Hello Ada!"
        )
    }

    func testStoryPromptReplacesDescriptionPlaceholdersInAllLanguages() {
        let cases: [(AppLanguage, String)] = [
            (.englishUS, "a little rabbit finds a glowing pebble under the soft moon"),
            (.portugueseBrazil, "um coelhinho acha um seixo brilhante sob a lua macia"),
            (.spanishSpain, "un conejito halla un guijarro brillante bajo la luna suave")
        ]
        for (lang, description) in cases {
            let filled = StoryPromptTemplate.filledStoryPrompt(
                description: description,
                language: lang
            )
            XCTAssertFalse(filled.isEmpty, lang.rawValue)
            XCTAssertFalse(
                StoryPromptTemplate.containsUnresolvedDescriptionPlaceholder(filled),
                "unresolved placeholder in \(lang.rawValue)"
            )
            XCTAssertTrue(filled.contains(description), lang.rawValue)
            XCTAssertFalse(filled.contains("[INSERT PHOTO CAPTION HERE]"), lang.rawValue)
            XCTAssertFalse(filled.contains("INSERIR A LEGENDA"), lang.rawValue)
        }
    }

    func testStoryPromptWeavesStoryElements() {
        let elements = "Main character (must look exactly like this on every page): little girl, dark hair"
        let filled = StoryPromptTemplate.filledStoryPrompt(
            description: "a little rabbit finds a glowing pebble under the soft moon",
            storyElements: elements,
            language: .englishUS
        )
        XCTAssertTrue(filled.contains(elements))
        XCTAssertTrue(filled.contains("Story elements"))
    }

    func testStoryPromptDropsEmptyStoryElementsSection() {
        let filled = StoryPromptTemplate.filledStoryPrompt(
            description: "a little rabbit finds a glowing pebble under the soft moon",
            storyElements: nil,
            language: .englishUS
        )
        XCTAssertFalse(filled.contains("Story elements"))
        XCTAssertFalse(filled.contains("[INSERT STORY ELEMENTS HERE]"))
    }

    func testBiblePromptFillsDescriptionAndTagsInAllLanguages() {
        let cases: [(AppLanguage, String)] = [
            (.englishUS, "Alice is a happy kid who loves her garden"),
            (.portugueseBrazil, "Alice é uma criança feliz que adora o jardim"),
            (.spanishSpain, "Alice es una niña feliz que adora su jardín")
        ]
        for (lang, description) in cases {
            let filled = StoryPromptTemplate.filledBiblePrompt(
                description: description,
                photoTags: "little girl, dark hair, red coat",
                language: lang
            )
            XCTAssertTrue(filled.contains("CHARACTER:"), lang.rawValue)
            XCTAssertTrue(filled.contains("SETTING:"), lang.rawValue)
            XCTAssertTrue(filled.contains("PROPS:"), lang.rawValue)
            XCTAssertTrue(filled.contains(description), lang.rawValue)
            XCTAssertTrue(filled.contains("little girl, dark hair, red coat"), lang.rawValue)
            XCTAssertFalse(
                filled.contains("[INSERT PHOTO TAGS HERE]"),
                "unresolved tag placeholder in \(lang.rawValue)"
            )
            XCTAssertFalse(
                StoryPromptTemplate.containsUnresolvedDescriptionPlaceholder(filled),
                "unresolved description placeholder in \(lang.rawValue)"
            )
        }
    }

    func testBiblePromptWithoutTagsSaysNone() {
        let filled = StoryPromptTemplate.filledBiblePrompt(
            description: "a little rabbit finds a glowing pebble under the soft moon",
            photoTags: nil,
            language: .englishUS
        )
        XCTAssertTrue(filled.contains("(none)"))
        XCTAssertFalse(filled.contains("[INSERT PHOTO TAGS HERE]"))
    }

    func testIllustrationPromptIsEnglishAndHasTenSlots() {
        for lang in AppLanguage.allCases {
            let filled = StoryPromptTemplate.filledIllustrationPrompt(
                title: "Lantern Garden",
                paragraphs: (1...10).map { "Paragraph \($0)" },
                elementsBlock: "Main character (must look exactly like this on every page): orange kitten, round eyes",
                language: lang
            )
            XCTAssertTrue(filled.contains("CHARACTER:"), lang.rawValue)
            XCTAssertTrue(filled.lowercased().contains("english"), lang.rawValue)
            XCTAssertTrue(filled.contains("Paragraph 10"), lang.rawValue)
            XCTAssertTrue(filled.contains("orange kitten, round eyes"), lang.rawValue)
            XCTAssertTrue(filled.contains("Story bible"), lang.rawValue)
            XCTAssertFalse(filled.contains("[INSERT STORY TITLE HERE]"), lang.rawValue)
            XCTAssertFalse(filled.contains("[INSERT STORY BIBLE HERE]"), lang.rawValue)
        }
    }

    func testStoryBibleParserParsesFullReply() throws {
        let raw = """
        CHARACTER: little girl, dark brown braids, red coat, yellow boots
        ALSO: grandpa, grey beard, blue cardigan
        SETTING: cozy seaside village, spring morning
        PROPS: red rose, brass lantern, wicker basket
        """
        let bible = try StoryBibleParser.parse(raw)
        XCTAssertEqual(bible.characterLock, "little girl, dark brown braids, red coat, yellow boots")
        XCTAssertEqual(bible.supporting, "grandpa, grey beard, blue cardigan")
        XCTAssertEqual(bible.setting, "cozy seaside village, spring morning")
        XCTAssertEqual(bible.props, ["red rose", "brass lantern", "wicker basket"])
    }

    func testStoryBibleParserTreatsNoneAsEmptyAndToleratesFences() throws {
        let raw = """
        ```text
        **CHARACTER:** orange kitten, round eyes
        **ALSO:** (none)
        SETTING: sunny garden
        PROPS: (none)
        ```
        """
        let bible = try StoryBibleParser.parse(raw)
        XCTAssertEqual(bible.characterLock, "orange kitten, round eyes")
        XCTAssertEqual(bible.supporting, "")
        XCTAssertEqual(bible.setting, "sunny garden")
        XCTAssertTrue(bible.props.isEmpty)
    }

    func testStoryBibleParserRequiresCharacterLock() {
        XCTAssertThrowsError(try StoryBibleParser.parse("SETTING: a quiet attic at night")) { error in
            XCTAssertEqual(error as? StoryBibleError, .missingCharacterLock)
        }
        XCTAssertThrowsError(try StoryBibleParser.parse("   ")) { error in
            XCTAssertEqual(error as? StoryBibleError, .missingCharacterLock)
        }
    }

    func testStoryBiblePartialMergePrefersFirstPassValues() throws {
        let first = StoryBibleParser.parsePartial("""
        SETTING: first setting
        """)
        let second = StoryBibleParser.parsePartial("""
        CHARACTER: brave bunny, white fur
        SETTING: second setting
        """)
        var merged = first
        if merged.characterLock.isEmpty { merged.characterLock = second.characterLock }
        if merged.setting.isEmpty { merged.setting = second.setting }
        let bible = try StoryBibleParser.validate(merged)
        XCTAssertEqual(bible.characterLock, "brave bunny, white fur")
        XCTAssertEqual(bible.setting, "first setting")
    }

    func testStoryBibleRenderedBlockCarriesLockPropsAndSkipsEmpties() {
        let bible = StoryBible(
            characterLock: "little girl, dark brown braids, red coat",
            supporting: "",
            setting: "cozy seaside village",
            props: ["red rose"]
        )
        let block = bible.renderedBlock
        XCTAssertTrue(block.contains("little girl, dark brown braids, red coat"))
        XCTAssertTrue(block.contains("cozy seaside village"))
        XCTAssertTrue(block.contains("red rose"))
        XCTAssertFalse(block.contains("Other characters"))

        // Codable round-trip keeps the bible persistable in story.json.
        let data = try! JSONEncoder().encode(bible)
        let decoded = try! JSONDecoder().decode(StoryBible.self, from: data)
        XCTAssertEqual(decoded, bible)
    }

    func testDeviceStoryGeneratorThrowsWhenModelMissing() async throws {        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = OnDeviceMLXModelStore(documentsURL: tmp)
        let generator = DeviceStoryGenerator(modelStore: store)
        let seed = StorySeedPrompt(
            text: "a little rabbit finds a glowing pebble under the soft moon light",
            language: .englishUS
        )
        do {
            _ = try await generator.generate(from: seed)
            XCTFail("expected modelNotInstalled")
        } catch let e as StoryPromptError {
            XCTAssertEqual(e, .modelNotInstalled)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
