import Foundation
import VovoUI

/// Loads on-disk **LLM prompt** Markdown (`story.<lang>.md`) and injects the parent's
/// short story description. These files are **instructions for the model**, not story bodies.
public enum StoryPromptTemplate: Sendable {
    public static let descriptionPlaceholders: [String] = [
        "[INSERT STORY DESCRIPTION HERE]",
        "[INSERIR A DESCRIÇÃO DA HISTÓRIA AQUI]",
        "[INSERTAR LA DESCRIPCIÓN DE LA HISTORIA AQUÍ]",
        "{{seed}}",
        "{{idea}}",
        "{{description}}"
    ]

    /// Tokens for the story/illustration "elements" slot: the story bible block,
    /// or (fallback) raw photo tags. Old caption tokens stay fillable for compat.
    public static let storyElementsPlaceholders: [String] = [
        "[INSERT STORY ELEMENTS HERE]",
        "[INSERIR OS ELEMENTOS DA HISTÓRIA AQUI]",
        "[INSERTAR LOS ELEMENTOS DE LA HISTORIA AQUÍ]",
        "[INSERT PHOTO CAPTION HERE]",
        "[INSERIR A LEGENDA DA FOTO AQUI]",
        "[INSERTAR EL PIE DE FOTO AQUÍ]",
        "{{caption}}",
        "{{photo}}"
    ]

    public static let photoTagsPlaceholders: [String] = [
        "[INSERT PHOTO TAGS HERE]",
        "{{tags}}"
    ]

    public static let storyBiblePlaceholders: [String] = [
        "[INSERT STORY BIBLE HERE]",
        "{{bible}}"
    ]

    /// Repo / package `Resources` root for source-tree fallback when the bundle omits files.
    public static var sourcePromptsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    /// Loads `story.<lang>.md` (falls back to en-US) and substitutes the description.
    public static func filledStoryPrompt(
        description: String,
        storyElements: String? = nil,
        language: AppLanguage
    ) -> String {
        let path = "Prompts/story.\(language.rawValue).md"
        let fallback = "Prompts/story.\(AppLanguage.englishUS.rawValue).md"
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
        raw = applyStoryElements(raw, storyElements)
        return replaceDescriptionPlaceholders(in: raw, with: description)
    }

    /// Loads `bible.<lang>.md` and fills the description + optional photo tags.
    public static func filledBiblePrompt(
        description: String,
        photoTags: String?,
        language: AppLanguage
    ) -> String {
        let path = "Prompts/bible.\(language.rawValue).md"
        let fallback = "Prompts/bible.\(AppLanguage.englishUS.rawValue).md"
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
        // Tags first: the description cleanup below rewrites any leftover
        // [INSERT …] bracket, so specific tokens must be resolved before it runs.
        let tags = photoTags?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        raw = replaceTokens(photoTagsPlaceholders, in: raw, with: tags.isEmpty ? "(none)" : tags)
        return replaceDescriptionPlaceholders(in: raw, with: description)
    }

    /// Loads `illustration.<lang>.md` and fills title, elements block, paragraphs.
    public static func filledIllustrationPrompt(
        title: String,
        paragraphs: [String],
        elementsBlock: String,
        language: AppLanguage
    ) -> String {
        let path = "Prompts/illustration.\(language.rawValue).md"
        let fallback = "Prompts/illustration.\(AppLanguage.englishUS.rawValue).md"
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
        let block = elementsBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = replaceTokens(storyBiblePlaceholders, in: raw, with: block.isEmpty ? "(none)" : block)
        raw = raw.replacingOccurrences(of: "[INSERT STORY TITLE HERE]", with: title)
        let body = paragraphs.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n")
        raw = raw.replacingOccurrences(of: "[INSERT STORY PARAGRAPHS HERE]", with: body)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyStoryElements(_ template: String, _ elements: String?) -> String {
        let trimmed = elements?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            var out = template
            if let regex = try? NSRegularExpression(
                pattern: #"(?ms)^Story elements[^\n]*\n.*?\n\n"#,
                options: []
            ) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
            }
            return replaceTokens(storyElementsPlaceholders, in: out, with: "")
        }
        return replaceTokens(storyElementsPlaceholders, in: template, with: trimmed)
    }

    static func replaceTokens(_ tokens: [String], in text: String, with value: String) -> String {
        var out = text
        for token in tokens {
            out = out.replacingOccurrences(of: token, with: value)
        }
        return out
    }

    public static func replaceDescriptionPlaceholders(in template: String, with description: String) -> String {
        var out = template
        for token in descriptionPlaceholders {
            out = out.replacingOccurrences(of: token, with: description)
        }
        if let regex = try? NSRegularExpression(
            pattern: #"\[(?:INSERT|INSERIR|INSERTAR)[^\]]*\]"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            let safe = NSRegularExpression.escapedTemplate(for: description)
            out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: safe)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func containsUnresolvedDescriptionPlaceholder(_ text: String) -> Bool {
        for token in descriptionPlaceholders where text.contains(token) {
            return true
        }
        return text.range(of: #"\[(?:INSERT|INSERIR|INSERTAR)[^\]]*\]"#, options: .regularExpression) != nil
    }
}
