import Foundation
@preconcurrency import LiteRTLM

/// Testable seam over the LiteRT-LM engine. The real adapter owns a long-lived
/// `LiteRTLM.Engine` (initialization is expensive — model compilation is cached to
/// `cacheDir`) and creates a fresh `Conversation` per call.
///
/// Generation is **100% on-device**. The only reason the network is ever involved is the
/// one-time model asset download handled by `LiteRTLMModelStore`, never inference.
public protocol LiteRTLMEngineSessioning: Sendable {
    /// Send `prompt` and return the model's full text reply.
    func send(_ prompt: String) async throws -> String
}

/// Concrete LiteRT-LM adapter.
///
/// Holds one `Engine` instance for its lifetime; `initialize()` is performed lazily on the
/// first `send(_:)` so a missing/unavailable model fails at generation, not at construction.
final class LiteRTLMEngineSession: LiteRTLMEngineSessioning, @unchecked Sendable {
    /// `Engine` is an actor; the reference itself is immutable and safe to capture across
    /// concurrency domains, hence `@unchecked Sendable`.
    private let engine: Engine

    init(
        modelPath: String,
        cacheDir: String,
        backend: LiteRTLM.Backend = LiteRTLMEngineSession.defaultBackend(),
        maxNumTokens: Int? = 2048
    ) throws {
        let config = try EngineConfig(
            modelPath: modelPath,
            backend: backend,
            maxNumTokens: maxNumTokens,
            cacheDir: cacheDir
        )
        self.engine = Engine(engineConfig: config)
    }

    func send(_ prompt: String) async throws -> String {
        // `Engine` is an actor; initialize() (expensive first time — model compile + cache) and
        // createConversation() hop onto it. Run off the main actor so the UI stays responsive.
        try await Task.detached(priority: .userInitiated) { [engine] in
            try await engine.initialize()
            let conversation = try await engine.createConversation()
            let response = try await conversation.sendMessage(Message(prompt))
            return response.toString
        }.value
    }

    /// Always the Metal/GPU backend.
    ///
    /// ⚠️ **LiteRT-LM does NOT work in the iOS Simulator** — the `.gpu` (Metal) backend is
    /// unsupported there, and we intentionally do not fall back to CPU. Run LiteRT-LM
    /// generation only on a physical device (iPhone 15+) after the one-time model download.
    /// In the simulator `OfflineFirstStoryGenerator` routes to the offline generator instead.
    static func defaultBackend() -> LiteRTLM.Backend { .gpu }
}
