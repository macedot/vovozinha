import Foundation
import StoryPromptKit
import VovoUI

/// One Qwen pass → CHARACTER/ALSO/SETTING/PROPS story bible. Never fabricates a
/// CHARACTER lock: a still-missing lock after the repair pass throws.
public struct DeviceStoryBibleGenerator: StoryBibleGenerating {
    private let completer: any IllustrationPromptCompleting
    private let language: AppLanguage

    public init(
        completer: (any IllustrationPromptCompleting)? = nil,
        language: AppLanguage = .englishUS
    ) {
        self.completer = completer ?? DeviceCompleterAdapter(DevicePromptCompleter())
        self.language = language
    }

    public func generate(description: String, photoTags: String?) async throws -> StoryBible {
        let filled = StoryPromptTemplate.filledBiblePrompt(
            description: description,
            photoTags: photoTags,
            language: language
        )
        // Chat session is shared with story writing. Repeat the list format here so
        // Qwen cannot fall back to TITLE:/SUMMARY:/paragraphs.
        let prompt = """
        Output ONLY the four tagged lines (English). No TITLE, SUMMARY, or story.

        \(filled)
        """
        // First attempt, then ONE repair pass asking only for the missing lock.
        let raw = try await completer.complete(prompt)
        do {
            return try StoryBibleParser.parse(raw)
        } catch {
            let ask = """
            Output ONLY in English, same format as before. First the `CHARACTER:` line.

            \(prompt)
            """
            let repaired = try await completer.complete(ask)
            let partial = StoryBibleParser.parsePartial(raw)
            let extra = StoryBibleParser.parsePartial(repaired)
            var merged = partial
            if merged.characterLock.isEmpty { merged.characterLock = extra.characterLock }
            if merged.supporting.isEmpty { merged.supporting = extra.supporting }
            if merged.setting.isEmpty { merged.setting = extra.setting }
            if merged.props.isEmpty { merged.props = extra.props }
            return try StoryBibleParser.validate(merged)
        }
    }
}
