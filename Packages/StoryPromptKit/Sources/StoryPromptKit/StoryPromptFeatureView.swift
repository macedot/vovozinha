import SwiftUI
import VovoUI

/// UI surface for the Story Prompt feature (used by main app + DEBUG harness).
public struct StoryPromptFeatureView: View {
    @State private var promptText = ""
    @State private var isGenerating = false
    @State private var draft: StoryDraft?
    @State private var errorMessage: String?
    @State private var generator: any StoryFromPromptGenerating

    public init(generator: (any StoryFromPromptGenerating)? = nil) {
        _generator = State(initialValue: generator ?? OfflineStoryFromPromptGenerator())
    }

    private var seed: StorySeedPrompt { StorySeedPrompt(text: promptText) }

    private var wordCount: Int { seed.wordCount }

    private var canGenerate: Bool { seed.isValid && !isGenerating }

    public var body: some View {
        VovoScreen(
            title: "Story seed",
            subtitle: "Describe the base of the story in \(StorySeedPrompt.minWords)–\(StorySeedPrompt.maxWords) words."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                TextField(
                    "A cozy idea for a gentle bedtime story…",
                    text: $promptText,
                    axis: .vertical
                )
                .lineLimit(4...8)
                .frame(minHeight: 120, alignment: .topLeading)
                .vovoCardField()
                .accessibilityIdentifier("storySeedField")

                HStack {
                    Text("\(wordCount) / \(StorySeedPrompt.maxWords) words")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(wordCountLabelColor)
                        .accessibilityIdentifier("wordCountLabel")
                    Spacer()
                    if wordCount > 0, wordCount < StorySeedPrompt.minWords {
                        Text("Need at least \(StorySeedPrompt.minWords)")
                            .font(.caption)
                            .foregroundStyle(VovoTheme.softPink)
                    } else if wordCount > StorySeedPrompt.maxWords {
                        Text("Too long (max \(StorySeedPrompt.maxWords))")
                            .font(.caption)
                            .foregroundStyle(VovoTheme.softPink)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(VovoTheme.softPink)
                }

                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .tint(VovoTheme.deepNight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    } else {
                        Text("Create story")
                    }
                }
                .buttonStyle(VovoPrimaryButtonStyle(enabled: canGenerate))
                .disabled(!canGenerate)
                .accessibilityIdentifier("createStoryButton")

                if let draft {
                    storyResult(draft)
                        .accessibilityIdentifier("storyResult")
                }
            }
        }
    }

    private var wordCountLabelColor: Color {
        if seed.isValid { return VovoTheme.mint }
        if wordCount == 0 { return VovoTheme.cream.opacity(0.5) }
        return VovoTheme.amber
    }

    @ViewBuilder
    private func storyResult(_ draft: StoryDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.title)
                .font(.title3.bold())
                .foregroundStyle(VovoTheme.amber)
            Text(draft.summary)
                .font(.subheadline)
                .foregroundStyle(VovoTheme.cream.opacity(0.8))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(draft.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scene \(index + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(VovoTheme.mint.opacity(0.9))
                            Text(paragraph)
                                .font(.body)
                                .foregroundStyle(VovoTheme.cream)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(VovoTheme.cardFill)
                        )
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(.top, 8)
    }

    @MainActor
    private func generate() async {
        errorMessage = nil
        draft = nil
        let seed = StorySeedPrompt(text: promptText)
        do {
            try seed.validate()
        } catch let e as StorySeedPrompt.ValidationError {
            errorMessage = validationMessage(e)
            return
        } catch {
            errorMessage = "Invalid prompt."
            return
        }

        isGenerating = true
        defer { isGenerating = false }
        do {
            draft = try await generator.generate(from: seed)
        } catch let e as StorySeedPrompt.ValidationError {
            errorMessage = validationMessage(e)
        } catch {
            errorMessage = "Could not create the story. Try again."
        }
    }

    private func validationMessage(_ error: StorySeedPrompt.ValidationError) -> String {
        switch error {
        case .tooShort(let n):
            return "Use at least \(StorySeedPrompt.minWords) words (now \(n))."
        case .tooLong(let n):
            return "Use at most \(StorySeedPrompt.maxWords) words (now \(n))."
        }
    }
}

#Preview {
    StoryPromptFeatureView()
}
