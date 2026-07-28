import Foundation
import CryptoKit
import zlib

/// Owns the on-device **Qwen3.5-4B-MLX-4bit** MLX model directory.
///
/// **Generation is offline.** Networking is only used to **download** a zip once from our
/// host (`files.kraftek.dev`). If that fails, the UI can open Hugging Face as a manual
/// fallback and the user **imports** a zip or unpacked folder. Sandbox path:
/// `<Documents>/Vovozinha/Models/Qwen3.5-4B-MLX-4bit/`.
///
/// Host downloads are integrity-checked with a pinned SHA-256. Manual Import / HF browser
/// paths are not (external sources are not our responsibility).
public actor OnDeviceMLXModelStore {
    /// Automatic in-app download (zip of MLX weights + tokenizer).
    public static let defaultHostDownloadURL = URL(string:
        "https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip"
    )!

    /// Manual browser fallback when automatic download fails.
    public static let defaultHostFallbackPageURL = URL(string:
        "https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit"
    )!

    /// Directory name under `Vovozinha/Models/`.
    public static let defaultModelDirectoryName = "Qwen3.5-4B-MLX-4bit"

    /// Zip filename expected for Downloads auto-import.
    public static let defaultZipFilename = "Qwen3.5-4B-MLX-4bit.zip"

    /// Lowercase hex SHA-256 of the CDN zip produced by `scripts/package_qwen35_4b_mlx_zip.sh`.
    /// Update whenever the hosted pack is rebuilt.
    public static let defaultHostZipSHA256 =
        "8b788dc7ca49b3527228159132a810106004218242652e71a13d1bdee8d8cebb"

    private let modelDirectoryURL: URL
    private let sourceURL: URL
    private let session: URLSession
    /// When non-nil, `download` verifies the zip against this hex SHA-256 (host path only).
    private let expectedHostZipSHA256: String?

    public enum DownloadError: Error, LocalizedError, Equatable {
        case http(statusCode: Int)
        case emptyFile
        case unzipFailed
        case checksumMismatch

        public var errorDescription: String? {
            switch self {
            case .http(let code):
                return "Model download failed (HTTP \(code)). Try again on Wi‑Fi, or open the backup download page."
            case .emptyFile:
                return "Model download finished but the file is empty."
            case .unzipFailed:
                return "Could not unpack the model archive. Try Import from Files."
            case .checksumMismatch:
                return "Model download failed integrity check. Try again on Wi‑Fi, or open the backup download page."
            }
        }
    }

    public enum ImportError: Error, LocalizedError, Equatable {
        case unreadableSource
        case emptyFile
        case copyFailed
        case missingConfig
        case unzipFailed

        public var errorDescription: String? {
            switch self {
            case .unreadableSource:
                return "Could not read the selected model file or folder."
            case .emptyFile:
                return "The selected file is empty."
            case .copyFailed:
                return "Could not copy the model into the app. Try again."
            case .missingConfig:
                return "Model pack is incomplete (need config.json and weights). Import the full Qwen3.5 MLX folder or zip."
            case .unzipFailed:
                return "Could not unpack the model archive."
            }
        }
    }

    /// - Parameters:
    ///   - documentsURL: Container whose `Vovozinha/Models/` holds the model directory.
    ///   - sourceURL: Automatic download URL (defaults to kraftek host zip).
    ///   - expectedHostZipSHA256: Hex SHA-256 required for host `download` (default: pinned CDN pack).
    ///     Pass `nil` only in tests that skip integrity checks.
    ///   - session: Injectable for tests.
    public init(
        documentsURL: URL? = nil,
        sourceURL: URL = OnDeviceMLXModelStore.defaultHostDownloadURL,
        expectedHostZipSHA256: String? = OnDeviceMLXModelStore.defaultHostZipSHA256,
        session: URLSession = .shared
    ) {
        let docs = documentsURL ?? OnDeviceMLXModelStore.defaultDocumentsURL()
        self.modelDirectoryURL = docs
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Self.defaultModelDirectoryName, isDirectory: true)
        self.sourceURL = sourceURL
        self.expectedHostZipSHA256 = expectedHostZipSHA256
        self.session = session
    }

    public func modelDirectory() -> URL { modelDirectoryURL }

    public func isModelPresent() -> Bool {
        Self.directoryLooksLikeMLXPack(modelDirectoryURL)
    }

    /// Downloads the model zip from our host, unpacks into the app sandbox (with progress).
    public func download(progress: (@MainActor @Sendable (Double) -> Void)? = nil) async throws {
        try FileManager.default.createDirectory(
            at: modelDirectoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: sourceURL)
        request.setValue("Vovozinha/1.0 (iOS; Qwen3.5 MLX model fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.http(statusCode: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.http(statusCode: http.statusCode)
        }

        let expected = http.expectedContentLength
        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: tempZip.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempZip)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                received &+= Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if let progress, expected > 0 {
                    await progress(min(Double(received) / Double(expected) * 0.95, 0.95))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received &+= Int64(buffer.count)
        }

        guard received > 0 else {
            try? FileManager.default.removeItem(at: tempZip)
            throw DownloadError.emptyFile
        }

        // Integrity check only for host auto-download (not Import / external sources).
        if let expected = expectedHostZipSHA256 {
            do {
                try Self.verifySHA256(ofFileAt: tempZip, expectedHex: expected)
            } catch {
                try? FileManager.default.removeItem(at: tempZip)
                throw error
            }
        }

        do {
            try Self.installPack(fromZip: tempZip, to: modelDirectoryURL)
            try? FileManager.default.removeItem(at: tempZip)
        } catch {
            try? FileManager.default.removeItem(at: tempZip)
            throw DownloadError.unzipFailed
        }

        guard isModelPresent() else { throw DownloadError.unzipFailed }
        if let progress { await progress(1.0) }
    }

    /// Imports a user-provided **zip** or **folder** into the app model directory.
    /// No SHA-256 check — external / user-provided packs are not our responsibility.
    public func importModel(from sourceURL: URL) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir)
        guard exists else { throw ImportError.unreadableSource }

        if isDir.boolValue {
            guard Self.directoryLooksLikeMLXPack(sourceURL) else {
                throw ImportError.missingConfig
            }
            try Self.replaceDirectory(at: modelDirectoryURL, withContentsOf: sourceURL)
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            if size <= 0 { throw ImportError.emptyFile }

            let ext = sourceURL.pathExtension.lowercased()
            if ext == "zip" {
                do {
                    try Self.installPack(fromZip: sourceURL, to: modelDirectoryURL)
                } catch {
                    throw ImportError.unzipFailed
                }
            } else {
                throw ImportError.missingConfig
            }
        }

        guard isModelPresent() else { throw ImportError.copyFailed }
    }

    @discardableResult
    public func tryImportFromDownloadsDirectory() throws -> Bool {
        for dir in Self.downloadsCandidateURLs() {
            let zip = dir.appendingPathComponent(Self.defaultZipFilename)
            if FileManager.default.fileExists(atPath: zip.path) {
                try importModel(from: zip)
                return true
            }
            let folder = dir.appendingPathComponent(Self.defaultModelDirectoryName, isDirectory: true)
            if Self.directoryLooksLikeMLXPack(folder) {
                try importModel(from: folder)
                return true
            }
        }
        return false
    }

    public func removeModel() throws {
        if FileManager.default.fileExists(atPath: modelDirectoryURL.path) {
            try FileManager.default.removeItem(at: modelDirectoryURL)
        }
    }

    // MARK: - Host integrity

    /// SHA-256 (lowercase hex) of the file at `url`. Used for host CDN downloads only.
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) // 1 MB
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verifySHA256(ofFileAt url: URL, expectedHex: String) throws {
        let actual = try sha256Hex(ofFileAt: url)
        let expected = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard actual == expected else {
            throw DownloadError.checksumMismatch
        }
    }

    // MARK: - Pack helpers

    static func directoryLooksLikeMLXPack(_ url: URL) -> Bool {
        let fm = FileManager.default
        let config = url.appendingPathComponent("config.json")
        guard fm.fileExists(atPath: config.path) else { return false }

        let single = url.appendingPathComponent("model.safetensors")
        if let attrs = try? fm.attributesOfItem(atPath: single.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > 0 {
            return true
        }
        let index = url.appendingPathComponent("model.safetensors.index.json")
        if fm.fileExists(atPath: index.path),
           let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for item in items where item.pathExtension == "safetensors" {
                let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 { return true }
            }
        }
        return false
    }

    static func installPack(fromZip zipURL: URL, to destination: URL) throws {
        let fm = FileManager.default
        let extractRoot = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: extractRoot) }

        try unzipItem(at: zipURL, to: extractRoot)
        let packRoot = try findMLXPackRoot(in: extractRoot)
        try replaceDirectory(at: destination, withContentsOf: packRoot)
    }

    static func findMLXPackRoot(in extractRoot: URL) throws -> URL {
        if directoryLooksLikeMLXPack(extractRoot) { return extractRoot }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: extractRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir),
               isDir.boolValue,
               directoryLooksLikeMLXPack(child) {
                return child
            }
        }
        throw ImportError.missingConfig
    }

    static func replaceDirectory(at destination: URL, withContentsOf source: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    static func unzipItem(at zipURL: URL, to destination: URL) throws {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ImportError.unzipFailed
        }
        #else
        try SimpleZip.extract(zipURL: zipURL, to: destination)
        #endif
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

// MARK: - Minimal ZIP reader (store + deflate)

enum SimpleZip {
    static func extract(zipURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: zipURL, options: [.mappedIfSafe])
        guard data.count >= 22 else { throw OnDeviceMLXModelStore.ImportError.unzipFailed }

        var offset = 0
        while offset + 30 <= data.count {
            let sig = readUInt32(data, offset)
            if sig == 0x02014b50 || sig == 0x06054b50 { break }
            guard sig == 0x04034b50 else { throw OnDeviceMLXModelStore.ImportError.unzipFailed }

            let method = Int(readUInt16(data, offset + 8))
            let flags = Int(readUInt16(data, offset + 6))
            let compSizeField = Int(readUInt32(data, offset + 18))
            let uncompSize = Int(readUInt32(data, offset + 22))
            let nameLen = Int(readUInt16(data, offset + 26))
            let extraLen = Int(readUInt16(data, offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd + extraLen <= data.count else {
                throw OnDeviceMLXModelStore.ImportError.unzipFailed
            }

            let nameData = data.subdata(in: nameStart..<nameEnd)
            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else {
                throw OnDeviceMLXModelStore.ImportError.unzipFailed
            }

            let dataStart = nameEnd + extraLen
            let compSize = compSizeField

            // Data descriptor (bit 3): sizes follow the payload; we cannot stream easily — fail.
            if flags & 0x8 != 0 {
                throw OnDeviceMLXModelStore.ImportError.unzipFailed
            }

            let dataEnd = dataStart + compSize
            guard dataEnd <= data.count else { throw OnDeviceMLXModelStore.ImportError.unzipFailed }
            let payload = data.subdata(in: dataStart..<dataEnd)
            offset = dataEnd

            if name.hasSuffix("/") { continue }

            let outURL = destination.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let bytes: Data
            switch method {
            case 0:
                bytes = payload
            case 8:
                bytes = try inflateDeflate(
                    payload,
                    expectedSize: uncompSize > 0 ? uncompSize : payload.count * 4
                )
            default:
                throw OnDeviceMLXModelStore.ImportError.unzipFailed
            }
            try bytes.write(to: outURL, options: .atomic)
        }
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func inflateDeflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        var status = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else { throw OnDeviceMLXModelStore.ImportError.unzipFailed }
        defer { _ = inflateEnd(&stream) }

        var output = [UInt8](repeating: 0, count: max(expectedSize, 64 * 1024))
        var outCount = 0

        try compressed.withUnsafeBytes { srcBuf in
            guard let src = srcBuf.bindMemory(to: Bytef.self).baseAddress else {
                throw OnDeviceMLXModelStore.ImportError.unzipFailed
            }
            stream.next_in = UnsafeMutablePointer(mutating: src)
            stream.avail_in = uInt(compressed.count)

            while true {
                if outCount >= output.count {
                    output.append(contentsOf: [UInt8](repeating: 0, count: output.count))
                }
                let remaining = output.count - outCount
                try output.withUnsafeMutableBytes { dstBuf in
                    guard let dst = dstBuf.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                        throw OnDeviceMLXModelStore.ImportError.unzipFailed
                    }
                    stream.next_out = dst.advanced(by: outCount)
                    stream.avail_out = uInt(remaining)
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                }
                outCount = Int(stream.total_out)
                if status == Z_STREAM_END { break }
                if status != Z_OK { throw OnDeviceMLXModelStore.ImportError.unzipFailed }
            }
        }

        return Data(output.prefix(outCount))
    }
}
