import Foundation
import VovoUI

/// On-device LLM story generator backed by LiteRT-LM (Gemma 4 E4B `.litertlm` weights).
///
/// Inference is **100% local**. The model file is obtained out-of-band by `LiteRTLMModelStore`.
/// There is **no** static story fallback: failures throw.
///
/// Output: `StoryDraft` with title, summary, and **exactly 10 paragraphs**.
public struct LiteRTLMStoryGenerator: StoryFromPromptGenerating {
    private let session: any LiteRTLMEngineSessioning

    /// - Parameters:
    ///   - modelPath: Filesystem path to the downloaded `.litertlm` model.
    ///   - cacheDir: Writable dir for the compiled-model cache.
    ///   - session: Inject a conformer for tests; defaults to the real LiteRT-LM engine.
    public init(
        modelPath: String,
        cacheDir: String,
        session: (any LiteRTLMEngineSessioning)? = nil
    ) throws {
        if let session {
            self.session = session
        } else {
            #if canImport(LiteRTLM)
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

        let userPrompt = Self.buildPrompt(seed: seed, language: lang)
        guard !userPrompt.isEmpty,
              !StoryPromptTemplate.containsUnresolvedDescriptionPlaceholder(userPrompt) else {
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

    static func buildPrompt(seed: String, language: AppLanguage) -> String {
        StoryPromptTemplate.filledLiteRTPrompt(description: seed, language: language)
    }

    // MARK: - Response parsing

    struct ParsedStory: Equatable {
        let title: String
        let summary: String
        let paragraphs: [String]
    }

    /// Parses the model's structured reply. **Fewer than 10 paragraphs → throws** (no padding).
    static func parse(_ raw: String, language: AppLanguage = .englishUS) throws -> ParsedStory {
        var title: String?
        var summary: String?
        var body = raw

        let nonBlank = raw.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard nonBlank else { throw StoryPromptError.generationFailed }

        let lines = body.components(separatedBy: .newlines)
        var consumedUpTo = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { consumedUpTo = index + 1; break }
            if title == nil, trimmed.lowercased().hasPrefix("title:") {
                title = String(trimmed.dropFirst("title:".count)).trimmingCharacters(in: .whitespaces)
                consumedUpTo = index + 1
            } else if summary == nil, trimmed.lowercased().hasPrefix("summary:") {
                summary = String(trimmed.dropFirst("summary:".count)).trimmingCharacters(in: .whitespaces)
                consumedUpTo = index + 1
            } else {
                break
            }
        }
        body = lines.dropFirst(consumedUpTo).joined(separator: "\n")

        let paragraphs = try normalizeParagraphs(body)
        let finalTitle = (title?.isEmpty == false ? title : nil) ?? Self.defaultTitle(for: language)
        let finalSummary = (summary?.isEmpty == false ? summary : nil) ?? ""

        return ParsedStory(title: finalTitle, summary: finalSummary, paragraphs: paragraphs)
    }

    static func defaultTitle(for language: AppLanguage) -> String {
        switch language {
        case .englishUS: return "Bedtime Story"
        case .portugueseBrazil: return "História de ninar"
        case .spanishSpain: return "Cuento de dormir"
        }
    }

    static func normalizeParagraphs(_ body: String, target: Int = 10) throws -> [String] {
        let chunks = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

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
