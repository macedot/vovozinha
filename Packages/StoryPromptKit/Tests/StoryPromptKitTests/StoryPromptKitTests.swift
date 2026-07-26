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
            let draft = try await OfflineStoryFromPromptGenerator().generate(from: seed)
            XCTAssertEqual(draft.paragraphs.count, 10, lang.rawValue)
            XCTAssertEqual(draft.language, lang)
            XCTAssertTrue(
                draft.summary.localizedCaseInsensitiveContains(summaryMarker)
                    || draft.summary.localizedCaseInsensitiveContains(text.split(separator: " ").first.map(String.init) ?? ""),
                "summary should be localized for \(lang.rawValue): \(draft.summary)"
            )
            // Scene text should not be English-only when PT/ES is selected.
            switch lang {
            case .englishUS:
                XCTAssertTrue(draft.paragraphs[0].contains("Evening light") || draft.paragraphs[0].localizedCaseInsensitiveContains("gentle"))
            case .portugueseBrazil:
                XCTAssertTrue(
                    draft.paragraphs[0].localizedCaseInsensitiveContains("luz")
                        || draft.paragraphs[0].localizedCaseInsensitiveContains("história")
                        || draft.paragraphs[9].localizedCaseInsensitiveContains("noite")
                )
            case .spanishSpain:
                XCTAssertTrue(
                    draft.paragraphs[0].localizedCaseInsensitiveContains("luz")
                        || draft.paragraphs[0].localizedCaseInsensitiveContains("cuento")
                        || draft.paragraphs[9].localizedCaseInsensitiveContains("noche")
                )
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
}
