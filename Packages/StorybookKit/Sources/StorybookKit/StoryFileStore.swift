import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Persists page PNGs and the cartoon reference as relative files.
public struct StoryFileStore: Sendable {
    public let rootURL: URL
    public static let referenceFileName = "reference.png"

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func storyDirectory(id: UUID) -> URL {
        rootURL
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Stories", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func pageFileName(index: Int) -> String { "page-\(index).png" }

    public func ensureStoryDirectory(id: UUID) throws -> URL {
        let dir = storyDirectory(id: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func pngExists(id: UUID, fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: storyDirectory(id: id).appendingPathComponent(fileName).path)
    }

#if canImport(CoreGraphics) && canImport(ImageIO)
    @discardableResult
    public func writePNG(_ image: CGImage, id: UUID, fileName: String) throws -> URL {
        let dir = try ensureStoryDirectory(id: id)
        let url = dir.appendingPathComponent(fileName)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageWriteError.failed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ImageWriteError.failed }
        return url
    }
#endif

    public enum ImageWriteError: Error { case failed }
}
