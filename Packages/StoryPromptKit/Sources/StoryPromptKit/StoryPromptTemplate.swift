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

    /// Repo / package `Resources` root for source-tree fallback when the bundle omits files.
    public static var sourcePromptsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
    }

    /// Loads `story.<lang>.md` (falls back to en-US) and substitutes the description.
    public static func filledStoryPrompt(description: String, language: AppLanguage) -> String {
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
        return replaceDescriptionPlaceholders(in: raw, with: description)
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
