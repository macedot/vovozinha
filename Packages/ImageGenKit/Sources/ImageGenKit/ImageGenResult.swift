import Foundation
import CoreGraphics

/// A generated image plus the provenance needed to reproduce it.
public struct ImageGenResult: Identifiable, Sendable {
    public let id: UUID
    /// Output bitmap. PNG-encodable via `ImageGenResult.pngData()`.
    public let cgImage: CGImage
    /// The seed actually used (resolved from `config.seed` or randomly drawn).
    public let seed: UInt32
    /// Wall-clock seconds spent in the diffusion pipeline (excludes model load).
    public let elapsedSeconds: Double
    /// The bucket the source was resized into.
    public let bucket: ImageGenBucket

    public init(
        id: UUID = UUID(),
        cgImage: CGImage,
        seed: UInt32,
        elapsedSeconds: Double,
        bucket: ImageGenBucket
    ) {
        self.id = id
        self.cgImage = cgImage
        self.seed = seed
        self.elapsedSeconds = elapsedSeconds
        self.bucket = bucket
    }
}
