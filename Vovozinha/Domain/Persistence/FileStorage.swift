import Foundation
import UIKit

final class FileStorage: @unchecked Sendable {
    static let shared = FileStorage()

    private let fm = FileManager.default
    private let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.root = base.appendingPathComponent("Vovozinha", isDirectory: true)
        }
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func storyDirectory(storyID: UUID) -> URL {
        let dir = root.appendingPathComponent(storyID.uuidString, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func relativePath(storyID: UUID, fileName: String) -> String {
        "\(storyID.uuidString)/\(fileName)"
    }

    func absoluteURL(relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    @discardableResult
    func saveImage(_ image: UIImage, storyID: UUID, fileName: String) throws -> String {
        let relative = relativePath(storyID: storyID, fileName: fileName)
        let url = absoluteURL(relativePath: relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            throw StorageError.encodeFailed
        }
        try data.write(to: url, options: .atomic)
        return relative
    }

    func loadImage(relativePath: String) -> UIImage? {
        let url = absoluteURL(relativePath: relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func savePDF(data: Data, storyID: UUID, fileName: String = "historia.pdf") throws -> URL {
        let relative = relativePath(storyID: storyID, fileName: fileName)
        let url = absoluteURL(relativePath: relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    func deleteStoryFiles(storyID: UUID) {
        let dir = storyDirectory(storyID: storyID)
        try? fm.removeItem(at: dir)
    }

    func approximateStorageBytes() -> Int64 {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    enum StorageError: LocalizedError {
        case encodeFailed

        var errorDescription: String? {
            "Não foi possível gravar a imagem."
        }
    }
}
