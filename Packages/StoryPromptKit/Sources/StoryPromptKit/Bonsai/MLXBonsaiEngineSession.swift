import Foundation

/// Testable seam over the MLX Bonsai engine.
///
/// Generation is **100% on-device**. Networking is only for the one-time model pack
/// download handled by `BonsaiModelStore`, never for inference.
public protocol MLXBonsaiEngineSessioning: Sendable {
    /// Send `prompt` and return the model's full text reply.
    func send(_ prompt: String) async throws -> String
}

// MARK: - Concrete adapter

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#if canImport(MLXHuggingFace)
import MLXHuggingFace
#endif
#if canImport(Tokenizers)
import Tokenizers
#endif
#if canImport(MLXVLM)
import MLXVLM
#endif

/// Concrete MLX adapter for **prism-ml/Bonsai-27B-mlx-1bit** (local directory of safetensors).
///
/// Loads the model from disk on first `send`, generates with short max tokens suitable for
/// bedtime stories, then drops the container so subsequent runs can reclaim memory.
final class MLXBonsaiEngineSession: MLXBonsaiEngineSessioning, @unchecked Sendable {
    private let modelDirectory: URL

    /// Story band ~150–480 words + title/summary overhead; keep well below phone memory limits.
    static let defaultMaxTokens = 1024
    static let defaultTemperature: Float = 0.7
    static let defaultTopP: Float = 0.95
    static let defaultTopK = 20

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func send(_ prompt: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [modelDirectory] in
            let container = try await Self.loadContainer(from: modelDirectory)
            let parameters = GenerateParameters(
                maxTokens: Self.defaultMaxTokens,
                temperature: Self.defaultTemperature,
                topP: Self.defaultTopP,
                topK: Self.defaultTopK
            )
            // Prefer direct, non-thinking replies for bedtime latency.
            let instructions = """
            You are a careful children's bedtime story writer. Answer directly with the requested \
            story format only. Do not include chain-of-thought, analysis, or tool calls.
            """
            let session = ChatSession(
                container,
                instructions: instructions,
                generateParameters: parameters
            )
            return try await session.respond(to: prompt)
        }.value
    }

    private static func loadContainer(from directory: URL) async throws -> ModelContainer {
        let tokenizerLoader = try makeTokenizerLoader()

        // Bonsai 27B ships as qwen3_5 VLM weights; VLM factory handles that model_type.
        // Fall back to LLM factory if VLM is not linked.
        #if canImport(MLXVLM)
        do {
            return try await VLMModelFactory.shared.loadContainer(
                from: directory,
                using: tokenizerLoader
            )
        } catch {
            return try await LLMModelFactory.shared.loadContainer(
                from: directory,
                using: tokenizerLoader
            )
        }
        #else
        return try await LLMModelFactory.shared.loadContainer(
            from: directory,
            using: tokenizerLoader
        )
        #endif
    }

    private static func makeTokenizerLoader() throws -> any TokenizerLoader {
        #if canImport(MLXHuggingFace)
        // Macro expands to AutoTokenizer-backed loader (local directory; no hub download).
        return #huggingFaceTokenizerLoader()
        #else
        throw StoryPromptError.generationFailed
        #endif
    }
}
#endif
