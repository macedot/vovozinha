import Foundation
import CryptoKit
import ZIPFoundation

/// Owns the on-device **Core ML image pack** — the compiled `.mlmodelc` bundles that
/// `StableDiffusionPipeline(resourcesAt:)` loads.
///
/// This is the image-gen analogue of StoryPromptKit's `OnDeviceMLXModelStore`, but
/// self-contained (this kit must **not** import StoryPromptKit — see the package doc on
/// `ImageGenKit`). It reuses the same conventions:
///
/// **Pack path (private):**
/// `Library/Application Support/Vovozinha/ImagePack/Resources/`
/// (what `StableDiffusionPipeline(resourcesAt:)` expects; not user-visible Documents).
///
/// **Integrity:** host downloads fetch a `…zip.sha256` sidecar and verify the zip before
/// install, then record that hash beside the pack for later update checks. Manual Import
/// (document picker) is the explicit no-checksum fallback.
///
/// **img2img requirement:** a valid pack **must** contain `VAEEncoder.mlmodelc` — without
/// it the pipeline cannot encode a source photo. `supportsImageToImage` is therefore
/// always `true` for packs that pass `directoryLooksLikeImagePack`.
public actor CoreMLImagePackStore {

    // MARK: - Defaults

    /// Automatic in-app download (zip of compiled Core ML `.mlmodelc` bundles).
    public static let defaultHostDownloadURL = URL(string:
        "https://vovo.kraftek.cloud/imagepack/AnimeImg2Img-SD15.zip"
    )!

    /// Sidecar checksum for the host zip (`*.zip.sha256`, shasum-style text).
    public static let defaultHostSHA256URL = URL(string:
        "https://vovo.kraftek.cloud/imagepack/AnimeImg2Img-SD15.zip.sha256"
    )!

    /// Directory name under `Vovozinha/`. `Resources/` inside holds the `.mlmodelc` files.
    public static let packDirectoryName = ImageGenKit.packDirectoryName  // "ImagePack"

    /// Resources subdirectory name (the URL passed to `StableDiffusionPipeline(resourcesAt:)`).
    public static let resourcesSubdirectoryName = "Resources"

    public static let defaultZipFilename = "AnimeImg2Img-SD15.zip"

    private let resourcesURL: URL
    private let sourceURL: URL
    private let sha256URL: URL?
    private let session: URLSession
    private var didAttemptLegacyMigration = false

    // MARK: - Errors

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
                return "Image pack download failed (HTTP \(code)). Try again on Wi‑Fi, or Import from Files."
            case .emptyFile:
                return "Image pack download finished but the file is empty."
            case .unzipFailed:
                return "Could not unpack the image pack. Try Import from Files."
            case .checksumMismatch:
                return "Image pack failed integrity check. Try again on Wi‑Fi, or Import from Files."
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
        case incompletePack
        case unzipFailed

        public var errorDescription: String? {
            switch self {
            case .unreadableSource:
                return "Could not read the selected image pack file or folder."
            case .emptyFile:
                return "The selected file is empty."
            case .copyFailed:
                return "Could not copy the image pack into the app. Try again."
            case .incompletePack:
                return "Image pack is incomplete. It needs TextEncoder, VAEDecoder, VAEEncoder, a Unet (or Unet chunks), vocab.json, and merges.txt."
            case .unzipFailed:
                return "Could not unpack the image pack archive."
            }
        }
    }

    /// Session tuned for multi-GB packs (long resource timeout, no URL cache).
    public static let defaultDownloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 6 * 60 * 60
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - storageRootURL: Root under which `Vovozinha/ImagePack/Resources/` is created.
    ///     Defaults to **Application Support** (private). Tests inject a temp directory.
    ///   - sourceURL: Automatic download URL (defaults to kraftek host zip).
    ///   - sha256URL: Sidecar checksum URL. Pass `nil` only in tests that skip checks.
    ///   - session: Injectable for tests.
    public init(
        storageRootURL: URL? = nil,
        sourceURL: URL = CoreMLImagePackStore.defaultHostDownloadURL,
        sha256URL: URL? = CoreMLImagePackStore.defaultHostSHA256URL,
        session: URLSession = CoreMLImagePackStore.defaultDownloadSession
    ) {
        let root = storageRootURL ?? CoreMLImagePackStore.defaultApplicationSupportRootURL()
        self.resourcesURL = root
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent(Self.packDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.resourcesSubdirectoryName, isDirectory: true)
        self.sourceURL = sourceURL
        self.sha256URL = sha256URL
        self.session = session
    }

    // MARK: - Presence

    /// The `Resources/` directory to pass to `StableDiffusionPipeline(resourcesAt:)`.
    public func resourcesDirectory() -> URL { resourcesURL }

    public func isPackPresent() -> Bool {
        migrateLegacyDocumentsPackIfNeeded()
        return Self.directoryLooksLikeImagePack(resourcesURL)
    }

    /// True when `VAEEncoder.mlmodelc` is present (required to encode a source photo).
    public func supportsImageToImage() -> Bool {
        Self.fileExists(in: resourcesURL, named: "VAEEncoder.mlmodelc", isDirectory: true)
    }

    /// True when TextEncoder + Unet(+chunks) + VAEDecoder + tokenizer files are present.
    public func supportsTextToImage() -> Bool {
        Self.directoryLooksLikeTextToImagePack(resourcesURL)
    }

    // MARK: - Download

    /// Downloads the pack zip from our host, unpacks into **Application Support**.
    public func download(
        progress: (@MainActor @Sendable (ModelDownloadProgress) -> Void)? = nil
    ) async throws {
        migrateLegacyDocumentsPackIfNeeded()
        try FileManager.default.createDirectory(
            at: resourcesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.excludeFromBackup(resourcesURL.deletingLastPathComponent())

        var request = URLRequest(url: sourceURL)
        request.setValue("Vovozinha/1.0 (iOS; Core ML image pack fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let started = Date()
        if let progress { await progress(ModelDownloadProgress(phase: .downloading)) }

        // Fetch CDN checksum first (small) so we fail fast if the sidecar is missing.
        let expectedHash: String?
        if let sha256URL {
            if let progress {
                await progress(Self.snapshot(started: started, received: 0, total: nil,
                                             phase: .verifying, fractionOverride: 0.02))
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

        if let progress { await progress(ModelDownloadProgress(fraction: 0.03, phase: .downloading)) }

        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-imagepack.zip")
        let live = ModelZipDownloadLiveState(started: started)
        let (received, bytesTotal): (Int64, Int64?)
        do {
            async let outcome = ModelZipDownloadController.download(
                request: request, destinationURL: tempZip, live: live
            )
            if let progress {
                while !live.isFinished {
                    await progress(live.snapshot(phase: .downloading))
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                await progress(live.snapshot(phase: .downloading))
            }
            let out = try await outcome
            received = out.bytesReceived
            bytesTotal = out.bytesTotal
        } catch let e as DownloadError {
            try? FileManager.default.removeItem(at: tempZip)
            throw e
        } catch {
            try? FileManager.default.removeItem(at: tempZip)
            throw error
        }

        guard received > 0 else {
            try? FileManager.default.removeItem(at: tempZip)
            throw DownloadError.emptyFile
        }

        if let progress {
            await progress(Self.snapshot(started: started, received: received, total: bytesTotal,
                                         phase: .downloading, fractionOverride: 0.92))
        }

        if let expectedHash {
            if let progress {
                await progress(Self.snapshot(started: started, received: received, total: bytesTotal,
                                             phase: .verifying, fractionOverride: 0.94))
            }
            do {
                try Self.verifySHA256(ofFileAt: tempZip, expectedHex: expectedHash)
            } catch {
                try? FileManager.default.removeItem(at: tempZip)
                throw error
            }
        }

        if let progress {
            await progress(Self.snapshot(started: started, received: received, total: bytesTotal,
                                         phase: .unpacking, fractionOverride: 0.96))
        }

        do {
            try Self.installPack(fromZip: tempZip, to: resourcesURL)
            try Self.excludeFromBackup(resourcesURL)
            try? FileManager.default.removeItem(at: tempZip)
        } catch {
            try? FileManager.default.removeItem(at: tempZip)
            throw DownloadError.unzipFailed
        }

        guard Self.directoryLooksLikeImagePack(resourcesURL) else {
            throw DownloadError.unzipFailed
        }

        if let expectedHash {
            try? persistInstallSHA256(expectedHash)
        } else {
            clearInstallSHA256()
        }

        if let progress {
            await progress(Self.snapshot(started: started, received: received,
                                         total: bytesTotal ?? received,
                                         phase: .finished, fractionOverride: 1))
        }
    }

    // MARK: - Import (document-picker fallback, no checksum)

    public func importPack(from sourceURL: URL) throws {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir)
        guard exists else { throw ImportError.unreadableSource }

        if isDir.boolValue {
            // A folder whose contents are the .mlmodelc files, OR a folder containing
            // a `Resources/` subdir. Accept the Resources layout if present.
            let candidate = sourceURL.appendingPathComponent(Self.resourcesSubdirectoryName)
            let root = Self.directoryLooksLikeImagePack(candidate)
                ? candidate
                : (Self.directoryLooksLikeImagePack(sourceURL) ? sourceURL : nil)
            guard let root else { throw ImportError.incompletePack }
            try Self.replaceDirectory(at: resourcesURL, withContentsOf: root)
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            if size <= 0 { throw ImportError.emptyFile }

            let tempZip = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-import.zip")
            do {
                try FileManager.default.copyItem(at: sourceURL, to: tempZip)
            } catch {
                throw ImportError.copyFailed
            }
            do {
                try Self.installPack(fromZip: tempZip, to: resourcesURL)
                try Self.excludeFromBackup(resourcesURL)
                try? FileManager.default.removeItem(at: tempZip)
            } catch {
                try? FileManager.default.removeItem(at: tempZip)
                throw ImportError.unzipFailed
            }
        }

        guard Self.directoryLooksLikeImagePack(resourcesURL) else {
            throw ImportError.incompletePack
        }
        clearInstallSHA256()
    }

    public func removePack() throws {
        let packRoot = resourcesURL.deletingLastPathComponent()  // …/ImagePack
        if FileManager.default.fileExists(atPath: packRoot.path) {
            try FileManager.default.removeItem(at: packRoot)
        }
        clearInstallSHA256()
    }

    // MARK: - Update detection

    /// Sidecar beside the pack: `…/ImagePack.installed.sha256`.
    public func installedSHA256SidecarURL() -> URL {
        resourcesURL
            .deletingLastPathComponent()  // …/ImagePack
            .appendingPathComponent("\(Self.packDirectoryName).installed.sha256")
    }

    public func recordedInstallSHA256() -> String? {
        let url = installedSHA256SidecarURL()
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        let hex = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hex.count == 64,
              hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) })
        else { return nil }
        return hex
    }

    /// `true` only when the pack is present, a recorded hash exists, and the CDN sidecar
    /// differs. Any missing piece or failure → `false`.
    public func checkForHostUpdate() async -> Bool {
        guard isPackPresent() else { return false }
        guard let recorded = recordedInstallSHA256() else { return false }
        guard let sha256URL else { return false }
        do {
            let remote = try await Self.fetchRemoteSHA256(from: sha256URL, session: session)
            return remote != recorded
        } catch {
            return false
        }
    }

    // MARK: - Paths & migration

    public static func defaultApplicationSupportRootURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func migrateLegacyDocumentsPackIfNeeded() {
        guard !didAttemptLegacyMigration else { return }
        didAttemptLegacyMigration = true
        if Self.directoryLooksLikeImagePack(resourcesURL) { return }

        let legacy = Self.legacyDocumentsResourcesURL()
        guard Self.directoryLooksLikeImagePack(legacy) else { return }
        do {
            try Self.replaceDirectory(at: resourcesURL, withContentsOf: legacy)
            try Self.excludeFromBackup(resourcesURL)
            try? FileManager.default.removeItem(at: legacy.deletingLastPathComponent())
        } catch {
            #if DEBUG
            print("[CoreMLImagePackStore] legacy pack migration failed: \(error)")
            #endif
        }
    }

    static func legacyDocumentsResourcesURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent(packDirectoryName, isDirectory: true)
            .appendingPathComponent(resourcesSubdirectoryName, isDirectory: true)
    }

    static func excludeFromBackup(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    // MARK: - Install hash sidecar

    private func persistInstallSHA256(_ hex: String) throws {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parent = installedSHA256SidecarURL().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Data(normalized.utf8).write(to: installedSHA256SidecarURL(), options: .atomic)
        try? Self.excludeFromBackup(installedSHA256SidecarURL())
    }

    private func clearInstallSHA256() {
        try? FileManager.default.removeItem(at: installedSHA256SidecarURL())
    }

    // MARK: - Host integrity (shared with MLX store — proven helpers)

    static func fetchRemoteSHA256(from url: URL, session: URLSession) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Vovozinha/1.0 (iOS; Core ML image pack checksum fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw DownloadError.http(statusCode: http.statusCode)
            }
        } else if !url.isFileURL {
            throw DownloadError.checksumUnavailable
        }
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            throw DownloadError.checksumFileInvalid
        }
        return try parseSHA256File(text)
    }

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

    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20)  // 1 MB
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verifySHA256(ofFileAt url: URL, expectedHex: String) throws {
        let actual = try sha256Hex(ofFileAt: url)
        let expected = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard actual == expected else { throw DownloadError.checksumMismatch }
    }

    // MARK: - Pack helpers

    static func fileExists(in dir: URL, named: String, isDirectory: Bool) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let path = dir.appendingPathComponent(named).path
        return fm.fileExists(atPath: path, isDirectory: &isDir) && (isDir.boolValue == isDirectory)
    }

    /// txt2img-capable pack: TextEncoder + VAEDecoder + Unet(+chunks) + vocab + merges.
    static func directoryLooksLikeTextToImagePack(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        for required in ["TextEncoder.mlmodelc", "VAEDecoder.mlmodelc"] {
            guard fileExists(in: url, named: required, isDirectory: true) else { return false }
        }
        for file in ["vocab.json", "merges.txt"] {
            guard fm.fileExists(atPath: url.appendingPathComponent(file).path) else { return false }
        }
        let singleUnet = fileExists(in: url, named: "Unet.mlmodelc", isDirectory: true)
        let chunked = fileExists(in: url, named: "UnetChunk1.mlmodelc", isDirectory: true)
            && fileExists(in: url, named: "UnetChunk2.mlmodelc", isDirectory: true)
        return singleUnet || chunked
    }

    /// Full pack (txt2img + img2img): txt2img files plus **VAEEncoder**.
    static func directoryLooksLikeImagePack(_ url: URL) -> Bool {
        directoryLooksLikeTextToImagePack(url)
            && fileExists(in: url, named: "VAEEncoder.mlmodelc", isDirectory: true)
    }

    /// Unzips `zip` into a temp staging dir, then promotes the nested `Resources/` (or the
    /// flat `.mlmodelc` root) into `destination`. Drops `SafetyChecker.mlmodelc` if present.
    static func installPack(fromZip zip: URL, to destination: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-stage")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try fm.unzipItem(at: zip, to: staging)

        // Locate the models root: prefer a nested `Resources/`; else the staged dir if it
        // already looks like a pack; else search one level deep for a pack-shaped folder.
        var modelsRoot: URL?
        let candidateResources = staging.appendingPathComponent(resourcesSubdirectoryName)
        if directoryLooksLikeImagePack(candidateResources) {
            modelsRoot = candidateResources
        } else if directoryLooksLikeImagePack(staging) {
            modelsRoot = staging
        } else if let contents = try? fm.contentsOfDirectory(atPath: staging.path) {
            for name in contents {
                let sub = staging.appendingPathComponent(name)
                let subResources = sub.appendingPathComponent(resourcesSubdirectoryName)
                if directoryLooksLikeImagePack(subResources) { modelsRoot = subResources; break }
                if directoryLooksLikeImagePack(sub) { modelsRoot = sub; break }
            }
        }
        guard let root = modelsRoot else { throw DownloadError.unzipFailed }

        // Replace destination with a clean copy, excluding SafetyChecker.
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let skip = "SafetyChecker"
        if let entries = try? fm.contentsOfDirectory(atPath: root.path) {
            for entry in entries where !entry.contains(skip) {
                let src = root.appendingPathComponent(entry)
                let dst = destination.appendingPathComponent(entry)
                try fm.copyItem(at: src, to: dst)
            }
        }
    }

    static func replaceDirectory(at destination: URL, withContentsOf source: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    static func snapshot(
        started: Date, received: Int64, total: Int64?,
        phase: ModelDownloadProgress.Phase, fractionOverride: Double? = nil
    ) -> ModelDownloadProgress {
        let elapsed = max(Date().timeIntervalSince(started), 0.001)
        let bps = Double(received) / elapsed
        let fraction: Double
        if let fractionOverride { fraction = fractionOverride }
        else if let total, total > 0 { fraction = min(Double(received) / Double(total) * 0.92, 0.92) }
        else { fraction = 0 }
        var eta: TimeInterval?
        if phase == .downloading, let total, total > received, bps > 1 {
            eta = Double(total - received) / bps
        } else if phase == .finished {
            eta = 0
        }
        return ModelDownloadProgress(
            fraction: fraction, bytesReceived: received, bytesTotal: total,
            bytesPerSecond: bps, elapsed: elapsed, estimatedRemaining: eta, phase: phase
        )
    }
}
