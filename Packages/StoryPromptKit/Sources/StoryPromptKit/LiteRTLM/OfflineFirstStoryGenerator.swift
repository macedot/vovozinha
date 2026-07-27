import Foundation
import VovoUI

/// Default generator for the apps: use **on-device LiteRT-LM** when the model is present,
/// and fall back to the deterministic offline generator so the app stays usable without a model.
///
/// Decision rule (per `generate(from:)`):
/// 1. No model file on disk → offline (model not yet downloaded).
/// 2. Model present → LiteRT-LM; on **any** inference error → offline (never throws for LLM failures).
///
/// Validation errors (`StorySeedPrompt.ValidationError`) are always propagated unchanged so the
/// UI's specific too-short/too-long messaging keeps working.
public struct OfflineFirstStoryGenerator: StoryFromPromptGenerating {
    private let modelStore: LiteRTLMModelStore
    private let offline: OfflineStoryFromPromptGenerator
    private let sessionProvider: @Sendable (String, String) throws -> any LiteRTLMEngineSessioning

    /// Default for apps: on-device LiteRT-LM when its model is present, offline fallback otherwise.
    public init(
        modelStore: LiteRTLMModelStore = LiteRTLMModelStore(),
        offline: OfflineStoryFromPromptGenerator = OfflineStoryFromPromptGenerator()
    ) {
        self.init(modelStore: modelStore, offline: offline, sessionProvider: OfflineFirstStoryGenerator.defaultSessionProvider)
    }

    /// Internal initializer that accepts a session provider (for tests / DEBUG injection).
    init(
        modelStore: LiteRTLMModelStore,
        offline: OfflineStoryFromPromptGenerator,
        sessionProvider: @escaping @Sendable (String, String) throws -> any LiteRTLMEngineSessioning
    ) {
        self.modelStore = modelStore
        self.offline = offline
        self.sessionProvider = sessionProvider
    }

    #if canImport(LiteRTLM)
    static let defaultSessionProvider: @Sendable (String, String) throws -> any LiteRTLMEngineSessioning = { modelPath, cacheDir in
        try LiteRTLMEngineSession(modelPath: modelPath, cacheDir: cacheDir)
    }
    #else
    static let defaultSessionProvider: @Sendable (String, String) throws -> any LiteRTLMEngineSessioning = { _, _ in
        throw StoryPromptError.generationFailed
    }
    #endif

    public func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        try prompt.validate()

        #if canImport(LiteRTLM)
        guard await modelStore.isModelPresent() else {
            return try await offline.generate(from: prompt)
        }

        let modelURL = await modelStore.modelFileURL()
        let cacheDir = await modelStore.cacheDirectory().path
        do {
            let session = try sessionProvider(modelURL.path, cacheDir)
            let litert = try LiteRTLMStoryGenerator(modelPath: modelURL.path, cacheDir: cacheDir, session: session)
            return try await litert.generate(from: prompt)
        } catch let e as StorySeedPrompt.ValidationError {
            throw e
        } catch {
            return try await offline.generate(from: prompt)
        }
        #else
        return try await offline.generate(from: prompt)
        #endif
    }
}
