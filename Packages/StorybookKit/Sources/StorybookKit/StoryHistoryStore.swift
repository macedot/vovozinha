import Foundation

/// Persists story metadata alongside the page PNGs in the user-visible Documents container.
public struct StoryHistoryStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? Self.defaultDocumentsRoot()
    }

    public func historyURL() -> URL {
        rootURL
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Stories", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public func load() throws -> [Storybook] {
        let url = historyURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Storybook].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func upsert(_ story: Storybook) throws {
        var stories = try load()
        if let index = stories.firstIndex(where: { $0.id == story.id }) {
            stories[index] = story
        } else {
            stories.append(story)
        }
        try save(stories)
    }

    public func delete(_ story: Storybook) throws {
        let files = StoryFileStore(rootURL: rootURL)
        try files.removeStory(id: story.id)
        try save(try load().filter { $0.id != story.id })
    }

    private func save(_ stories: [Storybook]) throws {
        let url = historyURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.sorted.encode(
            stories.sorted { $0.createdAt > $1.createdAt }
        )
        try data.write(to: url, options: .atomic)
    }

    private static func defaultDocumentsRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
