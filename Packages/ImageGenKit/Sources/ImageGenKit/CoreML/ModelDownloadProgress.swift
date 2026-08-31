import Foundation

/// Live stats for an on-device image-pack download (host CDN path).
///
/// Mirrors StoryPromptKit's `ModelDownloadProgress` (this kit cannot import that type —
/// see the package isolation note on `ImageGenKit`). Same shape so the UI gate can reuse
/// the same progress rendering.
public struct ModelDownloadProgress: Sendable, Equatable {
    public enum Phase: String, Sendable, Equatable {
        case downloading
        case verifying
        case unpacking
        case finished
    }

    public var fraction: Double
    public var bytesReceived: Int64
    public var bytesTotal: Int64?
    public var bytesPerSecond: Double
    public var elapsed: TimeInterval
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

    public var formattedSpeed: String {
        Self.formatBytes(Int64(max(bytesPerSecond, 0).rounded()))
    }
    public var formattedReceived: String { Self.formatBytes(bytesReceived) }
    public var formattedTotal: String? { bytesTotal.map { Self.formatBytes($0) } }
    public var formattedElapsed: String { Self.formatDuration(elapsed) }
    public var formattedETA: String? { estimatedRemaining.map { Self.formatDuration($0) } }

    private static func formatBytes(_ count: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: count)
    }

    public static func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
