import Foundation
import VovoUI

/// Feature boundary: local photo → short on-device caption (VLM only).
public protocol PhotoDescribing: Sendable {
    func describe(_ image: PhotoDescribeInput, language: AppLanguage) async throws -> PhotoCaption
}

public enum PhotoDescribeError: Error, Equatable, Sendable {
    case invalidImage
    /// Model missing, inference failed, or empty / unusable caption.
    case describeFailed
    /// On-device MLX story/VLM model pack is not installed yet.
    case modelNotInstalled
}
