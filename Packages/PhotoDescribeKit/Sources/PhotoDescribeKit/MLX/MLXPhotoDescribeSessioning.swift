import Foundation
import CoreImage

/// Testable seam over the on-device MLX VLM for photo captions.
public protocol MLXPhotoDescribeSessioning: Sendable {
    /// Describe `image` with `prompt` and return the model's text reply.
    func send(prompt: String, image: CIImage) async throws -> String
}
