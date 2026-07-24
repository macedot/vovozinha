import Foundation

enum KidsSafetyFilter {
    /// Whole-word style tokens (matched on word boundaries, not raw substring).
    /// Avoids false positives like "skill"⊃"kill" or "sexto"⊃"sex".
    private static let blockedTokens = [
        // PT
        "matar", "sangue", "terror", "assombro", "assombrado", "assombrada",
        "suicidio", "suicídio", "sexo", "nudez", "droga", "drogas",
        "armas", "tiro", "tiros", "tortura", "estupro", "odio", "ódio",
        // EN
        "kill", "killing", "killed", "blood", "bloody", "horror",
        "nude", "naked", "sex", "sexual", "drug", "drugs",
        "gun", "guns", "shoot", "shooting", "torture", "rape", "hate",
        // ES
        "sangre", "desnud", "desnudo", "desnuda", "odio"
    ]

    static func isTextSafe(_ text: String) -> Bool {
        !containsBlockedToken(text)
    }

    static func containsBlockedToken(_ text: String) -> Bool {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return false }
        let blocked = Set(blockedTokens.map { normalizeToken($0) })
        return tokens.contains { blocked.contains($0) }
    }

    // MARK: - Split validation

    /// True safety problems (must not ship / may need LLM rewrite).
    static func safetyIssues(plan: StoryPlan) -> [String] {
        var issues: [String] = []
        if plan.pages.isEmpty {
            issues.append("empty_story")
        }
        if !isTextSafe(plan.title) {
            issues.append("unsafe_title")
        }
        for page in plan.pages {
            let text = page.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                issues.append("empty_page_\(page.index + 1)")
            }
            // Body only — image prompts are code-built and not shown to kids.
            if !isTextSafe(page.text) {
                issues.append("unsafe_page_\(page.index + 1)")
            }
        }
        return issues
    }

    /// Structural problems (prefer `StoryDraftRepair` over LLM retry).
    static func structureIssues(plan: StoryPlan) -> [String] {
        var issues: [String] = []
        if plan.pages.count != FeatureFlags.fixedPageCount {
            issues.append("page_count_\(plan.pages.count)")
        }

        var previous = ""
        for page in plan.pages {
            let text = page.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let phraseCount = approximatePhraseCount(text)
            if phraseCount < 2 {
                issues.append("short_page_\(page.index + 1)")
            }
            // Descriptive scenes may use several short sentences (still soft cap).
            if phraseCount > 10 {
                issues.append("long_page_\(page.index + 1)")
            }
            if !previous.isEmpty, text == previous {
                issues.append("dup_page_\(page.index + 1)")
            }
            previous = text
        }

        let words = wordCount(plan)
        if words > 0 && (words < FeatureFlags.minStoryWordCount || words > FeatureFlags.maxStoryWordCount) {
            issues.append("word_count_\(words)")
        }
        return issues
    }

    /// Ready to save after repair: no safety issues and structure OK.
    static func canShip(_ plan: StoryPlan) -> Bool {
        safetyIssues(plan: plan).isEmpty && structureIssues(plan: plan).isEmpty
    }

    /// Legacy aggregate (tests / debugging). Prefer `canShip` + repair in product path.
    static func validate(plan: StoryPlan) -> [String] {
        safetyIssues(plan: plan) + structureIssues(plan: plan)
    }

    static func wordCount(_ plan: StoryPlan) -> Int {
        plan.pages
            .map(\.text)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .count
    }

    /// Counts sentence-like chunks (. ! ? … ; or line breaks) and comma clauses as fallback.
    static func approximatePhraseCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let separators = CharacterSet(charactersIn: ".!?…\n;")
        let parts = trimmed.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 { return parts.count }
        let clauses = trimmed.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return max(parts.count, clauses.count)
    }

    // MARK: - Tokenization

    private static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalizeToken)
            .filter { !$0.isEmpty }
    }

    private static func normalizeToken(_ token: String) -> String {
        token
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}
