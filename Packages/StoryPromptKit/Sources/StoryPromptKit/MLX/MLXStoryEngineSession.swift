import Foundation

/// Testable seam over the on-device MLX story engine.
///
/// Generation is **100% on-device**. Networking is only for the one-time model pack
/// download handled by `OnDeviceMLXModelStore`, never for inference.
public protocol MLXStoryEngineSessioning: Sendable {
    /// Send `prompt` and return the model's full text reply.
    func send(_ prompt: String) async throws -> String
}

// MARK: - Concrete adapter

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLX
import MLXLLM
import MLXLMCommon
#if canImport(MLXVLM)
import MLXVLM
#endif

/// Concrete MLX adapter for **mlx-community/Qwen3.5-4B-MLX-4bit** (local directory of safetensors).
///
/// Loads the model from disk on first `send`, generates with short max tokens suitable for
/// bedtime stories, then drops the container so subsequent runs can reclaim memory.
final class MLXStoryEngineSession: MLXStoryEngineSessioning, @unchecked Sendable {
    private let modelDirectory: URL

    /// Story band ~150–480 words + title/summary + format overhead.
    /// With thinking disabled this is enough for 10 short paragraphs; leave headroom.
    static let defaultMaxTokens = 1536
    static let defaultTemperature: Float = 0.7
    static let defaultTopP: Float = 0.95
    static let defaultTopK = 20

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func send(_ prompt: String) async throws -> String {
        // Runs after the detached task finishes and the container is dropped: return MLX's
        // cached Metal buffers to the OS so repeated generations don't stack residency.
        defer { MLX.Memory.clearCache() }
        return try await Task.detached(priority: .userInitiated) { [modelDirectory] in
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
            // Qwen3.5 chat template defaults to open-ended <think> unless disabled —
            // that burns maxTokens on reasoning and leaves zero story paragraphs.
            let session = ChatSession(
                container,
                instructions: instructions,
                generateParameters: parameters,
                additionalContext: ["enable_thinking": false]
            )
            let text = try await session.respond(to: prompt)
            #if DEBUG
            print(
                "[MLXStory] raw reply chars=\(text.count) preview=\(text.prefix(240).replacingOccurrences(of: "\n", with: "⏎"))"
            )
            #endif
            return text
        }.value
    }

    private static func loadContainer(from directory: URL) async throws -> ModelContainer {
        let tokenizerLoader = makeTokenizerLoader()

        // Text-only generation: load through the **LLM** factory. Its Qwen3.5 `sanitize`
        // drops the `vision_tower` weights (~0.7 GB of the pack — dead memory for a text-only
        // app) before they ever materialize. Fall back to the VLM factory only if the LLM
        // path can't load the pack.
        do {
            return try await LLMModelFactory.shared.loadContainer(
                from: directory,
                using: tokenizerLoader
            )
        } catch {
            #if canImport(MLXVLM)
            return try await VLMModelFactory.shared.loadContainer(
                from: directory,
                using: tokenizerLoader
            )
            #else
            throw error
            #endif
        }
    }

    private static func makeTokenizerLoader() -> any TokenizerLoader {
        HuggingFaceTokenizerLoader()
    }
}
#endif
