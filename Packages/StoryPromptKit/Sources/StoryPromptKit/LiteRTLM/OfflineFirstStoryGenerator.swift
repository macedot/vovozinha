import Foundation
import VovoUI

/// Default generator for the apps: use **on-device LiteRT-LM** when the model is present,
/// and always fall back to the deterministic offline generator so the app works **100% offline**.
///
/// Decision rule (per `generate(from:)`):
/// 1. In the iOS Simulator → offline (the `.gpu` Metal backend doesn't work there).
/// 2. No model file on disk → offline (model not yet downloaded).
/// 3. Model present → LiteRT-LM; on **any** inference error → fall back to offline, never throw.
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

    /// Builds the real LiteRT-LM engine session. Internal so the public init's signature never
    /// references an internal type.
    static let defaultSessionProvider: @Sendable (String, String) throws -> any LiteRTLMEngineSessioning = { modelPath, cacheDir in
        try LiteRTLMEngineSession(modelPath: modelPath, cacheDir: cacheDir)
    }

    public func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        // Validate once here; both backends validate again but that's cheap and idempotent.
        try prompt.validate()

        // 1. ⚠️ LiteRT-LM does NOT work in the iOS Simulator (Metal `.gpu` backend unsupported,
        //    and we don't fall back to CPU). Route to the offline generator there. Run LiteRT-LM
        //    only on a physical device (iPhone 15+) after the one-time model download.
        #if targetEnvironment(simulator)
        return try await offline.generate(from: prompt)
        #else
        // 2. No model on disk → offline.
        guard await modelStore.isModelPresent() else {
            return try await offline.generate(from: prompt)
        }

        // 3. Model present → LiteRT-LM, fall back on any failure.
        let modelURL = await modelStore.modelFileURL()
        let cacheDir = await modelStore.cacheDirectory().path
        do {
            let session = try sessionProvider(modelURL.path, cacheDir)
            let litert = try LiteRTLMStoryGenerator(modelPath: modelURL.path, cacheDir: cacheDir, session: session)
            return try await litert.generate(from: prompt)
        } catch let e as StorySeedPrompt.ValidationError {
            // Propagate validation errors so UI messaging stays specific.
            throw e
        } catch {
            // Never let an LLM/runtime failure break the offline guarantee.
            return try await offline.generate(from: prompt)
        }
        #endif
    }
}
