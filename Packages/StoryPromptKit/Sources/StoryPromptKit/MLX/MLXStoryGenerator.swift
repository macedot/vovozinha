import Foundation
import VovoUI

/// On-device LLM story generator backed by **Qwen3.5-4B-MLX-4bit** (MLX).
///
/// Inference is **100% local**. The model directory is obtained out-of-band by
/// `OnDeviceMLXModelStore`. There is **no** static story fallback: failures throw.
///
/// Output: `StoryDraft` with title, summary, and **exactly 10 paragraphs**.
public struct MLXStoryGenerator: StoryFromPromptGenerating {
    private let session: any MLXStoryEngineSessioning

    /// - Parameters:
    ///   - modelDirectory: Filesystem URL of the unpacked MLX model pack.
    ///   - session: Inject a conformer for tests; defaults to the real MLX engine when linked.
    public init(
        modelDirectory: URL,
        session: (any MLXStoryEngineSessioning)? = nil
    ) throws {
        if let session {
            self.session = session
        } else {
            #if canImport(MLXLLM) && canImport(MLXLMCommon)
            self.session = MLXStoryEngineSession(modelDirectory: modelDirectory)
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

        let raw: String
        do {
            raw = try await session.send(userPrompt)
        } catch {
            #if DEBUG
            print("[MLXStory] session.send failed: \(error)")
            #endif
            throw StoryPromptError.generationFailed
        }

        let cleaned = Self.stripThinkingBlocks(raw)
        #if DEBUG
        if cleaned.count < raw.count {
            print("[MLXStory] stripped thinking; cleaned chars=\(cleaned.count)")
        }
        #endif

        let parsed: ParsedStory
        do {
            parsed = try Self.parse(cleaned, language: lang)
        } catch {
            #if DEBUG
            let chunks = cleaned
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            print(
                "[MLXStory] parse failed: blank=\(cleaned.isEmpty) doubleNewlineChunks=\(chunks.count) preview=\(cleaned.prefix(400).replacingOccurrences(of: "\n", with: "⏎"))"
            )
            #endif
            throw StoryPromptError.generationFailed
        }

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
        StoryPromptTemplate.filledStoryPrompt(description: seed, language: language)
    }

    /// Drop Qwen-style thinking wrappers if the model emits them despite `enable_thinking: false`.
    static func stripThinkingBlocks(_ raw: String) -> String {
        var text = raw
        // Closed blocks: <think>...</think>
        if let regex = try? NSRegularExpression(
            pattern: #"(?is)<think>.*?</think>"#,
            options: []
        ) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        // Truncated / open block (hit maxTokens mid-think): drop from first <think> to end,
        // then fall back to anything after a late </think> if present.
        if let open = text.range(of: "<think>", options: .caseInsensitive) {
            if let close = text.range(of: "</think>", options: [.caseInsensitive, .backwards]),
               close.lowerBound > open.lowerBound {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                // No usable story after an unfinished think — clear the think prefix.
                text = String(text[text.startIndex..<open.lowerBound])
            }
        }
        // Redundant empty markers some templates inject.
        text = text
            .replacingOccurrences(of: "<think>\n\n</think>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "<think></think>", with: "", options: .caseInsensitive)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let cleanedBody = stripLeadingListMarkers(body)
        let chunks = cleanedBody
            .components(separatedBy: "\n\n")
            .map { stripLeadingListMarkers($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var paragraphs = chunks
        if chunks.count == 1, let only = chunks.first {
            let bySingle = only
                .components(separatedBy: .newlines)
                .map { stripLeadingListMarkers($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if bySingle.count > 1 { paragraphs = bySingle }
        }

        guard paragraphs.count >= target else { throw StoryPromptError.generationFailed }
        return Array(paragraphs.prefix(target))
    }

    /// Drops optional `1.` / `1)` / `Paragraph 1:` prefixes models sometimes add.
    static func stripLeadingListMarkers(_ text: String) -> String {
        var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(
            pattern: #"^(?i)(?:paragraph\s+)?\d+[\.\)\:\-]\s+"#,
            options: []
        ) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            line = regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
        }
        return line
    }
}
