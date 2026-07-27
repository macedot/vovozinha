import Foundation

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

// MARK: - Concrete adapter

#if canImport(LiteRTLM)
@preconcurrency import LiteRTLM

/// Concrete LiteRT-LM adapter (Metal `.gpu` backend).
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
        try await Task.detached(priority: .userInitiated) { [engine] in
            try await engine.initialize()
            let sampler = try SamplerConfig(
                topK: 40,
                topP: 0.95,
                temperature: 0.9,
                seed: Int.random(in: 1...Int(Int32.max))
            )
            let conversation = try await engine.createConversation(
                with: ConversationConfig(samplerConfig: sampler)
            )
            let response = try await conversation.sendMessage(Message(prompt))
            return response.toString
        }.value
    }

    static func defaultBackend() -> LiteRTLM.Backend { .gpu }
}
#endif
