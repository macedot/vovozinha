import Foundation

/// Where **user-facing story exports** (PDF, share files) are written.
///
/// - **Default:** `Documents/Vovozinha/Exports/` (visible in the Files app so parents can
///   find and share stories).
/// - **Custom:** security-scoped bookmark chosen by the user (Settings later).
///
/// Model packs do **not** use this — they live under private Application Support.
public enum StoryExportLocationStore: Sendable {
    public static let bookmarkDefaultsKey = "vovozinha.storyExportDirectoryBookmark"

    /// Default export folder under the app’s Documents container.
    public static func defaultDocumentsExportDirectory() -> URL {
        let docs =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
    }

    /// Resolved directory for writing exports. Creates the default folder when needed.
    ///
    /// If a custom bookmark is set and still valid, that URL is returned (caller must
    /// `startAccessingSecurityScopedResource` for the session when using a custom folder).
    public static func resolvedExportDirectory(
        userDefaults: UserDefaults = .standard
    ) -> (url: URL, isSecurityScoped: Bool) {
        if let data = userDefaults.data(forKey: bookmarkDefaultsKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale {
                return (url, true)
            }
            // Stale / unreadable bookmark — fall back to default.
            userDefaults.removeObject(forKey: bookmarkDefaultsKey)
        }

        let url = defaultDocumentsExportDirectory()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (url, false)
    }

    /// Persist a user-chosen folder (security-scoped bookmark). Pass `nil` to reset to Documents.
    public static func setCustomExportDirectory(
        _ url: URL?,
        userDefaults: UserDefaults = .standard
    ) throws {
        guard let url else {
            userDefaults.removeObject(forKey: bookmarkDefaultsKey)
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let data = try url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        userDefaults.set(data, forKey: bookmarkDefaultsKey)
    }

    public static func hasCustomExportDirectory(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.data(forKey: bookmarkDefaultsKey) != nil
    }
}
