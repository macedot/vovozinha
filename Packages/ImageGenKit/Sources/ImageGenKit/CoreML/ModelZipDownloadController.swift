import Foundation

// MARK: - Large zip download (session delegate + polled progress)

/// Thread-safe live counters for UI polling (session queue writes, download task reads).
/// Faithful port of StoryPromptKit's helper (this kit is dependency-isolated).
final class ModelZipDownloadLiveState: @unchecked Sendable {
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
        if let total, total > 0 { self.total = total }
        lock.unlock()
    }

    func markFinished(received: Int64? = nil, total: Int64? = nil) {
        lock.lock()
        if let received { self.received = max(self.received, received) }
        if let total, total > 0 { self.total = total }
        finished = true
        lock.unlock()
    }

    func snapshot(phase: ModelDownloadProgress.Phase) -> ModelDownloadProgress {
        lock.lock()
        let received = self.received
        let total = self.total
        lock.unlock()
        return CoreMLImagePackStore.snapshot(
            started: started, received: received, total: total, phase: phase
        )
    }
}

/// One-shot multi-GB download via `URLSessionDownloadDelegate`.
///
/// The session retains this object as its delegate for the lifetime of the task; the cycle
/// is broken with `finishTasksAndInvalidate()` when settled. Progress is published only via
/// `live` (polled by the caller).
final class ModelZipDownloadController: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
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
        config.allowsConstrainedNetworkAccess = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 6

        let queue = OperationQueue()
        queue.name = "app.vovozinha.ImagePackDownload"
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
            settle(.failure(CoreMLImagePackStore.DownloadError.http(statusCode: http.statusCode)))
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
                settle(.failure(CoreMLImagePackStore.DownloadError.emptyFile))
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

        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
