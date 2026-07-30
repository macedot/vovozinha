import Foundation
import VovoUI

/// Short on-device caption for a photo (persons → objects → scene).
public struct PhotoCaption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let language: AppLanguage
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        language: AppLanguage,
        createdAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.language = language
        self.createdAt = createdAt
    }
}
