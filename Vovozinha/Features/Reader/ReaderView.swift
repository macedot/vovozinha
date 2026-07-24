import SwiftUI
import SwiftData
import AVFoundation

struct ReaderView: View {
    @Bindable var story: Story
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var languageStore

    @State private var pageIndex = 0
    @State private var narrator = Narrator()
    @State private var showReadAloud = false
    @State private var pdfURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?

    private var pages: [StoryPage] { story.sortedPages }
    private var lang: AppLanguage { languageStore.language }

    var body: some View {
        ZStack {
            VovoTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                if pages.isEmpty {
                    Text(L10n.t(.readerEmptyPages, lang))
                        .foregroundStyle(VovoTheme.cream)
                        .padding()
                } else {
                    TabView(selection: $pageIndex) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            pageView(page)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))

                    controls
                        .padding()
                }
            }
        }
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if onClose != nil {
                    Button(L10n.t(.readerClose, lang)) {
                        narrator.stop()
                        onClose?()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.t(.readerListenPage, lang), systemImage: "speaker.wave.2.fill") {
                        speakCurrentPage()
                    }
                    Button(L10n.t(.readerAudiobook, lang), systemImage: "headphones") {
                        speakAll()
                    }
                    Button(L10n.t(.readerParentRead, lang), systemImage: "text.book.closed") {
                        showReadAloud = true
                    }
                    Button(L10n.t(.readerExportPDF, lang), systemImage: "doc.richtext") {
                        exportPDF()
                    }
                    Button(L10n.t(.readerDelete, lang), systemImage: "trash", role: .destructive) {
                        deleteStory()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(VovoTheme.cream)
                }
            }
        }
        .sheet(isPresented: $showReadAloud) {
            NavigationStack {
                ScrollView {
                    Text(story.fullText)
                        .font(.title3)
                        .foregroundStyle(VovoTheme.deepNight)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(VovoTheme.cream)
                .navigationTitle(L10n.t(.readerReadAloudTitle, lang))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.t(.readerClose, lang)) { showReadAloud = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let pdfURL {
                ShareSheet(items: [pdfURL])
            }
        }
        .alert(L10n.t(.readerOps, lang), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            // Prefer the language the story was written in (TTS voice).
            narrator.speechLanguage = story.language.speechLanguage
        }
        .onChange(of: languageStore.language) { _, _ in
            // Keep story language for narration even if UI bar changes mid-read.
            narrator.speechLanguage = story.language.speechLanguage
        }
        // Audiobook: follow the page the narrator is reading.
        .onChange(of: narrator.currentPageIndex) { _, newIndex in
            guard let newIndex, pages.indices.contains(newIndex) else { return }
            guard pageIndex != newIndex else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                pageIndex = newIndex
            }
        }
        .onDisappear {
            narrator.deactivateAudioSession()
        }
    }

    private func pageView(_ page: StoryPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // TEXT_ONLY_PHASE: show art only if a page image exists and graphics are enabled.
                if FeatureFlags.graphicsEnabled,
                   let path = page.imagePath,
                   let image = FileStorage.shared.loadImage(relativePath: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "text.book.closed.fill")
                            .foregroundStyle(VovoTheme.amber)
                        Text(L10n.t(.readerTextOnlyBanner, lang))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(VovoTheme.cream.opacity(0.55))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(VovoTheme.cardFill)
                    )
                }

                Text(L10n.format(.readerPageOf, lang, page.index + 1, pages.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VovoTheme.amber)

                Text(page.text)
                    .font(.title2)
                    .foregroundStyle(VovoTheme.cream)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                pageIndex = max(0, pageIndex - 1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 36))
            }
            .disabled(pageIndex == 0)

            Button {
                if narrator.isSpeaking {
                    narrator.stop()
                } else {
                    speakCurrentPage()
                }
            } label: {
                Image(systemName: narrator.isSpeaking ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(VovoTheme.amber)
            }

            Button {
                pageIndex = min(pages.count - 1, pageIndex + 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 36))
            }
            .disabled(pageIndex >= pages.count - 1)
        }
        .foregroundStyle(VovoTheme.cream)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(VovoTheme.cardFill)
        )
    }

    private func configureNarrator() {
        narrator.speechLanguage = story.language.speechLanguage
        narrator.reloadVoicePreference()
        // Stay near default rate — extreme values can produce empty audio buffers.
        narrator.rate = story.ageBand == .threeToFive
            ? AVSpeechUtteranceDefaultSpeechRate * 0.88
            : AVSpeechUtteranceDefaultSpeechRate * 0.95
        narrator.pitchMultiplier = 1.04
        narrator.sentencePause = 0.18
        // Pause between pages in full audiobook mode (turn the page, then continue).
        narrator.pageGap = story.ageBand == .threeToFive ? 1.1 : 0.85
    }

    private func speakCurrentPage() {
        guard pages.indices.contains(pageIndex) else { return }
        let text = pages[pageIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = L10n.t(.readerNothingToSpeak, lang)
            return
        }
        configureNarrator()
        narrator.speak(text: text, pageIndex: pageIndex)
    }

    private func speakAll() {
        let texts = pages.map(\.text)
        guard texts.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            errorMessage = L10n.t(.readerNothingToSpeak, lang)
            return
        }
        configureNarrator()
        // Start from the page the reader is on; UI will advance with narration.
        narrator.speakStory(pages: texts, startAt: pageIndex)
    }

    private func exportPDF() {
        do {
            let url = try PDFExporter.export(story: story)
            pdfURL = url
            showShare = true
        } catch {
            errorMessage = L10n.t(.readerExportFailed, lang)
        }
    }

    private func deleteStory() {
        narrator.stop()
        FileStorage.shared.deleteStoryFiles(storyID: story.id)
        modelContext.delete(story)
        try? modelContext.save()
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
