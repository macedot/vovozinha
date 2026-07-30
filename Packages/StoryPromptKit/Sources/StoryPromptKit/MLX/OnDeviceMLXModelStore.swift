import Foundation
import CryptoKit
import ZIPFoundation

/// Owns the on-device **Qwen3.5-4B-MLX-4bit** MLX model directory.
///
/// **Generation is offline.** Networking is only used to **download** a zip once from our
/// host (`files.kraftek.dev`). If that fails, the UI can open Hugging Face as a manual
/// fallback and the user **imports** a zip or folder via the system document picker
/// (copied into private app storage — never left in user Documents/Downloads).
///
/// **Pack path (private):**  
/// `Library/Application Support/Vovozinha/Models/Qwen3.5-4B-MLX-4bit/`  
/// (not visible in the Files app “On My iPhone” Documents tree).
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

    /// Zip filename (CDN + document-picker Import). Not scanned from Downloads.
    public static let defaultZipFilename = "Qwen3.5-4B-MLX-4bit.zip"

    private let modelDirectoryURL: URL
    private let sourceURL: URL
    /// Host checksum file; when non-nil, `download` fetches it and verifies the zip.
    private let sha256URL: URL?
    private let session: URLSession
    private var didAttemptLegacyMigration = false

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

    /// Session tuned for multi‑GB model packs (long resource timeout, no URL cache).
    public static let defaultDownloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 6 * 60 * 60
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// - Parameters:
    ///   - storageRootURL: Root under which `Vovozinha/Models/` is created. Defaults to
    ///     **Application Support** (private). Tests inject a temp directory.
    ///   - sourceURL: Automatic download URL (defaults to kraftek host zip).
    ///   - sha256URL: Sidecar checksum URL (defaults to `*.zip.sha256` on the same host).
    ///     Pass `nil` only in tests that skip integrity checks.
    ///   - session: Injectable for tests.
    public init(
        storageRootURL: URL? = nil,
        sourceURL: URL = OnDeviceMLXModelStore.defaultHostDownloadURL,
        sha256URL: URL? = OnDeviceMLXModelStore.defaultHostSHA256URL,
        session: URLSession = OnDeviceMLXModelStore.defaultDownloadSession
    ) {
        let root = storageRootURL ?? OnDeviceMLXModelStore.defaultApplicationSupportRootURL()
        self.modelDirectoryURL = root
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Self.defaultModelDirectoryName, isDirectory: true)
        self.sourceURL = sourceURL
        self.sha256URL = sha256URL
        self.session = session
    }

    /// Back-compat for tests that still pass `documentsURL:` (any injectable root).
    public init(
        documentsURL: URL,
        sourceURL: URL = OnDeviceMLXModelStore.defaultHostDownloadURL,
        sha256URL: URL? = OnDeviceMLXModelStore.defaultHostSHA256URL,
        session: URLSession = OnDeviceMLXModelStore.defaultDownloadSession
    ) {
        self.init(
            storageRootURL: documentsURL,
            sourceURL: sourceURL,
            sha256URL: sha256URL,
            session: session
        )
    }

    public func modelDirectory() -> URL { modelDirectoryURL }

    public func isModelPresent() -> Bool {
        migrateLegacyDocumentsModelIfNeeded()
        return Self.directoryLooksLikeMLXPack(modelDirectoryURL)
    }

    /// Downloads the model zip from our host, unpacks into **Application Support** (with progress).
    ///
    /// - Parameter progress: Optional main-actor callback with fraction, speed, elapsed, and ETA.
    public func download(
        progress: (@MainActor @Sendable (ModelDownloadProgress) -> Void)? = nil
    ) async throws {
        migrateLegacyDocumentsModelIfNeeded()
        try FileManager.default.createDirectory(
            at: modelDirectoryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.excludeFromBackup(modelDirectoryURL.deletingLastPathComponent())

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

        // Dedicated session + download task. Progress is stored in a shared box and
        // pumped with `await progress(...)` on this task — unstructured
        // `Task { @MainActor }` from the session queue does not reliably refresh SwiftUI
        // while this actor method is in flight.
        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-qwen.zip")
        let live = ModelZipDownloadLiveState(started: started)
        let (received, bytesTotal): (Int64, Int64?)
        do {
            async let downloadOutcome = ModelZipDownloadController.download(
                request: request,
                destinationURL: tempZip,
                live: live
            )
            if let progress {
                while !live.isFinished {
                    await progress(live.snapshot(phase: .downloading))
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2s UI pump
                }
                // Final byte counts after settle (before we throw on failure).
                await progress(live.snapshot(phase: .downloading))
            }
            let outcome = try await downloadOutcome
            received = outcome.bytesReceived
            bytesTotal = outcome.bytesTotal
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
            try Self.excludeFromBackup(modelDirectoryURL)
            try? FileManager.default.removeItem(at: tempZip)
        } catch {
            try? FileManager.default.removeItem(at: tempZip)
            throw DownloadError.unzipFailed
        }

        guard Self.directoryLooksLikeMLXPack(modelDirectoryURL) else {
            throw DownloadError.unzipFailed
        }

        // Remember the CDN zip hash so later launches can detect a newer pack.
        if let expectedHash {
            try? persistInstallSHA256(expectedHash)
        } else {
            clearInstallSHA256()
        }

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

    fileprivate static func makeDownloadSnapshot(
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

    /// Imports a user-provided **zip** or **folder** into private Application Support.
    /// Source may be a security-scoped URL from the document picker; the pack is **copied**
    /// into app storage — we never keep the model in Documents or Downloads.
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

        try Self.excludeFromBackup(modelDirectoryURL)
        guard Self.directoryLooksLikeMLXPack(modelDirectoryURL) else {
            throw ImportError.copyFailed
        }
        // Import is not CDN-verified — drop any previous host install hash.
        clearInstallSHA256()
    }

    public func removeModel() throws {
        if FileManager.default.fileExists(atPath: modelDirectoryURL.path) {
            try FileManager.default.removeItem(at: modelDirectoryURL)
        }
        clearInstallSHA256()
    }

    /// Sidecar next to the pack: `…/Models/Qwen3.5-4B-MLX-4bit.installed.sha256`.
    /// Holds the CDN zip hex recorded after a verified host download (not inside weights).
    public func installedSHA256SidecarURL() -> URL {
        modelDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(Self.defaultModelDirectoryName).installed.sha256")
    }

    /// Hex recorded after the last verified host download, if any.
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

    /// Compares the recorded install hash to the CDN `.sha256` sidecar.
    /// Returns `true` only when both exist and differ. Missing pack, missing local hash,
    /// missing `sha256URL`, or any network/parse failure → `false` (stay silent).
    public func checkForHostUpdate() async -> Bool {
        guard isModelPresent() else { return false }
        guard let recorded = recordedInstallSHA256() else { return false }
        guard let sha256URL else { return false }
        do {
            let remote = try await Self.fetchRemoteSHA256(from: sha256URL, session: session)
            return remote != recorded
        } catch {
            return false
        }
    }

    // MARK: - Paths

    /// Private Application Support root (not user Documents / Downloads).
    public static func defaultApplicationSupportRootURL() -> URL {
        let fm = FileManager.default
        let base =
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        // Ensure Application Support exists (iOS may not create it until first write).
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// One-time move from the old `Documents/Vovozinha/Models/…` location (user-visible).
    private func migrateLegacyDocumentsModelIfNeeded() {
        guard !didAttemptLegacyMigration else { return }
        didAttemptLegacyMigration = true

        if Self.directoryLooksLikeMLXPack(modelDirectoryURL) { return }

        let legacy = Self.legacyDocumentsModelDirectoryURL()
        guard Self.directoryLooksLikeMLXPack(legacy) else { return }

        do {
            try Self.replaceDirectory(at: modelDirectoryURL, withContentsOf: legacy)
            try Self.excludeFromBackup(modelDirectoryURL)
            try? FileManager.default.removeItem(at: legacy)
            // Clean empty parent folders if possible.
            let modelsParent = legacy.deletingLastPathComponent()
            let vovoParent = modelsParent.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: modelsParent)
            if let children = try? FileManager.default.contentsOfDirectory(atPath: vovoParent.path),
               children.isEmpty {
                try? FileManager.default.removeItem(at: vovoParent)
            }
        } catch {
            // Leave legacy in place if move fails; next launch can retry.
            #if DEBUG
            print("[OnDeviceMLXModelStore] legacy model migration failed: \(error)")
            #endif
        }
    }

    /// Previous pack path under Documents (user-visible Files app).
    static func legacyDocumentsModelDirectoryURL() -> URL {
        let docs =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(defaultModelDirectoryName, isDirectory: true)
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
        let url = installedSHA256SidecarURL()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Host integrity

    /// Downloads and parses a shasum-style sidecar (`hex  filename` or bare hex).
    static func fetchRemoteSHA256(from url: URL, session: URLSession) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Vovozinha/1.0 (iOS; Qwen3.5 MLX checksum fetch)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw DownloadError.http(statusCode: http.statusCode)
            }
        } else if !url.isFileURL {
            // Production always hits HTTPS; file URLs are allowed for unit tests.
            throw DownloadError.checksumUnavailable
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

    /// Unpacks a model zip with ZIPFoundation (libcompression). Prefer CDN packs built with
    /// `zip -0` (store): safetensors are already compressed, so deflate only wastes CPU on
    /// device. Still accepts legacy deflate zips for manual Import.
    static func unzipItem(at zipURL: URL, to destination: URL) throws {
        do {
            try FileManager.default.unzipItem(at: zipURL, to: destination)
        } catch {
            throw ImportError.unzipFailed
        }
    }

}

// MARK: - Large zip download (session delegate + polled progress)

/// Thread-safe live counters for UI polling (session queue writes, download task reads).
private final class ModelZipDownloadLiveState: @unchecked Sendable {
    private let lock = NSLock()
    private let started: Date
    private var received: Int64 = 0
    private var total: Int64?
    private var finished = false

    init(started: Date) {
        self.started = started
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func update(received: Int64, total: Int64?) {
        lock.lock()
        self.received = max(self.received, received)
        if let total, total > 0 {
            self.total = total
        }
        lock.unlock()
    }

    func markFinished(received: Int64? = nil, total: Int64? = nil) {
        lock.lock()
        if let received {
            self.received = max(self.received, received)
        }
        if let total, total > 0 {
            self.total = total
        }
        finished = true
        lock.unlock()
    }

    func snapshot(phase: ModelDownloadProgress.Phase) -> ModelDownloadProgress {
        lock.lock()
        let received = self.received
        let total = self.total
        lock.unlock()
        return OnDeviceMLXModelStore.makeDownloadSnapshot(
            started: started,
            received: received,
            bytesTotal: total,
            phase: phase
        )
    }
}

/// One-shot multi‑GB download via `URLSessionDownloadDelegate`.
///
/// The session retains this object as its delegate for the lifetime of the task; we break
/// the cycle with `finishTasksAndInvalidate()` when settled. Progress is published only via
/// `live` (polled by the caller) — not via unstructured MainActor tasks.
private final class ModelZipDownloadController: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Outcome: Sendable {
        var bytesReceived: Int64
        var bytesTotal: Int64?
    }

    private let destinationURL: URL
    private let live: ModelZipDownloadLiveState
    private let continuation: CheckedContinuation<Outcome, Error>

    private let lock = NSLock()
    private var settled = false
    private var session: URLSession?
    private var progressObservation: NSKeyValueObservation?

    private init(
        destinationURL: URL,
        live: ModelZipDownloadLiveState,
        continuation: CheckedContinuation<Outcome, Error>
    ) {
        self.destinationURL = destinationURL
        self.live = live
        self.continuation = continuation
    }

    static func download(
        request: URLRequest,
        destinationURL: URL,
        live: ModelZipDownloadLiveState
    ) async throws -> Outcome {
        try await withCheckedThrowingContinuation { cont in
            let controller = ModelZipDownloadController(
                destinationURL: destinationURL,
                live: live,
                continuation: cont
            )
            controller.start(request: request)
        }
    }

    private func start(request: URLRequest) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 6 * 60 * 60
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 6

        let queue = OperationQueue()
        queue.name = "app.vovozinha.ModelZipDownload"
        queue.maxConcurrentOperationCount = 1

        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.downloadTask(with: request)
        // KVO backup: some OS versions are flaky about `didWriteData` frequency.
        progressObservation = task.progress.observe(\.completedUnitCount, options: [.new]) { [live] progress, _ in
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            live.update(
                received: completed,
                total: total > 0 ? total : nil
            )
        }
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        live.update(
            received: totalBytesWritten,
            total: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            live.markFinished()
            settle(.failure(OnDeviceMLXModelStore.DownloadError.http(statusCode: http.statusCode)))
            return
        }

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            // Must copy/move before this method returns — system temp file is ephemeral.
            try fm.copyItem(at: location, to: destinationURL)

            let attrs = try fm.attributesOfItem(atPath: destinationURL.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else {
                live.markFinished()
                settle(.failure(OnDeviceMLXModelStore.DownloadError.emptyFile))
                return
            }

            let expectedFromResponse = (downloadTask.response as? HTTPURLResponse)?.expectedContentLength ?? -1
            let total: Int64? = expectedFromResponse > 0 ? expectedFromResponse : size
            live.markFinished(received: size, total: total)
            settle(.success(Outcome(bytesReceived: size, bytesTotal: total)))
        } catch {
            live.markFinished()
            settle(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            live.markFinished()
            settle(.failure(error))
        }
        // Success is settled in `didFinishDownloadingTo`.
    }

    private func settle(_ result: Result<Outcome, Error>) {
        lock.lock()
        guard !settled else {
            lock.unlock()
            return
        }
        settled = true
        progressObservation?.invalidate()
        progressObservation = nil
        let session = self.session
        self.session = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
