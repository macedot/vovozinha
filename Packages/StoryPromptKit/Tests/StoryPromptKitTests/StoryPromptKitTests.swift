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

    func testLiteRTPromptReplacesDescriptionPlaceholdersInAllLanguages() {
        let cases: [(AppLanguage, String)] = [
            (.englishUS, "a little rabbit finds a glowing pebble under the soft moon"),
            (.portugueseBrazil, "um coelhinho acha um seixo brilhante sob a lua macia"),
            (.spanishSpain, "un conejito halla un guijarro brillante bajo la luna suave")
        ]
        for (lang, description) in cases {
            let filled = StoryPromptTemplate.filledLiteRTPrompt(
                description: description,
                language: lang
            )
            XCTAssertFalse(filled.isEmpty, lang.rawValue)
            XCTAssertFalse(
                StoryPromptTemplate.containsUnresolvedDescriptionPlaceholder(filled),
                "unresolved placeholder in \(lang.rawValue)"
            )
            XCTAssertTrue(filled.contains(description), lang.rawValue)
        }
    }

    func testDeviceStoryGeneratorThrowsWhenModelMissing() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = LiteRTLMModelStore(documentsURL: tmp)
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
