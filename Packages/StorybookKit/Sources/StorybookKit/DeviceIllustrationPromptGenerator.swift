import Foundation
import StoryPromptKit
import VovoUI

/// One Qwen pass → CHARACTER lock + 10 English scene prompts. Never fabricates lines.
public struct DeviceIllustrationPromptGenerator: IllustrationPromptGenerating {
    private let completer: DevicePromptCompleter
    private let language: AppLanguage

    public init(
        completer: DevicePromptCompleter = DevicePromptCompleter(),
        language: AppLanguage = .englishUS
    ) {
        self.completer = completer
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
        var lastError: Error = IllustrationPromptError.emptyReply
        for _ in 0..<2 {
            let raw = try await completer.complete(prompt)
            do {
                return try IllustrationPromptParser.parse(raw)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
