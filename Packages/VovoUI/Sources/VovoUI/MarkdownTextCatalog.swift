import Foundation

/// Loads static copy from Markdown files in a package or app bundle.
///
/// ## File format
///
/// ```markdown
/// # Optional title
///
/// ## keyName
/// Body text. Supports {{placeholders}}.
///
/// ## anotherKey
/// More text.
/// ```
///
/// Sections are `## key` headers. Body runs until the next `##` (or EOF).
/// Trailing whitespace is trimmed. `{{name}}` tokens are filled by `render`.
public enum MarkdownTextCatalog: Sendable {
    private static let lock = NSLock()
    /// Cache key: "bundleId|relativePath". Guarded by `lock`.
    nonisolated(unsafe) private static var fileCache: [String: String] = [:]
    /// Cache key: "bundleId|relativePath|sectionKey". Guarded by `lock`.
    nonisolated(unsafe) private static var sectionCache: [String: String] = [:]

    // MARK: - Public API

    /// Load a whole Markdown file (raw text).
    public static func loadFile(
        _ relativePath: String,
        bundle: Bundle,
        sourceFallbackRoot: URL? = nil
    ) -> String {
        let cacheKey = "\(bundle.bundleIdentifier ?? bundle.bundlePath)|\(relativePath)"
        lock.lock()
        if let hit = fileCache[cacheKey] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let text = readFromBundle(relativePath, bundle: bundle)
            ?? sourceFallbackRoot.flatMap { readFromDisk(root: $0, relativePath: relativePath) }
            ?? ""

        lock.lock()
        fileCache[cacheKey] = text
        lock.unlock()
        return text
    }

    /// Load one `## section` from a Markdown file.
    public static func section(
        _ key: String,
        from relativePath: String,
        bundle: Bundle,
        sourceFallbackRoot: URL? = nil
    ) -> String {
        let cacheKey = "\(bundle.bundleIdentifier ?? bundle.bundlePath)|\(relativePath)|\(key)"
        lock.lock()
        if let hit = sectionCache[cacheKey] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let file = loadFile(relativePath, bundle: bundle, sourceFallbackRoot: sourceFallbackRoot)
        let body = parseSections(file)[key] ?? ""

        lock.lock()
        sectionCache[cacheKey] = body
        lock.unlock()
        return body
    }

    /// Load + substitute `{{vars}}`.
    public static func text(
        _ key: String,
        from relativePath: String,
        bundle: Bundle,
        vars: [String: String] = [:],
        sourceFallbackRoot: URL? = nil
    ) -> String {
        let raw = section(key, from: relativePath, bundle: bundle, sourceFallbackRoot: sourceFallbackRoot)
        guard !vars.isEmpty else { return raw }
        return render(raw, vars: vars)
    }

    /// Replace `{{key}}` with values (missing keys → empty).
    public static func render(_ template: String, vars: [String: String]) -> String {
        var out = template
        for (key, value) in vars {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        if out.contains("{{") {
            out = out.replacingOccurrences(
                of: #"\{\{[^}]+\}\}"#,
                with: "",
                options: .regularExpression
            )
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse all `## key` sections from Markdown.
    public static func parseSections(_ markdown: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        var buffer: [String] = []

        func flush() {
            guard let key = currentKey else {
                buffer.removeAll()
                return
            }
            let body = buffer
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = body
            buffer.removeAll()
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.hasPrefix("## ") {
                flush()
                let key = raw.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                currentKey = key.isEmpty ? nil : key
                continue
            }
            // Skip top-level title / prose outside sections.
            if currentKey == nil { continue }
            buffer.append(raw)
        }
        flush()
        return result
    }

    public static func clearCache() {
        lock.lock()
        fileCache.removeAll()
        sectionCache.removeAll()
        lock.unlock()
    }

    // MARK: - IO

    private static func readFromBundle(_ relativePath: String, bundle: Bundle) -> String? {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard let fileName = parts.last else { return nil }

        let nameParts = fileName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let ext: String
        let baseName: String
        if nameParts.count >= 2 {
            ext = nameParts.last ?? "md"
            baseName = nameParts.dropLast().joined(separator: ".")
        } else {
            ext = "md"
            baseName = fileName
        }

        let subdir: String? = parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil

        // Prefer nested path (source layout); SPM `.process` often flattens to resource root.
        let subdirs: [String?] = [subdir, nil].reduce(into: [String?]()) { acc, s in
            if !acc.contains(where: { $0 == s }) { acc.append(s) }
        }
        for dir in subdirs {
            if let url = bundle.url(forResource: baseName, withExtension: ext, subdirectory: dir) {
                if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                    return text
                }
            }
        }
        if let root = bundle.resourceURL {
            for candidate in [
                root.appendingPathComponent(relativePath),
                root.appendingPathComponent(fileName)
            ] {
                if let text = try? String(contentsOf: candidate, encoding: .utf8), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private static func readFromDisk(root: URL, relativePath: String) -> String? {
        let fileName = (relativePath as NSString).lastPathComponent
        for candidate in [
            root.appendingPathComponent(relativePath),
            root.appendingPathComponent(fileName),
            // Nested source layout: Resources/Strings/… or Resources/Prompts/…
            root.appendingPathComponent(relativePath)
        ] {
            if let text = try? String(contentsOf: candidate, encoding: .utf8), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
