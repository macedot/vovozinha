import Foundation

/// Deterministic post-processing so on-device LLM drafts can **ship** even when the model
/// ignores punctuation / length instructions. Safety-only failures still need a rewrite.
enum StoryDraftRepair {
    static func repair(_ plan: StoryPlan, language: AppLanguage) -> StoryPlan {
        var pages = plan.pages
            .map { page -> StoryPlanPage in
                var p = page
                p.text = normalizeWhitespace(page.text)
                return p
            }
            .filter { !$0.text.isEmpty }

        // Pad / trim to fixed page count.
        pages = fitPageCount(pages, language: language, plan: plan)

        // Fix phrase density, duplicates, then word band.
        pages = pages.enumerated().map { index, page in
            var p = page
            p.index = index
            p.text = ensurePhraseDensity(p.text, language: language)
            return p
        }
        pages = breakDuplicates(pages, language: language)
        pages = fitWordBand(pages, language: language)

        // Re-assign stable scene tags / indices.
        let tags = StorySceneTags.ordered
        pages = pages.enumerated().map { index, page in
            var p = page
            p.index = index
            if index < tags.count {
                p.sceneTag = tags[index]
            }
            return p
        }

        var repaired = plan
        repaired.pages = pages
        if !KidsSafetyFilter.isTextSafe(repaired.title) {
            repaired.title = safeFallbackTitle(language: language, hero: plan.character.name)
        }
        return repaired
    }

    // MARK: - Page count

    private static func fitPageCount(
        _ pages: [StoryPlanPage],
        language: AppLanguage,
        plan: StoryPlan
    ) -> [StoryPlanPage] {
        let target = FeatureFlags.fixedPageCount
        if pages.count == target { return pages }
        if pages.count > target {
            return Array(pages.prefix(target))
        }
        // Too few: split longest pages, then pad with gentle beats.
        var result = pages
        while result.count < target {
            if let splitIndex = result.indices.max(by: {
                result[$0].text.split(whereSeparator: \.isWhitespace).count
                    < result[$1].text.split(whereSeparator: \.isWhitespace).count
            }), result[splitIndex].text.split(whereSeparator: \.isWhitespace).count >= 6 {
                let parts = splitInHalf(result[splitIndex].text)
                if parts.count == 2 {
                    var a = result[splitIndex]
                    a.text = parts[0]
                    var b = result[splitIndex]
                    b.text = parts[1]
                    result.remove(at: splitIndex)
                    result.insert(contentsOf: [a, b], at: splitIndex)
                    continue
                }
            }
            let pad = softPadLine(language: language, hero: plan.character.name, index: result.count)
            var last = result.last ?? StoryPlanPage(
                index: result.count,
                text: pad,
                imagePrompt: "",
                narrationHint: "",
                sceneTag: ""
            )
            last = StoryPlanPage(
                index: result.count,
                text: pad,
                imagePrompt: last.imagePrompt,
                narrationHint: last.narrationHint,
                sceneTag: last.sceneTag
            )
            result.append(last)
        }
        return Array(result.prefix(target))
    }

    private static func splitInHalf(_ text: String) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 4 else { return [text] }
        let mid = words.count / 2
        let left = words[..<mid].joined(separator: " ")
        let right = words[mid...].joined(separator: " ")
        return [ensureTerminalPunctuation(left), ensureTerminalPunctuation(right)]
    }

    // MARK: - Phrase density

    static func ensurePhraseDensity(_ text: String, language: AppLanguage) -> String {
        let t = normalizeWhitespace(text)
        guard !t.isEmpty else { return softPadLine(language: language, hero: "Luma", index: 0) }

        if KidsSafetyFilter.approximatePhraseCount(t) >= 2 {
            return ensureTerminalPunctuation(t)
        }

        // Try splitting on soft connectors / commas.
        for sep in softSeparators(language) {
            if let range = t.range(of: sep) {
                let left = t[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let right = t[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !left.isEmpty, !right.isEmpty {
                    return ensureTerminalPunctuation(left) + " " + ensureTerminalPunctuation(right)
                }
            }
        }

        // Split near the middle on a space.
        let words = t.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count >= 4 {
            let mid = words.count / 2
            let left = words[..<mid].joined(separator: " ")
            let right = words[mid...].joined(separator: " ")
            return ensureTerminalPunctuation(left) + " " + ensureTerminalPunctuation(right)
        }

        // Very short: append a second gentle sentence.
        let second = secondSentence(language: language)
        return ensureTerminalPunctuation(t) + " " + second
    }

    private static func softSeparators(_ language: AppLanguage) -> [String] {
        switch language {
        case .portugueseBrazil:
            return [", ", " e ", " depois ", " então ", " quando "]
        case .englishUS:
            return [", ", " and ", " then ", " when ", " while "]
        case .spanishSpain:
            return [", ", " y ", " luego ", " entonces ", " cuando "]
        }
    }

    private static func secondSentence(language: AppLanguage) -> String {
        switch language {
        case .portugueseBrazil: return "Tudo fica calmo."
        case .englishUS: return "Everything feels calm."
        case .spanishSpain: return "Todo se siente en calma."
        }
    }

    // MARK: - Duplicates

    private static func breakDuplicates(_ pages: [StoryPlanPage], language: AppLanguage) -> [StoryPlanPage] {
        guard !pages.isEmpty else { return pages }
        var result: [StoryPlanPage] = []
        for page in pages {
            var p = page
            if let prev = result.last, prev.text == p.text {
                p.text = ensurePhraseDensity(
                    p.text + " " + uniqueBeat(language: language, index: result.count),
                    language: language
                )
            }
            result.append(p)
        }
        return result
    }

    private static func uniqueBeat(language: AppLanguage, index: Int) -> String {
        switch language {
        case .portugueseBrazil:
            return index % 2 == 0 ? "Algo novo acontece." : "O momento muda devagar."
        case .englishUS:
            return index % 2 == 0 ? "Something new happens." : "The moment gently changes."
        case .spanishSpain:
            return index % 2 == 0 ? "Algo nuevo sucede." : "El momento cambia despacio."
        }
    }

    // MARK: - Word band

    private static func fitWordBand(_ pages: [StoryPlanPage], language: AppLanguage) -> [StoryPlanPage] {
        var result = pages
        var words = result.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).count

        // Too long: trim longest pages (only far above the descriptive band).
        var guardRails = 0
        let maxWords = FeatureFlags.maxStoryWordCount
        let minWords = FeatureFlags.minStoryWordCount
        while words > maxWords && guardRails < 40 {
            guardRails += 1
            guard let idx = result.indices.max(by: {
                result[$0].text.split(whereSeparator: \.isWhitespace).count
                    < result[$1].text.split(whereSeparator: \.isWhitespace).count
            }) else { break }
            let trimmed = trimWords(result[idx].text, keep: max(12, result[idx].text.split(whereSeparator: \.isWhitespace).count - 4))
            if trimmed == result[idx].text { break }
            result[idx].text = ensurePhraseDensity(trimmed, language: language)
            words = result.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).count
        }

        // Too short: append gentle descriptive beats across pages.
        guardRails = 0
        while words < minWords && guardRails < 40 {
            guardRails += 1
            let idx = max(0, result.count - 1 - (guardRails % max(1, result.count)))
            let extra = expandBeat(language: language, index: guardRails)
            result[idx].text = ensurePhraseDensity(result[idx].text + " " + extra, language: language)
            words = result.map(\.text).joined(separator: " ").split(whereSeparator: \.isWhitespace).count
        }

        return result
    }

    private static func trimWords(_ text: String, keep: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > keep, keep > 0 else { return text }
        return ensureTerminalPunctuation(words.prefix(keep).joined(separator: " "))
    }

    private static func expandBeat(language: AppLanguage, index: Int) -> String {
        switch language {
        case .portugueseBrazil:
            let opts = [
                "As cores do lugar brilham baixinho.",
                "Um cheiro doce paira no ar.",
                "O coração de todos fica quentinho.",
                "A luz dourada dança nas folhas.",
                "Um sorriso calmo aparece no rosto."
            ]
            return opts[index % opts.count]
        case .englishUS:
            let opts = [
                "Soft colors glow all around.",
                "A sweet scent floats in the air.",
                "Warm feelings fill every heart.",
                "Golden light dances on the leaves.",
                "A calm smile appears on their face."
            ]
            return opts[index % opts.count]
        case .spanishSpain:
            let opts = [
                "Los colores del lugar brillan bajito.",
                "Un olor dulce flota en el aire.",
                "El corazón de todos se calienta.",
                "La luz dorada baila en las hojas.",
                "Una sonrisa calmada aparece en su rostro."
            ]
            return opts[index % opts.count]
        }
    }

    // MARK: - Helpers

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ensureTerminalPunctuation(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if let last = t.last, ".!?…".contains(last) { return t }
        return t + "."
    }

    private static func softPadLine(language: AppLanguage, hero: String, index: Int) -> String {
        let h = hero.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Luma" : hero
        switch language {
        case .portugueseBrazil:
            return "\(h) respira fundo. Tudo fica bem."
        case .englishUS:
            return "\(h) takes a soft breath. All is well."
        case .spanishSpain:
            return "\(h) respira despacio. Todo está bien."
        }
    }

    private static func safeFallbackTitle(language: AppLanguage, hero: String) -> String {
        let h = hero.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Luma" : hero
        switch language {
        case .portugueseBrazil: return "\(h) e a noite calma"
        case .englishUS: return "\(h) and the calm night"
        case .spanishSpain: return "\(h) y la noche tranquila"
        }
    }
}
