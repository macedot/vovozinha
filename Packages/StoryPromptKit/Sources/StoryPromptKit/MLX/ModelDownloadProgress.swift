import Foundation

/// Live stats for an on-device model pack download (host CDN path).
public struct ModelDownloadProgress: Sendable, Equatable {
    public enum Phase: String, Sendable, Equatable {
        /// Streaming bytes from the host.
        case downloading
        /// SHA-256 check of the zip (host downloads only).
        case verifying
        /// Unzipping into the app sandbox.
        case unpacking
        case finished
    }

    /// Overall UI fraction in `0...1` (download band uses most of the bar; verify/unpack share the end).
    public var fraction: Double
    public var bytesReceived: Int64
    /// `nil` when the server does not send `Content-Length`.
    public var bytesTotal: Int64?
    /// Average throughput so far (bytes/sec). `0` until the first sample.
    public var bytesPerSecond: Double
    public var elapsed: TimeInterval
    /// `nil` when total size or speed is unknown / not yet stable.
    public var estimatedRemaining: TimeInterval?
    public var phase: Phase

    public init(
        fraction: Double = 0,
        bytesReceived: Int64 = 0,
        bytesTotal: Int64? = nil,
        bytesPerSecond: Double = 0,
        elapsed: TimeInterval = 0,
        estimatedRemaining: TimeInterval? = nil,
        phase: Phase = .downloading
    ) {
        self.fraction = min(max(fraction, 0), 1)
        self.bytesReceived = max(0, bytesReceived)
        self.bytesTotal = bytesTotal.map { max(0, $0) }
        self.bytesPerSecond = max(0, bytesPerSecond)
        self.elapsed = max(0, elapsed)
        self.estimatedRemaining = estimatedRemaining.map { max(0, $0) }
        self.phase = phase
    }

    public static let zero = ModelDownloadProgress()

    // MARK: - Formatting (locale-agnostic numbers; labels come from L10n)

    public var formattedSpeed: String {
        guard bytesPerSecond > 0 else { return Self.formatBytes(0) }
        return Self.formatBytes(Int64(bytesPerSecond.rounded()))
    }

    public var formattedReceived: String {
        Self.formatBytes(bytesReceived)
    }

    public var formattedTotal: String? {
        guard let bytesTotal else { return nil }
        return Self.formatBytes(bytesTotal)
    }

    private static func formatBytes(_ count: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: count)
    }

    public var formattedElapsed: String {
        Self.formatDuration(elapsed)
    }

    public var formattedETA: String? {
        guard let estimatedRemaining else { return nil }
        return Self.formatDuration(estimatedRemaining)
    }

    /// `m:ss` or `h:mm:ss`.
    public static func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
