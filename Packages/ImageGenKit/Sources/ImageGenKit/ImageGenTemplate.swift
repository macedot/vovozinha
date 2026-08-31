import Foundation
import VovoUI

/// Loads on-disk **img2img prompt scaffolds** (`img2img.<lang>.md`).
///
/// Each prompt file has two `## key` sections:
/// - `## positive` — a locale-appropriate style prefix appended before the user's free-text
///   prompt (keeps output kid-friendly and anime-styled).
/// - `## negative` — the locked kids/anti-photoreal negative prompt (the same across the
///   feature; the file is the single source of truth).
///
/// These are **instructions for the model**, not user-facing copy.
public enum ImageGenTemplate: Sendable {
    public static var sourcePromptsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    /// The locked kids/anti-photoreal negative (loaded once, cached). Used when the caller
    /// does not supply a custom negative prompt.
    public static let defaultNegativePrompt: String = {
        negative(for: .englishUS)
    }()

    /// Positive style scaffold for `language` (falls back to en-US).
    public static func positive(for language: AppLanguage) -> String {
        section("positive", language: language)
    }

    /// Locked negative prompt for `language` (falls back to en-US; content is locale-stable).
    public static func negative(for language: AppLanguage) -> String {
        section("negative", language: language)
    }

    private static func section(_ key: String, language: AppLanguage) -> String {
        let path = "Prompts/img2img.\(language.rawValue).md"
        let fallback = "Prompts/img2img.\(AppLanguage.englishUS.rawValue).md"
        var body = MarkdownTextCatalog.section(
            key, from: path, bundle: .module, sourceFallbackRoot: sourcePromptsRoot
        )
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = MarkdownTextCatalog.section(
                key, from: fallback, bundle: .module, sourceFallbackRoot: sourcePromptsRoot
            )
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
