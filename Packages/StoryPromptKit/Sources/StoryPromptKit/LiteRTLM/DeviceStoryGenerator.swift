import Foundation
import VovoUI

/// Production generator: **LiteRT-LM only**. No static / template story body.
///
/// - Model missing → `StoryPromptError.modelNotInstalled`
/// - Inference or parse failure → `StoryPromptError.generationFailed` (or underlying error)
/// - Never invents paragraphs without the model.
public struct DeviceStoryGenerator: StoryFromPromptGenerating {
    private let modelStore: LiteRTLMModelStore
    private let sessionProvider: @Sendable (String, String) throws -> any LiteRTLMEngineSessioning

    public init(modelStore: LiteRTLMModelStore = LiteRTLMModelStore()) {
        self.init(modelStore: modelStore, sessionProvider: DeviceStoryGenerator.defaultSessionProvider)
    }

    init(
        modelStore: LiteRTLMModelStore,
        sessionProvider: @escaping @Sendable (String, String) throws -> any LiteRTLMEngineSessioning
    ) {
        self.modelStore = modelStore
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

        guard await modelStore.isModelPresent() else {
            throw StoryPromptError.modelNotInstalled
        }

        #if canImport(LiteRTLM)
        let modelURL = await modelStore.modelFileURL()
        let cacheDir = await modelStore.cacheDirectory().path
        let session = try sessionProvider(modelURL.path, cacheDir)
        let litert = try LiteRTLMStoryGenerator(
            modelPath: modelURL.path,
            cacheDir: cacheDir,
            session: session
        )
        return try await litert.generate(from: prompt)
        #else
        // LiteRT-LM not linked on this platform — cannot invent a story.
        throw StoryPromptError.generationFailed
        #endif
    }
}
