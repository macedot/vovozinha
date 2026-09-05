import Foundation
import StoryPromptKit
import VovoUI

/// Raw-completion seam so the illustration prompt pass is unit-testable.
public protocol IllustrationPromptCompleting: Sendable {
    func complete(_ prompt: String) async throws -> String
}

/// Wraps the concrete Qwen completer behind the seam.
public struct DeviceCompleterAdapter: IllustrationPromptCompleting {
    private let completer: DevicePromptCompleter

    public init(_ completer: DevicePromptCompleter) {
        self.completer = completer
    }

    public func complete(_ prompt: String) async throws -> String {
        try await completer.complete(prompt)
    }
}

/// One Qwen pass → CHARACTER lock + 10 English scene prompts. Never fabricates lines.
public struct DeviceIllustrationPromptGenerator: IllustrationPromptGenerating {
    private let completer: any IllustrationPromptCompleting
    private let language: AppLanguage

    public init(
        completer: (any IllustrationPromptCompleting)? = nil,
        language: AppLanguage = .englishUS
    ) {
        self.completer = completer ?? DeviceCompleterAdapter(DevicePromptCompleter())
        self.language = language
    }

    public func generate(
        draftTitle: String,
        paragraphs: [String],
        caption: String?
    ) async throws -> IllustrationPlan {
        let filled = StoryPromptTemplate.filledIllustrationPrompt(
            title: draftTitle,
            paragraphs: paragraphs,
            photoCaption: caption,
            language: language
        )
        // Chat session is shared with story writing. Repeat the list format here so
        // Qwen cannot fall back to TITLE:/SUMMARY:/paragraphs.
        let prompt = """
        Output ONLY this list (English). No TITLE, SUMMARY, or story paragraphs.

        \(filled)
        """
        // First attempt, then ONE targeted repair pass asking only for what is
        // missing. A still-incomplete reply throws — lines are never invented.
        let raw = try await completer.complete(prompt)
        do {
            return try IllustrationPromptParser.parse(raw)
        } catch {
            return try await repair(from: raw, originalPrompt: prompt, filled: filled)
        }
    }

    private func repair(
        from raw: String,
        originalPrompt: String,
        filled: String
    ) async throws -> IllustrationPlan {
        let partial = IllustrationPromptParser.parsePartial(raw)
        let missing = (1...IllustrationPromptParser.requiredCount).filter {
            (partial.lines[$0] ?? "").isEmpty
        }
        guard !missing.isEmpty || partial.descriptor.isEmpty else {
            return try IllustrationPromptParser.validate(partial)
        }

        var ask = "Output ONLY in English, same format as before."
        if partial.descriptor.isEmpty { ask += "\nFirst the `CHARACTER:` line." }
        if !missing.isEmpty {
            ask += "\nThen ONLY the missing numbered lines \(missing.map(String.init).joined(separator: ", "))."
        }
        ask += "\n\n\(originalPrompt)\n\n\(filled)"

        let repaired = try await completer.complete(ask)
        let extra = IllustrationPromptParser.parsePartial(repaired)
        var merged = partial
        if merged.descriptor.isEmpty { merged.descriptor = extra.descriptor }
        for (index, line) in extra.lines where (merged.lines[index] ?? "").isEmpty {
            merged.lines[index] = line
        }
        return try IllustrationPromptParser.validate(merged)
    }
}
