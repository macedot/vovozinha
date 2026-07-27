import Foundation
import VovoUI

/// On-device LLM story generator backed by LiteRT-LM (Gemma 3n E2B int4).
///
/// Inference is **100% local** — see `LiteRTLMEngineSession`. The model file is obtained
/// out-of-band by `LiteRTLMModelStore`. When the model is unavailable or inference fails,
/// `OfflineFirstStoryGenerator` falls back to the deterministic offline generator, so the
/// app always works offline.
///
/// The output contract is unchanged from the offline generator: a `StoryDraft` with a
/// title, summary, and **exactly 10 paragraphs**, with `language` echoed from the seed.
public struct LiteRTLMStoryGenerator: StoryFromPromptGenerating {
    /// Reuses the offline generator's placeholder substitution so the parent's description
    /// is injected into the `litert.<lang>.md` template (never left raw).
    private static let offlinePromptHelper = OfflineStoryFromPromptGenerator.self

    private let session: any LiteRTLMEngineSessioning

    /// - Parameters:
    ///   - modelPath: Filesystem path to the downloaded `.litertlm` model.
    ///   - cacheDir: Writable dir for the compiled-model cache.
    ///   - session: Inject a conformer for tests; defaults to the real LiteRT-LM engine
    ///              (**physical iOS device only**).
    public init(
        modelPath: String,
        cacheDir: String,
        session: (any LiteRTLMEngineSessioning)? = nil
    ) throws {
        if let session {
            self.session = session
        } else {
            #if os(iOS) && !targetEnvironment(simulator)
            self.session = try LiteRTLMEngineSession(modelPath: modelPath, cacheDir: cacheDir)
            #else
            throw StoryPromptError.generationFailed
            #endif
        }
    }

    public func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        try prompt.validate()

        let seed = prompt.trimmed
        let lang = prompt.language

        // Build the prompt from the litert.<lang>.md template, injecting the description.
        let userPrompt = Self.buildPrompt(seed: seed, language: lang)
        guard !userPrompt.isEmpty,
              !Self.offlinePromptHelper.containsUnresolvedDescriptionPlaceholder(userPrompt) else {
            throw StoryPromptError.generationFailed
        }

        let raw = try await session.send(userPrompt)
        let parsed = try Self.parse(raw, language: lang)

        return StoryDraft(
            title: parsed.title,
            summary: parsed.summary,
            seedPrompt: seed,
            paragraphs: parsed.paragraphs,
            language: lang
        )
    }

    // MARK: - Prompt building

    /// Loads `litert.<lang>.md` (falls back to en-US) and injects the parent's description,
    /// reusing the offline generator's placeholder machinery.
    static func buildPrompt(seed: String, language: AppLanguage) -> String {
        let path = "Prompts/litert.\(language.rawValue).md"
        let fallback = "Prompts/litert.\(AppLanguage.englishUS.rawValue).md"
        var raw = MarkdownTextCatalog.loadFile(
            path,
            bundle: .module,
            sourceFallbackRoot: OfflineStoryFromPromptGenerator.sourcePromptsRoot
        )
        if raw.isEmpty {
            raw = MarkdownTextCatalog.loadFile(
                fallback,
                bundle: .module,
                sourceFallbackRoot: OfflineStoryFromPromptGenerator.sourcePromptsRoot
            )
        }
        return offlinePromptHelper.replaceDescriptionPlaceholders(in: raw, with: seed)
    }

    // MARK: - Response parsing

    struct ParsedStory: Equatable {
        let title: String
        let summary: String
        let paragraphs: [String]
    }

    /// Parses the model's structured reply into a title, summary, and exactly 10 paragraphs.
    ///
    /// Expected layout:
    /// ```
    /// TITLE: ...
    /// SUMMARY: ...
    /// <blank>
    /// para 1
    /// <blank>
    /// para 2
    /// ...
    /// ```
    /// Tolerant of missing headers, leading/trailing whitespace, and models that ignore the
    /// format. A reply with **fewer than 10 paragraphs** is a generation failure (throw) so
    /// `OfflineFirstStoryGenerator` can fall back — never padded with empty scenes.
    static func parse(_ raw: String, language: AppLanguage = .englishUS) throws -> ParsedStory {
        var title: String?
        var summary: String?
        var body = raw

        // A blank/garbage reply is a generation failure: nothing usable to turn into a story.
        let nonBlank = raw.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard nonBlank else { throw StoryPromptError.generationFailed }

        // Peel off TITLE / SUMMARY header lines (case-insensitive).
        var headerLines: [String] = []
        let lines = body.components(separatedBy: .newlines)
        var consumedUpTo = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { consumedUpTo = index + 1; break } // first blank line ends the header
            if title == nil, trimmed.lowercased().hasPrefix("title:") {
                title = String(trimmed.dropFirst("title:".count)).trimmingCharacters(in: .whitespaces)
                headerLines.append(line)
                consumedUpTo = index + 1
            } else if summary == nil, trimmed.lowercased().hasPrefix("summary:") {
                summary = String(trimmed.dropFirst("summary:".count)).trimmingCharacters(in: .whitespaces)
                headerLines.append(line)
                consumedUpTo = index + 1
            } else {
                break
            }
        }
        body = lines.dropFirst(consumedUpTo).joined(separator: "\n")

        let paragraphs = try normalizeParagraphs(body)

        let finalTitle = (title?.isEmpty == false ? title : nil) ?? Self.fallbackTitle(for: language)
        let finalSummary = (summary?.isEmpty == false ? summary : nil) ?? ""

        return ParsedStory(title: finalTitle, summary: finalSummary, paragraphs: paragraphs)
    }

    /// Localized title used when the model omits the `TITLE:` header.
    static func fallbackTitle(for language: AppLanguage) -> String {
        switch language {
        case .englishUS: return "Bedtime Story"
        case .portugueseBrazil: return "História de ninar"
        case .spanishSpain: return "Cuento de dormir"
        }
    }

    /// Splits the body into blank-line-separated paragraphs, trims each, drops empties, and
    /// truncates to **exactly 10**. Throws when the model produced fewer than 10 — the caller
    /// treats that as a generation failure and falls back instead of showing empty scenes.
    static func normalizeParagraphs(_ body: String, target: Int = 10) throws -> [String] {
        // Split on one-or-more blank lines.
        let chunks = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // If the model returned a single non-empty blob, split on single newlines as a fallback.
        var paragraphs = chunks
        if chunks.count == 1, let only = chunks.first {
            let bySingle = only
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if bySingle.count > 1 { paragraphs = bySingle }
        }

        guard paragraphs.count >= target else { throw StoryPromptError.generationFailed }
        return Array(paragraphs.prefix(target))
    }
}
