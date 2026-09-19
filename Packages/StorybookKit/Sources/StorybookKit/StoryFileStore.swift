import Foundation

/// Persists storybook metadata as `story.json` under the user-visible Documents container.
public struct StoryFileStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func storyDirectory(id: UUID) -> URL {
        rootURL
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Stories", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: - Storybook metadata (story.json)

    public static let storybookFileName = "story.json"

    public func storybookFileURL(id: UUID) -> URL {
        storyDirectory(id: id).appendingPathComponent(Self.storybookFileName)
    }

    public func saveStorybook(_ book: Storybook) throws {
        let dir = try ensureStoryDirectory(id: book.id)
        let data = try JSONEncoder().encode(book)
        try data.write(to: dir.appendingPathComponent(Self.storybookFileName), options: [.atomic])
    }

    public func loadStorybook(id: UUID) -> Storybook? {
        guard let data = try? Data(contentsOf: storybookFileURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(Storybook.self, from: data)
    }

    /// All saved books, newest first. Entries without a readable `story.json`
    /// are skipped.
    public func loadAllStorybooks() -> [Storybook] {
        let storiesRoot = rootURL
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Stories", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: storiesRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
            .compactMap { entry in
                guard let id = UUID(uuidString: entry.lastPathComponent) else { return nil }
                return loadStorybook(id: id)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func deleteStory(id: UUID) throws {
        let directory = storyDirectory(id: id)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    public func ensureStoryDirectory(id: UUID) throws -> URL {
        let dir = storyDirectory(id: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
