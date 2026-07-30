import Foundation
import VovoUI

/// Loads on-disk **VLM prompt** Markdown (`describe.<lang>.md`).
/// These files are **instructions for the model**, not captions.
public enum PhotoDescribeTemplate: Sendable {
    public static var sourcePromptsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    /// Loads `describe.<lang>.md` (falls back to en-US).
    public static func filledDescribePrompt(language: AppLanguage) -> String {
        let path = "Prompts/describe.\(language.rawValue).md"
        let fallback = "Prompts/describe.\(AppLanguage.englishUS.rawValue).md"
        var raw = MarkdownTextCatalog.loadFile(
            path,
            bundle: .module,
            sourceFallbackRoot: sourcePromptsRoot
        )
        if raw.isEmpty {
            raw = MarkdownTextCatalog.loadFile(
                fallback,
                bundle: .module,
                sourceFallbackRoot: sourcePromptsRoot
            )
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
