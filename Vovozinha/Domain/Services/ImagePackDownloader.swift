import Foundation
import Observation
import os

private let packLog = Logger(subsystem: "app.vovozinha", category: "ImagePackDownload")

/// In-app download of offline **anime-tuned** Core ML Stable Diffusion assets.
/// Network is only used for the download; generation stays fully on-device afterward.
@MainActor
@Observable
final class ImagePackDownloader {
    enum Phase: Equatable {
        case idle
        case listing
        case downloading
        case extracting
        case verifying
        case ready
        case failed(String)
    }

    /// Anime-tuned pack: Anything V5 Ink, Neural Engine `split_einsum_v2` compiled (~1.5 GB zip).
    /// Includes TextEncoder, Unet, VAEDecoder, **VAEEncoder** (img2img), vocab, merges.
    nonisolated static let defaultRepoID = "mozksoft/AnythingV5Ink-coreml"
    nonisolated static let defaultZipFileName = "AnythingV5Ink-coreml_split_einsum_v2_compiled.zip"
    nonisolated static let packKindID = "anime-anything-v5-ink"

    /// Legacy tree-style Apple SD1.5 pack (still supported if already installed).
    static let legacyAppleRepoID = "apple/coreml-stable-diffusion-v1-5-palettized"
    static let legacyVariantPrefix = "split_einsum_v2/compiled"

    private(set) var phase: Phase = .idle
    /// 0…1 overall progress.
    private(set) var progress: Double = 0
    private(set) var bytesDownloaded: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var filesDone: Int = 0
    private(set) var filesTotal: Int = 0
    private(set) var currentFileName: String = ""

    private var downloadTask: Task<Void, Never>?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        refreshReadyState()
    }

    var isBusy: Bool {
        switch phase {
        case .listing, .downloading, .extracting, .verifying: return true
        default: return false
        }
    }

    func refreshReadyState() {
        if ImagePackStore.isNeuralPackReady {
            phase = .ready
            progress = 1
        } else if case .failed = phase {
            // keep failure message until user retries
        } else if !isBusy {
            phase = .idle
            progress = 0
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        phase = .idle
        progress = 0
        currentFileName = ""
    }

    /// Remove installed pack (frees ~1–2 GB).
    func deleteInstalledPack() throws {
        cancel()
        let fm = FileManager.default
        if fm.fileExists(atPath: ImagePackStore.resourcesURL.path) {
            try fm.removeItem(at: ImagePackStore.resourcesURL)
        }
        let packRoot = ImagePackStore.packRootURL
        let zipCache = packRoot.appendingPathComponent("download")
        if fm.fileExists(atPath: zipCache.path) {
            try? fm.removeItem(at: zipCache)
        }
        ImagePackStore.clearManifest()
        if fm.fileExists(atPath: ImagePackStore.documentsPackURL.path) {
            try? fm.removeItem(at: ImagePackStore.documentsPackURL.deletingLastPathComponent())
        }
        AppSettings.illustrationPackInstalled = false
        CoreMLDiffusionIllustrator.unloadPipeline()
        phase = .idle
        progress = 0
        filesDone = 0
        filesTotal = 0
        bytesDownloaded = 0
        totalBytes = 0
    }

    /// Download the default anime-tuned pack (zip).
    func startDownload(
        repoID: String = ImagePackDownloader.defaultRepoID,
        zipFileName: String = ImagePackDownloader.defaultZipFileName
    ) {
        guard !isBusy else { return }
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            await self?.runAnimeZipDownload(repoID: repoID, zipFileName: zipFileName)
        }
    }

    // MARK: - Anime zip pipeline

    private func runAnimeZipDownload(repoID: String, zipFileName: String) async {
        phase = .listing
        progress = 0
        bytesDownloaded = 0
        totalBytes = 0
        filesDone = 0
        filesTotal = 1
        currentFileName = zipFileName

        do {
            // Optional size probe via tree API.
            if let size = try? await remoteFileSize(repoID: repoID, path: zipFileName) {
                totalBytes = Int64(size)
            }

            phase = .downloading
            let packRoot = ImagePackStore.packRootURL
            let downloadDir = packRoot.appendingPathComponent("download", isDirectory: true)
            try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)
            let zipURL = downloadDir.appendingPathComponent(zipFileName)

            // Re-download if missing or size mismatch.
            let needsDownload: Bool
            if FileManager.default.fileExists(atPath: zipURL.path), totalBytes > 0 {
                let attrs = try FileManager.default.attributesOfItem(atPath: zipURL.path)
                let existing = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                needsDownload = existing != totalBytes
            } else {
                needsDownload = !FileManager.default.fileExists(atPath: zipURL.path)
            }

            if needsDownload {
                let remote = resolveURL(repoID: repoID, path: zipFileName)
                try await downloadFile(from: remote, to: zipURL, expectedSize: totalBytes > 0 ? Int(totalBytes) : nil)
            } else if totalBytes > 0 {
                bytesDownloaded = totalBytes
                progress = 0.55
            }

            try Task.checkCancellation()
            phase = .extracting
            currentFileName = "extracting…"
            progress = max(progress, 0.55)

            // Wipe previous Resources (apple or incomplete anime).
            let destRoot = ImagePackStore.resourcesURL
            if FileManager.default.fileExists(atPath: destRoot.path) {
                try FileManager.default.removeItem(at: destRoot)
            }
            let extractScratch = packRoot.appendingPathComponent("extract_tmp", isDirectory: true)
            if FileManager.default.fileExists(atPath: extractScratch.path) {
                try FileManager.default.removeItem(at: extractScratch)
            }
            try FileManager.default.createDirectory(at: extractScratch, withIntermediateDirectories: true)

            let progressBox = ProgressBox()
            try await Task.detached(priority: .userInitiated) {
                try ZipExtractor.extract(
                    zipURL: zipURL,
                    to: extractScratch,
                    skipPathContains: ["SafetyChecker"]
                ) { frac in
                    progressBox.value = frac
                }
            }.value
            // Snapshot extract progress into UI (full extract already done).
            progress = 0.95
            _ = progressBox.value

            try Task.checkCancellation()
            phase = .verifying
            currentFileName = ""

            // Zip nests under AnythingV5Ink-…_compiled/ — promote models to Resources/.
            guard let modelsRoot = Self.findModelsRoot(in: extractScratch) else {
                throw DownloadError.incompletePack
            }
            try FileManager.default.createDirectory(
                at: destRoot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destRoot.path) {
                try FileManager.default.removeItem(at: destRoot)
            }
            try FileManager.default.moveItem(at: modelsRoot, to: destRoot)
            try? FileManager.default.removeItem(at: extractScratch)

            guard ImagePackStore.hasRequiredModels(at: destRoot) else {
                throw DownloadError.incompletePack
            }

            ImagePackStore.writeManifest(
                ImagePackStore.PackManifest(
                    id: Self.packKindID,
                    repoID: repoID,
                    zipFileName: zipFileName,
                    displayName: "Anything V5 Ink (anime)",
                    installedAt: ISO8601DateFormatter().string(from: Date())
                )
            )
            AppSettings.illustrationPackInstalled = true
            // Free zip after successful install to reclaim ~1.5 GB.
            try? FileManager.default.removeItem(at: zipURL)

            CoreMLDiffusionIllustrator.unloadPipeline()
            phase = .ready
            progress = 1
            packLog.info("Anime image pack ready at \(destRoot.path, privacy: .public)")
        } catch is CancellationError {
            phase = .idle
            progress = 0
        } catch {
            packLog.error("download failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Locate folder that contains TextEncoder.mlmodelc (+ tokenizer).
    private static func findModelsRoot(in root: URL) -> URL? {
        let fm = FileManager.default
        if ImagePackStore.hasRequiredModels(at: root) { return root }
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if url.lastPathComponent.hasSuffix(".mlmodelc") { continue }
            if ImagePackStore.hasRequiredModels(at: url) {
                return url
            }
        }
        return nil
    }

    // MARK: - HF helpers

    private struct HFTreeItem: Decodable {
        let type: String
        let path: String
        let size: Int?
    }

    private func remoteFileSize(repoID: String, path: String) async throws -> Int {
        var components = URLComponents(string: "https://huggingface.co/api/models/\(repoID)/tree/main")!
        components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        guard let url = components.url else { throw DownloadError.badURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        try throwIfHTTPError(response, data: data)

        let items = try JSONDecoder().decode([HFTreeItem].self, from: data)
        if let match = items.first(where: { $0.path == path || $0.path.hasSuffix("/" + path) }) {
            return match.size ?? 0
        }
        // Fallback: any zip matching filename
        if let match = items.first(where: { $0.path.hasSuffix(path) }) {
            return match.size ?? 0
        }
        return 0
    }

    private func resolveURL(repoID: String, path: String) -> URL {
        let encodedPath = path
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encodedPath)?download=true")!
    }

    private func downloadFile(from url: URL, to dest: URL, expectedSize: Int?) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3_600 // large pack
        let (tempURL, response) = try await session.download(for: request)
        try throwIfHTTPError(response, data: nil)

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)

        if let expectedSize, expectedSize > 0 {
            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard size == Int64(expectedSize) else {
                try? FileManager.default.removeItem(at: dest)
                throw DownloadError.sizeMismatch(expected: expectedSize, got: Int(size))
            }
            bytesDownloaded = size
            progress = 0.55
        } else if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
                  let size = attrs[.size] as? NSNumber {
            bytesDownloaded = size.int64Value
            totalBytes = max(totalBytes, size.int64Value)
            progress = 0.55
        }
    }

    private func throwIfHTTPError(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw DownloadError.http(http.statusCode, body)
        }
    }

    enum DownloadError: LocalizedError {
        case badURL
        case incompletePack
        case http(Int, String)
        case sizeMismatch(expected: Int, got: Int)

        var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid download URL."
            case .incompletePack: return "Download finished but the anime pack is incomplete."
            case .http(let code, let body):
                return "Download failed (HTTP \(code)). \(body.prefix(120))"
            case .sizeMismatch(let e, let g):
                return "File size mismatch (expected \(e), got \(g))."
            }
        }
    }
}

/// Thread-safe progress scratch for background zip extract.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Double = 0
    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

extension ImagePackDownloader {
    var progressPercent: Int { Int((progress * 100).rounded()) }

    var byteProgressLabel: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        if totalBytes > 0 {
            return "\(f.string(fromByteCount: bytesDownloaded)) / \(f.string(fromByteCount: totalBytes))"
        }
        if bytesDownloaded > 0 {
            return f.string(fromByteCount: bytesDownloaded)
        }
        return ""
    }
}
