import CryptoKit
import Foundation

/// Stable per-story seed. Never use Swift `hashValue` (randomized per process).
public enum StoryIdentity {
    public static func baseSeed(storyID: UUID) -> UInt32 {
        let digest = SHA256.hash(data: Data(storyID.uuidString.utf8))
        return digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    public static func pageSeed(storyID: UUID, pageIndex: Int) -> UInt32 {
        baseSeed(storyID: storyID) &+ UInt32(pageIndex)
    }
}
