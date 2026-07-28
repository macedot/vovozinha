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
/// Host downloads are integrity-checked by fetching a sidecar `.sha256` from our CDN
/// and comparing it to the zip. Manual Import / HF browser paths are not checked
/// (external sources are not our responsibility).
public actor OnDeviceMLXModelStore {
    /// Automatic in-app download (zip of MLX weights + tokenizer).
    public static let defaultHostDownloadURL = URL(string:
        "https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip"
    )!

    /// Sidecar checksum for the host zip (`*.zip.sha256`, shasum-style text).
    public static let defaultHostSHA256URL = URL(string:
        "https://files.kraftek.dev/qwen/Qwen3.5-4B-MLX-4bit.zip.sha256"
    )!

    /// Manual browser fallback when automatic download fails.
    public static let defaultHostFallbackPageURL = URL(string:
        "https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit"
    )!

    /// Directory name under `Vovozinha/Models/`.
    public static let defaultModelDirectoryName = "Qwen3.5-4B-MLX-4bit"

    /// Zip filename expected for Downloads auto-import.
    public static let defaultZipFilename = "Qwen3.5-4B-MLX-4bit.zip"

    private let modelDirectoryURL: URL
    private let sourceURL: URL
    /// Host checksum file; when non-nil, `download` fetches it and verifies the zip.
    private let sha256URL: URL?
    private let session: URLSession

    public enum DownloadError: Error, LocalizedError, Equatable {
        case http(statusCode: Int)
        case emptyFile
        case unzipFailed
        case checksumMismatch
        case checksumFileInvalid
        case checksumUnavailable

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
            case .checksumFileInvalid:
                return "Could not read the download checksum from the server. Try again later."
            case .checksumUnavailable:
                return "Could not download the integrity checksum. Try again on Wi‑Fi."
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
    ///   - sha256URL: Sidecar checksum URL (defaults to `*.zip.sha256` on the same host).
    ///     Pass `nil` only in tests that skip integrity checks.
    ///   - session: Injectable for tests.
    public init(
        documentsURL: URL? = nil,
        sourceURL: URL = OnDeviceMLXModelStore.defaultHostDownloadURL,
        sha256URL: URL? = OnDeviceMLXModelStore.defaultHostSHA256URL,
        session: URLSession = .shared
    ) {
        let docs = documentsURL ?? OnDeviceMLXModelStore.defaultDocumentsURL()
        self.modelDirectoryURL = docs
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Self.defaultModelDirectoryName, isDirectory: true)
        self.sourceURL = sourceURL
        self.sha256URL = sha256URL
        self.session = session
    }

    public func modelDirectory() -> URL { modelDirectoryURL }

    public func isModelPresent() -> Bool {
        Self.directoryLooksLikeMLXPack(modelDirectoryURL)
    }

    /// Downloads the model zip from our host, unpacks into the app sandbox (with progress).
    ///
    /// - Parameter progress: Optional main-actor callback with fraction, speed, elapsed, and ETA.
    public func download(
        progress: (@MainActor @Sendable (ModelDownloadProgress) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(
            at: modelDirectoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var request = URLRequest(url: sourceURL)
        request.setValue("Vovozinha/1.0 (iOS; Qwen3.5 MLX model fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let started = Date()
        if let progress {
            await progress(ModelDownloadProgress(phase: .downloading))
        }

        // Fetch CDN checksum first (small) so we fail fast if the sidecar is missing.
        let expectedHash: String?
        if let sha256URL {
            if let progress {
                await progress(
                    Self.makeDownloadSnapshot(
                        started: started,
                        received: 0,
                        bytesTotal: nil,
                        phase: .verifying,
                        fractionOverride: 0.02
                    )
                )
            }
            do {
                expectedHash = try await Self.fetchRemoteSHA256(from: sha256URL, session: session)
            } catch let e as DownloadError {
                throw e
            } catch {
                throw DownloadError.checksumUnavailable
            }
        } else {
            expectedHash = nil
        }

        if let progress {
            await progress(ModelDownloadProgress(fraction: 0.03, phase: .downloading))
        }

        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.http(statusCode: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.http(statusCode: http.statusCode)
        }

        let expectedLength = http.expectedContentLength
        let bytesTotal: Int64? = expectedLength > 0 ? expectedLength : nil
        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: tempZip.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempZip)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var lastReport = Date.distantPast
        let reportInterval: TimeInterval = 0.25

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                received &+= Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let now = Date()
                if let progress, now.timeIntervalSince(lastReport) >= reportInterval {
                    lastReport = now
                    await progress(
                        Self.makeDownloadSnapshot(
                            started: started,
                            received: received,
                            bytesTotal: bytesTotal,
                            phase: .downloading
                        )
                    )
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

        if let progress {
            await progress(
                Self.makeDownloadSnapshot(
                    started: started,
                    received: received,
                    bytesTotal: bytesTotal,
                    phase: .downloading,
                    fractionOverride: 0.92
                )
            )
        }

        // Integrity check only for host auto-download (not Import / external sources).
        if let expectedHash {
            if let progress {
                await progress(
                    Self.makeDownloadSnapshot(
                        started: started,
                        received: received,
                        bytesTotal: bytesTotal,
                        phase: .verifying,
                        fractionOverride: 0.94
                    )
                )
            }
            do {
                try Self.verifySHA256(ofFileAt: tempZip, expectedHex: expectedHash)
            } catch {
                try? FileManager.default.removeItem(at: tempZip)
                throw error
            }
        }

        if let progress {
            await progress(
                Self.makeDownloadSnapshot(
                    started: started,
                    received: received,
                    bytesTotal: bytesTotal,
                    phase: .unpacking,
                    fractionOverride: 0.96
                )
            )
        }

        do {
            try Self.installPack(fromZip: tempZip, to: modelDirectoryURL)
            try? FileManager.default.removeItem(at: tempZip)
        } catch {
            try? FileManager.default.removeItem(at: tempZip)
            throw DownloadError.unzipFailed
        }

        guard isModelPresent() else { throw DownloadError.unzipFailed }
        if let progress {
            await progress(
                Self.makeDownloadSnapshot(
                    started: started,
                    received: received,
                    bytesTotal: bytesTotal ?? received,
                    phase: .finished,
                    fractionOverride: 1
                )
            )
        }
    }

    private static func makeDownloadSnapshot(
        started: Date,
        received: Int64,
        bytesTotal: Int64?,
        phase: ModelDownloadProgress.Phase,
        fractionOverride: Double? = nil
    ) -> ModelDownloadProgress {
        let elapsed = max(Date().timeIntervalSince(started), 0.001)
        let bps = Double(received) / elapsed
        let fraction: Double
        if let fractionOverride {
            fraction = fractionOverride
        } else if let bytesTotal, bytesTotal > 0 {
            // Leave headroom for verify + unpack.
            fraction = min(Double(received) / Double(bytesTotal) * 0.92, 0.92)
        } else {
            fraction = 0
        }
        var eta: TimeInterval?
        if phase == .downloading, let bytesTotal, bytesTotal > received, bps > 1 {
            eta = Double(bytesTotal - received) / bps
        } else if phase == .finished {
            eta = 0
        }
        return ModelDownloadProgress(
            fraction: fraction,
            bytesReceived: received,
            bytesTotal: bytesTotal,
            bytesPerSecond: bps,
            elapsed: elapsed,
            estimatedRemaining: eta,
            phase: phase
        )
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

    /// Downloads and parses a shasum-style sidecar (`hex  filename` or bare hex).
    static func fetchRemoteSHA256(from url: URL, session: URLSession) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Vovozinha/1.0 (iOS; Qwen3.5 MLX checksum fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.checksumUnavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.http(statusCode: http.statusCode)
        }
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            throw DownloadError.checksumFileInvalid
        }
        return try parseSHA256File(text)
    }

    /// Accepts `8b78…  Qwen3.5-4B-MLX-4bit.zip` or a bare 64-char hex line.
    static func parseSHA256File(_ text: String) throws -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        for line in lines {
            let token = line.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            let hex = token.lowercased()
            if hex.count == 64, hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) {
                return hex
            }
        }
        throw DownloadError.checksumFileInvalid
    }

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
