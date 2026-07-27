import Foundation

/// Owns the on-device LiteRT-LM model file.
///
/// **Generation is offline.** Networking is only used to **download** the model once from our
/// host (`files.kraftek.dev`). If that fails, the UI can open Hugging Face as a manual fallback
/// and the user **imports** the file. Sandbox path:
/// `<Documents>/Vovozinha/Models/gemma-4-E4B-it.litertlm`.
public actor LiteRTLMModelStore {
    /// Automatic in-app download (HTTPS — `http://` redirects here).
    public static let defaultHostDownloadURL = URL(string:
        "https://files.kraftek.dev/gemma4/gemma-4-E4B-it.litertlm"
    )!

    /// Manual browser fallback when automatic download fails.
    public static let defaultHostFallbackPageURL = URL(string:
        "https://huggingface.co/google/gemma-3n-E2B-it-litert-lm"
    )!

    public static let defaultModelFilename = "gemma-4-E4B-it.litertlm"

    private let modelURL: URL
    private let sourceURL: URL
    private let session: URLSession

    public enum DownloadError: Error, LocalizedError, Equatable {
        case http(statusCode: Int)
        case emptyFile

        public var errorDescription: String? {
            switch self {
            case .http(let code):
                return "Model download failed (HTTP \(code)). Try again on Wi‑Fi, or open the backup download page."
            case .emptyFile:
                return "Model download finished but the file is empty."
            }
        }
    }

    public enum ImportError: Error, LocalizedError, Equatable {
        case unreadableSource
        case emptyFile
        case copyFailed

        public var errorDescription: String? {
            switch self {
            case .unreadableSource:
                return "Could not read the selected model file."
            case .emptyFile:
                return "The selected file is empty."
            case .copyFailed:
                return "Could not copy the model into the app. Try again."
            }
        }
    }

    /// - Parameters:
    ///   - documentsURL: Container whose `Vovozinha/Models/` holds the model.
    ///   - sourceURL: Automatic download URL (defaults to kraftek host).
    ///   - session: Injectable for tests.
    public init(
        documentsURL: URL? = nil,
        sourceURL: URL = LiteRTLMModelStore.defaultHostDownloadURL,
        session: URLSession = .shared
    ) {
        let docs = documentsURL ?? LiteRTLMModelStore.defaultDocumentsURL()
        self.modelURL = docs
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Self.defaultModelFilename)
        self.sourceURL = sourceURL
        self.session = session
    }

    public func modelFileURL() -> URL { modelURL }

    public func cacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? modelURL.deletingLastPathComponent()
        return caches.appendingPathComponent("LiteRTLM", isDirectory: true)
    }

    public func isModelPresent() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attrs[.size] as? NSNumber else { return false }
        return size.intValue > 0
    }

    /// Downloads the model from our host into the app sandbox (with progress).
    public func download(progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws {
        try FileManager.default.createDirectory(
            at: modelURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: sourceURL)
        request.setValue("Vovozinha/1.0 (iOS; LiteRT-LM model fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.http(statusCode: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.http(statusCode: http.statusCode)
        }

        let expected = http.expectedContentLength
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temp)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1 << 20) // 1 MB

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                received &+= Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if let progress, expected > 0 {
                    await progress(min(Double(received) / Double(expected), 0.999))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received &+= Int64(buffer.count)
        }

        guard received > 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw DownloadError.emptyFile
        }

        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
        try FileManager.default.moveItem(at: temp, to: modelURL)
        if let progress { await progress(1.0) }
    }

    /// Copies a user-provided file into the app model path (manual import fallback).
    public func importModel(from sourceURL: URL) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.isReadableFile(atPath: sourceURL.path)
            || (try? Data(contentsOf: sourceURL, options: [.mappedIfSafe])) != nil
        else {
            throw ImportError.unreadableSource
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        if size <= 0 {
            let probe = try? Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            if probe == nil || probe?.isEmpty == true {
                throw ImportError.emptyFile
            }
        }

        try FileManager.default.createDirectory(
            at: modelURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: modelURL)
        } catch {
            let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            guard !data.isEmpty else { throw ImportError.emptyFile }
            try data.write(to: modelURL, options: .atomic)
        }

        guard isModelPresent() else { throw ImportError.copyFailed }
    }

    @discardableResult
    public func tryImportFromDownloadsDirectory() throws -> Bool {
        for dir in Self.downloadsCandidateURLs() {
            let file = dir.appendingPathComponent(Self.defaultModelFilename)
            if FileManager.default.fileExists(atPath: file.path) {
                try importModel(from: file)
                return true
            }
        }
        return false
    }

    public func removeModel() throws {
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
    }

    private static func downloadsCandidateURLs() -> [URL] {
        var urls: [URL] = []
        if let d = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            urls.append(d)
        }
        #if os(macOS)
        let homeDownloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        if FileManager.default.fileExists(atPath: homeDownloads.path) {
            urls.append(homeDownloads)
        }
        #endif
        return urls
    }

    private static func defaultDocumentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}
