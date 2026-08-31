import Foundation
import ImageGenKit

/// Hands off between MLX and Core ML. One engine resident at a time.
public protocol MemorySequencing: Sendable {
    func releaseMLX() async
    func prepareCoreML() async throws
    func releaseCoreML() async
}

public struct MemorySequencer: MemorySequencing {
    public var coreMLReset: @Sendable () async -> Void
    public var mlxRelease: @Sendable () async -> Void

    public init(
        coreMLReset: @escaping @Sendable () async -> Void = {
            await CoreMLImageGenSession.resetCache()
        },
        mlxRelease: @escaping @Sendable () async -> Void = {}
    ) {
        self.coreMLReset = coreMLReset
        self.mlxRelease = mlxRelease
    }

    public func releaseMLX() async {
        await mlxRelease()
    }

    public func prepareCoreML() async throws {
        // Give Metal a beat to return buffers after MLX.Memory.clearCache().
        try await Task.sleep(nanoseconds: 250_000_000)
        await coreMLReset()
    }

    public func releaseCoreML() async {
        await coreMLReset()
    }
}
