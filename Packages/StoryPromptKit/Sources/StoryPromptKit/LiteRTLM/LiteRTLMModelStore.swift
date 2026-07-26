import Foundation

/// Owns the on-device LiteRT-LM model file and its one-time download.
///
/// **Hard rule:** generation is never networked. The network is used *only* here, to fetch
/// the model asset once; everything else runs locally. Once `isModelPresent` is true the
/// app is fully offline.
///
/// The model lives at `<Documents >/Vovozinha/Models/gemma-3n-E2B-it-int4.litertlm`.
public actor LiteRTLMModelStore {
    /// Default Hugging Face source for the Gemma 3n E2B int4 LiteRT-LM model (~3.66 GB).
    public static let defaultSourceURL = URL(string:
        "https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm"
    )!

    public static let defaultModelFilename = "gemma-3n-E2B-it-int4.litertlm"

    private let modelURL: URL
    private let sourceURL: URL
    private let session: URLSession

    /// - Parameters:
    ///   - documentsURL: Container whose `Vovozinha/Models/` subdir holds the model.
    ///                   Defaults to the app's real `Documents` directory.
    ///   - sourceURL: Where to download the model from. Tests can point this elsewhere.
    ///   - session: Injectable for tests (e.g. `URLProtocol`-backed).
    public init(
        documentsURL: URL? = nil,
        sourceURL: URL = LiteRTLMModelStore.defaultSourceURL,
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

    /// Filesystem location of the (possibly not-yet-downloaded) model file.
    public func modelFileURL() -> URL { modelURL }

    /// Writable directory the LiteRT-LM engine may use for the compiled-model cache.
    public func cacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? modelURL.deletingLastPathComponent()
        return caches.appendingPathComponent("LiteRTLM", isDirectory: true)
    }

    /// `true` when a non-empty model file is present at `modelFileURL()`.
    public func isModelPresent() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attrs[.size] as? NSNumber else { return false }
        return size.intValue > 0
    }

    /// Downloads the model into a temp file, then moves it atomically into place.
    ///
    /// - Parameter progress: Called on the main actor with `0.0...1.0` as bytes arrive.
    ///                       Pass `nil` to skip progress callbacks.
    public func download(progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws {
        try FileManager.default.createDirectory(
            at: modelURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let (asyncBytes, response) = try await session.bytes(from: sourceURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let expected = http.expectedContentLength
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temp)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1 << 16) // 64 KB

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                received &+= Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if let progress, expected > 0 {
                    await progress(Double(received) / Double(expected))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received &+= Int64(buffer.count)
            if let progress { await progress(expected > 0 ? Double(received) / Double(expected) : 1.0) }
        }

        // Atomic move into place; replace any partial file from a prior failed run.
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
        try FileManager.default.moveItem(at: temp, to: modelURL)
    }

    /// Removes the downloaded model (e.g. for a DEBUG "re-download" control).
    public func removeModel() throws {
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
    }

    private static func defaultDocumentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}
