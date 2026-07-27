import SwiftUI
import StoryPromptKit
import VovoUI

/// DEBUG harness: runs `StoryPromptKit` alone with the shared Vovo visual template.
///
/// Injects `DeviceStoryGenerator` (LiteRT-LM only — no static stories) and a model-download
/// control so generation can run after the one-time model fetch.
@main
struct StoryPromptDebugApp: App {
    @State private var languageStore = LanguageStore()
    @State private var modelStore = LiteRTLMModelStore()
    @State private var showModelSheet = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StoryPromptFeatureView(generator: DeviceStoryGenerator(modelStore: modelStore))
                    .navigationTitle("StoryPrompt · Debug")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbarBackground(VovoTheme.deepNight.opacity(0.9), for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showModelSheet = true
                            } label: {
                                Image(systemName: "internaldrive")
                            }
                            .accessibilityLabel("LiteRT-LM model")
                        }
                    }
            }
            .environment(languageStore)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showModelSheet) {
                LiteRTLMModelSheet(modelStore: modelStore)
            }
        }
    }
}

/// DEBUG-only: shows whether the Gemma 3n E2B model is on disk and lets you download /
/// remove it. Generation stays on-device; the network is used only for this one-time fetch.
private struct LiteRTLMModelSheet: View {
    let modelStore: LiteRTLMModelStore
    @State private var isModelInstalled = false
    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VovoScreen(
                title: "LiteRT-LM Model",
                subtitle: "On-device Gemma 3n E2B int4 (~3.66 GB). Generation is 100% local; the network is used only for this one-time download.",
                scrolls: false
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: isModelInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(isModelInstalled ? VovoTheme.mint : VovoTheme.amber)
                        Text(isModelInstalled ? "Model installed" : "Model not downloaded")
                            .foregroundStyle(VovoTheme.cream)
                    }

                    if isDownloading {
                        ProgressView(value: progress) {
                            Text("Downloading… \(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(VovoTheme.cream.opacity(0.8))
                        }
                        .tint(VovoTheme.amber)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(VovoTheme.softPink)
                    }

                    Button {
                        Task { await download() }
                    } label: {
                        Text(isModelInstalled ? "Re-download model" : "Download model")
                    }
                    .buttonStyle(VovoPrimaryButtonStyle(enabled: !isDownloading))
                    .disabled(isDownloading)

                    Button(role: .destructive) {
                        Task { await remove() }
                    } label: {
                        Text("Remove model")
                    }
                    .buttonStyle(VovoSecondaryButtonStyle())
                    .disabled(!isModelInstalled || isDownloading)

                    Spacer()
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(VovoTheme.amber)
                }
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isModelInstalled = await modelStore.isModelPresent()
    }

    private func download() async {
        errorText = nil
        isDownloading = true
        progress = 0
        defer { isDownloading = false }
        do {
            try await modelStore.download { fraction in
                progress = fraction
            }
            await refresh()
        } catch {
            errorText = "Download failed: \(error.localizedDescription)"
        }
    }

    private func remove() async {
        do {
            try await modelStore.removeModel()
            await refresh()
        } catch {
            errorText = "Remove failed: \(error.localizedDescription)"
        }
    }
}
