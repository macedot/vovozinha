import Foundation

public enum ModelDownloadError: Error, LocalizedError, Equatable, Sendable {
    case http(statusCode: Int)
    case emptyFile
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .http(let code):
            return "Download failed (HTTP \(code))."
        case .emptyFile:
            return "Downloaded file is empty."
        case .cancelled:
            return "Download was cancelled."
        }
    }
}

/// Thread-safe live counters for UI polling during model downloads.
public final class ModelZipDownloadLiveState: @unchecked Sendable {
    private let lock = NSLock()
    private let started: Date
    private var received: Int64 = 0
    private var total: Int64?
    private var finished = false

    public init(started: Date) {
        self.started = started
    }

    public var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    public func update(received: Int64, total: Int64?) {
        lock.lock()
        self.received = max(self.received, received)
        if let total, total > 0 { self.total = total }
        lock.unlock()
    }

    public func markFinished(received: Int64? = nil, total: Int64? = nil) {
        lock.lock()
        if let received { self.received = max(self.received, received) }
        if let total, total > 0 { self.total = total }
        finished = true
        lock.unlock()
    }

    public func snapshot(phase: ModelDownloadProgress.Phase) -> ModelDownloadProgress {
        lock.lock()
        let received = self.received
        let total = self.total
        lock.unlock()
        return Self.calculateSnapshot(
            started: started, received: received, total: total, phase: phase
        )
    }

    public static func calculateSnapshot(
        started: Date,
        received: Int64,
        total: Int64?,
        phase: ModelDownloadProgress.Phase,
        fractionOverride: Double? = nil
    ) -> ModelDownloadProgress {
        let elapsed = max(Date().timeIntervalSince(started), 0.001)
        let bps = Double(received) / elapsed
        let fraction: Double
        if let fractionOverride {
            fraction = fractionOverride
        } else if let total, total > 0 {
            fraction = min(Double(received) / Double(total) * 0.92, 0.92)
        } else {
            fraction = 0
        }
        var eta: TimeInterval?
        if phase == .downloading, let total, total > received, bps > 1 {
            eta = Double(total - received) / bps
        } else if phase == .finished {
            eta = 0
        }
        return ModelDownloadProgress(
            fraction: fraction,
            bytesReceived: received,
            bytesTotal: total,
            bytesPerSecond: bps,
            elapsed: elapsed,
            estimatedRemaining: eta,
            phase: phase
        )
    }
}

/// One-shot multi-GB download via `URLSessionDownloadDelegate`.
public final class ModelZipDownloadController: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public struct Outcome: Sendable {
        public var bytesReceived: Int64
        public var bytesTotal: Int64?

        public init(bytesReceived: Int64, bytesTotal: Int64?) {
            self.bytesReceived = bytesReceived
            self.bytesTotal = bytesTotal
        }
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

    public static func download(
        request: URLRequest,
        destinationURL: URL,
        live: ModelZipDownloadLiveState
    ) async throws -> Outcome {
        let box = NSLock()
        var activeController: ModelZipDownloadController?
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                let controller = ModelZipDownloadController(
                    destinationURL: destinationURL,
                    live: live,
                    continuation: cont
                )
                box.lock()
                if Task.isCancelled {
                    box.unlock()
                    live.markFinished()
                    cont.resume(throwing: CancellationError())
                    return
                }
                activeController = controller
                controller.start(request: request)
                box.unlock()
            }
        } onCancel: {
            box.lock()
            let c = activeController
            box.unlock()
            c?.cancel()
        }
    }

    private func start(request: URLRequest) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 6 * 60 * 60
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 6

        let queue = OperationQueue()
        queue.name = "app.vovozinha.ModelZipDownload"
        queue.maxConcurrentOperationCount = 1

        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.downloadTask(with: request)
        progressObservation = task.progress.observe(\.completedUnitCount, options: [.new]) { [live] progress, _ in
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            live.update(received: completed, total: total > 0 ? total : nil)
        }
        task.resume()
    }

    public func urlSession(
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

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            live.markFinished()
            settle(.failure(ModelDownloadError.http(statusCode: http.statusCode)))
            return
        }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: location, to: destinationURL)

            let attrs = try fm.attributesOfItem(atPath: destinationURL.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else {
                live.markFinished()
                settle(.failure(ModelDownloadError.emptyFile))
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

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            live.markFinished()
            settle(.failure(error))
        }
    }

    private func settle(_ result: Result<Outcome, Error>) {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true
        progressObservation?.invalidate()
        progressObservation = nil
        let session = self.session
        self.session = nil
        lock.unlock()

        session?.invalidateAndCancel()
        continuation.resume(with: result)
    }

    public func cancel() {
        live.markFinished()
        settle(.failure(CancellationError()))
    }
}
