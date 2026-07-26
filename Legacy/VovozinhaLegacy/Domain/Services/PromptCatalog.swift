import Foundation
import os

private let promptLog = Logger(subsystem: "app.vovozinha", category: "PromptCatalog")

/// Loads static prompt templates from the app bundle (`Resources/Prompts/...`).
///
/// Templates use `{{placeholder}}` tokens filled by `render(_:vars:)`.
enum PromptCatalog {
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    /// Bundle-relative path under `Prompts/`, e.g. `story/system_instructions.txt`.
    static func load(_ relativePath: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[relativePath] { return hit }

        let text = loadFromBundle(relativePath)
            ?? loadFromSourceTreeFallback(relativePath)
        if let text {
            let normalized = normalizeWhitespaceIfNeeded(text, path: relativePath)
            cache[relativePath] = normalized
            return normalized
        }

        promptLog.error("Missing prompt template: \(relativePath, privacy: .public)")
        // Last resort so generate does not crash; empty string fails loudly in tests.
        cache[relativePath] = ""
        return ""
    }

    /// Replace `{{key}}` with `vars[key]` (missing keys → empty string).
    /// - Parameter collapseWhitespace: set true for single-line image prompts.
    static func render(
        _ template: String,
        vars: [String: String],
        collapseWhitespace: Bool = false
    ) -> String {
        var out = template
        for (key, value) in vars {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        // Strip any leftover tokens.
        if out.contains("{{") {
            out = out.replacingOccurrences(
                of: #"\{\{[^}]+\}\}"#,
                with: "",
                options: .regularExpression
            )
        }
        if collapseWhitespace {
            out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Load + render in one step.
    static func text(
        _ relativePath: String,
        vars: [String: String] = [:],
        collapseWhitespace: Bool = false
    ) -> String {
        let raw = load(relativePath)
        guard !vars.isEmpty else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return render(raw, vars: vars, collapseWhitespace: collapseWhitespace)
    }

    static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - Bundle / disk

    private static func loadFromBundle(_ relativePath: String) -> String? {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard let fileName = parts.last else { return nil }
        let nameParts = fileName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let ext: String
        let baseName: String
        if nameParts.count >= 2 {
            ext = nameParts.last ?? "txt"
            baseName = nameParts.dropLast().joined(separator: ".")
        } else {
            ext = "txt"
            baseName = fileName
        }
        let subdir: String
        if parts.count > 1 {
            subdir = "Prompts/" + parts.dropLast().joined(separator: "/")
        } else {
            subdir = "Prompts"
        }

        if let url = Bundle.main.url(forResource: baseName, withExtension: ext, subdirectory: subdir) {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        // Absolute path inside bundle (folder reference).
        let direct = Bundle.main.bundleURL.appendingPathComponent("Prompts/\(relativePath)")
        if let text = try? String(contentsOf: direct, encoding: .utf8) {
            return text
        }
        return nil
    }

    /// Unit tests / Xcode previews may not copy resources; allow repo path when running from source.
    private static func loadFromSourceTreeFallback(_ relativePath: String) -> String? {
        let candidates = [
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Prompts/\(relativePath)"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Services
                .deletingLastPathComponent() // Domain
                .deletingLastPathComponent() // Vovozinha
                .appendingPathComponent("Resources/Prompts/\(relativePath)")
        ]
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                promptLog.debug("Loaded prompt from disk fallback: \(url.path, privacy: .public)")
                return text
            }
        }
        return nil
    }

    private static func normalizeWhitespaceIfNeeded(_ text: String, path: String) -> String {
        // Keep multi-line structure for story instructions; collapse art one-liners lightly.
        if path.hasPrefix("art/") && !path.contains("page.") {
            return text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
