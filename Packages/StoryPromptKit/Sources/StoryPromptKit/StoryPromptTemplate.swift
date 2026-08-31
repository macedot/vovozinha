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

    public static let photoCaptionPlaceholders: [String] = [
        "[INSERT PHOTO CAPTION HERE]",
        "[INSERIR A LEGENDA DA FOTO AQUI]",
        "[INSERTAR EL PIE DE FOTO AQUÍ]",
        "{{caption}}",
        "{{photo}}"
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
        photoCaption: String? = nil,
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
        raw = applyPhotoCaption(raw, photoCaption)
        return replaceDescriptionPlaceholders(in: raw, with: description)
    }

    /// Loads `illustration.<lang>.md` and fills title, paragraphs, optional caption.
    public static func filledIllustrationPrompt(
        title: String,
        paragraphs: [String],
        photoCaption: String?,
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
        let caption = photoCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        raw = replaceTokens(photoCaptionPlaceholders, in: raw, with: caption.isEmpty ? "(none)" : caption)
        raw = raw.replacingOccurrences(of: "[INSERT STORY TITLE HERE]", with: title)
        let body = paragraphs.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n")
        raw = raw.replacingOccurrences(of: "[INSERT STORY PARAGRAPHS HERE]", with: body)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyPhotoCaption(_ template: String, _ caption: String?) -> String {
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            var out = template
            if let regex = try? NSRegularExpression(
                pattern: #"(?ms)^Photo elements[^\n]*\n.*?\n\n"#,
                options: []
            ) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
            }
            return replaceTokens(photoCaptionPlaceholders, in: out, with: "")
        }
        return replaceTokens(photoCaptionPlaceholders, in: template, with: trimmed)
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
