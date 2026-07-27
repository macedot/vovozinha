import Foundation
import VovoUI

/// Production generator: **Bonsai MLX only**. No static / template story body.
///
/// - Model missing → `StoryPromptError.modelNotInstalled`
/// - Inference or parse failure → `StoryPromptError.generationFailed` (or underlying error)
/// - Never invents paragraphs without the model.
public struct DeviceStoryGenerator: StoryFromPromptGenerating {
    private let modelStore: BonsaiModelStore
    private let sessionProvider: @Sendable (URL) throws -> any MLXBonsaiEngineSessioning

    public init(modelStore: BonsaiModelStore = BonsaiModelStore()) {
        self.init(modelStore: modelStore, sessionProvider: DeviceStoryGenerator.defaultSessionProvider)
    }

    init(
        modelStore: BonsaiModelStore,
        sessionProvider: @escaping @Sendable (URL) throws -> any MLXBonsaiEngineSessioning
    ) {
        self.modelStore = modelStore
        self.sessionProvider = sessionProvider
    }

    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    static let defaultSessionProvider: @Sendable (URL) throws -> any MLXBonsaiEngineSessioning = { dir in
        MLXBonsaiEngineSession(modelDirectory: dir)
    }
    #else
    static let defaultSessionProvider: @Sendable (URL) throws -> any MLXBonsaiEngineSessioning = { _ in
        throw StoryPromptError.generationFailed
    }
    #endif

    public func generate(from prompt: StorySeedPrompt) async throws -> StoryDraft {
        try prompt.validate()

        guard await modelStore.isModelPresent() else {
            throw StoryPromptError.modelNotInstalled
        }

        let modelDir = await modelStore.modelDirectory()
        let session = try sessionProvider(modelDir)
        let generator = try MLXBonsaiStoryGenerator(modelDirectory: modelDir, session: session)
        return try await generator.generate(from: prompt)
    }
}
