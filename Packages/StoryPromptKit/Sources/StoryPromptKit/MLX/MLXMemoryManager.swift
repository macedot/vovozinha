import Foundation

#if canImport(MLX)
import MLX
#endif

/// Controls memory reclamation for on-device MLX neural models.
public enum MLXMemoryManager: Sendable {
    /// Flushes MLX's cached Metal buffers back to the OS.
    public static func releaseMemory() async {
        #if canImport(MLX)
        MLX.Memory.clearCache()
        #endif
    }
}
