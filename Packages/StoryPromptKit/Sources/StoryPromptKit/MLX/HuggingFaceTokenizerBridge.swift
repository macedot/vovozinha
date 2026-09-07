import Foundation
import MLXLMCommon
import Tokenizers

/// Local-folder tokenizer loader (no MLXHuggingFace macros — avoids Xcode “enable macro” gate).
public struct HuggingFaceTokenizerLoader: MLXLMCommon.TokenizerLoader, Sendable {
    public init() {}

    public func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return HuggingFaceTokenizerBridge(upstream)
    }
}

/// Adapts `Tokenizers.Tokenizer` to `MLXLMCommon.Tokenizer`.
public struct HuggingFaceTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    public init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    public func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    public func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    public func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    public func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    public var bosToken: String? { upstream.bosToken }
    public var eosToken: String? { upstream.eosToken }
    public var unknownToken: String? { upstream.unknownToken }

    public func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
