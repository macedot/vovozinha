import SwiftUI
import SwiftData
import os

private let generationLog = Logger(subsystem: "app.vovozinha", category: "Generation")

struct GenerationView: View {
    let draft: StoryDraftInput
    /// Clears create-flow covers and returns to the main app (library tab).
    var onExitToMain: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageStore.self) private var languageStore

    @State private var service = StoryGenerationService.makeDefault()
    @State private var finishedStory: Story?
    @State private var presentedReader: ReaderPresentation?
    @State private var errorMessage: String?
    @State private var hasStarted = false

    /// UI language follows the language bar (not only the draft snapshot).
    private var lang: AppLanguage { languageStore.language }

    var body: some View {
        ZStack {
            // Solid base so the sheet is never empty black/transparent.
            VovoTheme.deepNight.ignoresSafeArea()
            VovoTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 28) {
                        headerBlock
                        progressBlock
                        stepsBlock
                        statusFooter
                        actionButtons
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await run()
        }
        .fullScreenCover(item: $presentedReader) { presentation in
            NavigationStack {
                ReaderView(story: presentation.story, onClose: {
                    // Closing the book leaves the whole generate flow → main window.
                    exitToMain()
                })
            }
            .environment(\.modelContext, modelContext)
            .preferredColorScheme(.dark)
        }
    }

    /// Dismiss generation + reader covers and return to the main app shell.
    private func exitToMain() {
        presentedReader = nil
        if let onExitToMain {
            onExitToMain()
        } else {
            dismiss()
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Button {
                exitToMain()
            } label: {
                Text(isTerminal ? L10n.t(.genClose, lang) : L10n.t(.genCancel, lang))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VovoTheme.cream.opacity(0.9))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            Spacer()
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(VovoTheme.amber.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(VovoTheme.amber)
                    .symbolRenderingMode(.hierarchical)
            }

            Text(headline)
                .font(.title2.bold())
                .foregroundStyle(VovoTheme.cream)
                .multilineTextAlignment(.center)

            Text(stageTitle)
                .font(.body)
                .foregroundStyle(VovoTheme.cream.opacity(0.85))
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: stageTitle)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var stageTitle: String {
        switch service.stage {
        case .idle: return L10n.t(.genCreating, lang)
        case .analyzingCharacter: return L10n.t(.genStepCharacter, lang) + "…"
        case .planningStory: return L10n.t(.genStepStory, lang) + "…"
        case .illustrating(let page, let total):
            return "\(L10n.t(.genStepArt, lang)) (\(page)/\(total))…"
        case .saving: return L10n.t(.genStepSave, lang) + "…"
        case .finished: return L10n.t(.genReady, lang)
        case .failed(let message): return message
        }
    }

    private var progressBlock: some View {
        VStack(spacing: 12) {
            ProgressView(value: max(service.stage.progress, service.isRunning ? 0.05 : 0))
                .tint(VovoTheme.amber)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)

            Text("\(Int(service.stage.progress * 100))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(VovoTheme.amber)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(VovoTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VovoTheme.cardStroke)
                )
        )
    }

    private var stepsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(
                title: L10n.t(.genStepCharacter, lang),
                state: stepState(for: .character)
            )
            stepRow(
                title: L10n.t(.genStepStory, lang),
                state: stepState(for: .plan)
            )
            if FeatureFlags.graphicsEnabled {
                stepRow(
                    title: illustrationStepTitle,
                    state: stepState(for: .illustrate)
                )
            }
            stepRow(
                title: L10n.t(.genStepSave, lang),
                state: stepState(for: .save)
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(VovoTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VovoTheme.cardStroke)
                )
        )
    }

    private var statusFooter: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(VovoTheme.softPink)
                    .multilineTextAlignment(.center)
            }

            Text(service.deviceProfile.statusSummary(lang: lang))
                .font(.caption2)
                .foregroundStyle(VovoTheme.cream.opacity(0.45))
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let finishedStory {
            VStack(spacing: 12) {
                Button(L10n.t(.genOpenBook, lang)) {
                    presentedReader = ReaderPresentation(story: finishedStory)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(L10n.t(.genBack, lang)) {
                    exitToMain()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 8)
        } else if case .failed = service.stage {
            VStack(spacing: 12) {
                Button(L10n.t(.genRetry, lang)) {
                    Task { await run() }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(L10n.t(.genClose, lang)) {
                    exitToMain()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Step helpers

    private enum PipelineStep {
        case character, plan, illustrate, save
    }

    private enum StepUIState {
        case pending, active, done, failed
    }

    private func stepState(for step: PipelineStep) -> StepUIState {
        if case .failed = service.stage { return .failed }
        switch step {
        case .character:
            switch service.stage {
            case .idle: return .pending
            case .analyzingCharacter: return .active
            default: return .done
            }
        case .plan:
            switch service.stage {
            case .idle, .analyzingCharacter: return .pending
            case .planningStory: return .active
            default: return .done
            }
        case .illustrate:
            switch service.stage {
            case .idle, .analyzingCharacter, .planningStory: return .pending
            case .illustrating: return .active
            case .saving, .finished: return .done
            case .failed: return .failed
            }
        case .save:
            switch service.stage {
            case .saving: return .active
            case .finished: return .done
            case .failed: return .failed
            default: return .pending
            }
        }
    }

    private func stepRow(title: String, state: StepUIState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stepIcon(state))
                .foregroundStyle(stepColor(state))
                .frame(width: 22)
            Text(title)
                .font(.subheadline.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(state == .pending ? VovoTheme.cream.opacity(0.45) : VovoTheme.cream)
            Spacer()
        }
    }

    private func stepIcon(_ state: StepUIState) -> String {
        switch state {
        case .pending: return "circle"
        case .active: return "circle.dotted"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func stepColor(_ state: StepUIState) -> Color {
        switch state {
        case .pending: return VovoTheme.cream.opacity(0.35)
        case .active: return VovoTheme.amber
        case .done: return VovoTheme.mint
        case .failed: return VovoTheme.softPink
        }
    }

    private var illustrationStepTitle: String {
        let base = L10n.t(.genStepArt, lang)
        if case .illustrating(let page, let total) = service.stage {
            return "\(base) (\(page)/\(total))"
        }
        return base
    }

    private var headline: String {
        switch service.stage {
        case .finished: return L10n.t(.genReady, lang)
        case .failed: return L10n.t(.genFailed, lang)
        default: return L10n.t(.genCreating, lang)
        }
    }

    private var iconName: String {
        switch service.stage {
        case .finished: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .illustrating: return "paintbrush.pointed.fill"
        case .planningStory: return "book.fill"
        case .saving: return "arrow.down.doc.fill"
        default: return "sparkles"
        }
    }

    private var isTerminal: Bool {
        switch service.stage {
        case .finished, .failed: return true
        default: return false
        }
    }

    // MARK: - Run

    private func run() async {
        errorMessage = nil
        finishedStory = nil
        service.reset()
        generationLog.info("Generation started for actor=\(self.draft.resolvedActorName(), privacy: .public)")

        do {
            // Prefer UI language for generation too, so story language matches the bar.
            var input = draft
            input.language = lang
            let story = try await service.generate(input: input, modelContext: modelContext)
            finishedStory = story
            generationLog.info("Generation finished id=\(story.id.uuidString, privacy: .public)")
        } catch let analysis as CharacterAnalysisError {
            let msg = analysis.localizedDescription(for: lang)
            generationLog.error("Generation failed: \(msg, privacy: .public)")
            errorMessage = msg
            service.stage = .failed(msg)
        } catch {
            // Never show raw system/English FM strings (e.g. context/transcript exceeded).
            let planning = StoryPlanningError.from(systemError: error)
            let msg = planning.localizedDescription(for: lang)
            generationLog.error("Generation failed: \(msg, privacy: .public) raw=\(String(describing: error), privacy: .public)")
            errorMessage = msg
            service.stage = .failed(msg)
        }
    }
}

/// Holds a generated story for item-based fullScreenCover (avoids empty/black sheet).
struct ReaderPresentation: Identifiable {
    let id: UUID
    let story: Story

    init(story: Story) {
        self.id = story.id
        self.story = story
    }
}
