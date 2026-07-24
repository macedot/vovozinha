import SwiftUI

struct SettingsView: View {
    @Environment(LanguageStore.self) private var languageStore
    @AppStorage(AppSettings.ageGateAcceptedKey) private var ageGateAccepted = false
    @AppStorage(AppSettings.illustrationPackInstalledKey) private var packInstalled = false
    @AppStorage(AppSettings.preferredVoiceIdentifierKey) private var preferredVoiceID = ""
    @State private var storageLabel = "—"
    @State private var profile = DeviceProfile.current
    @State private var installedVoices: [VoiceCatalog.Entry] = []
    @State private var imagePackDownloader = ImagePackDownloader()

    private var lang: AppLanguage { languageStore.language }

    var body: some View {
        NavigationStack {
            ZStack {
                VovoTheme.backgroundGradient.ignoresSafeArea()

                List {
                    Section(L10n.t(.settingsLanguage, lang)) {
                        Picker(L10n.t(.settingsLanguage, lang), selection: Binding(
                            get: { languageStore.preferenceRaw },
                            set: { languageStore.preferenceRaw = $0 }
                        )) {
                            Text(L10n.t(.settingsLanguageSystem, lang) + " (\(AppLanguage.fromSystem().shortLabel))")
                                .tag(LanguagePreference.system.rawValue)
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language.rawValue)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()

                        Text(L10n.t(.settingsLanguageHint, lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Picker(L10n.t(.settingsVoice, lang), selection: $preferredVoiceID) {
                            Text(L10n.t(.settingsVoiceAuto, lang)).tag("")
                            ForEach(installedVoices) { voice in
                                Text("\(voice.name) · \(voice.qualityLabel)")
                                    .tag(voice.identifier)
                            }
                        }

                        Text(L10n.t(.settingsVoiceHint, lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !VoiceCatalog.hasEnhancedOrBetter(for: lang) {
                            Text(L10n.t(.settingsVoicePremiumTip, lang))
                                .font(.caption)
                                .foregroundStyle(VovoTheme.amber.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(L10n.t(.settingsVoicePremiumTip, lang))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text(L10n.t(.settingsVoice, lang))
                    }

                    Section {
                        LabeledContent(L10n.t(.settingsOSVersion, lang), value: profile.osDisplay)
                        Text(L10n.t(.settingsResourcesHint, lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(AppFeature.userVisible) { feature in
                            FeatureStatusRow(
                                feature: feature,
                                availability: profile.availability(for: feature, lang: lang),
                                lang: lang
                            )
                        }
                    } header: {
                        Text(L10n.t(.settingsResources, lang))
                    }

                    Section(L10n.t(.settingsAbout, lang)) {
                        LabeledContent(L10n.t(.settingsApp, lang), value: "Vovozinha")
                        LabeledContent(L10n.t(.settingsVersion, lang), value: "0.1.0")
                        LabeledContent(L10n.t(.settingsFocus, lang), value: L10n.t(.settingsFocusValue, lang))
                        LabeledContent(L10n.t(.settingsDevices, lang), value: L10n.t(.settingsDevicesValue, lang))
                    }

                    Section(L10n.t(.settingsOnDevice, lang)) {
                        Text(profile.statusSummary(lang: lang))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(L10n.t(.settingsPackHint, lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        imagePackSection
                    } header: {
                        Text(L10n.t(.settingsImagePack, lang))
                    }

                    Section(L10n.t(.settingsStorage, lang)) {
                        LabeledContent(L10n.t(.settingsStoriesSize, lang), value: storageLabel)
                        Button(L10n.t(.settingsRefreshSize, lang)) {
                            refreshStorage()
                        }
                    }

                    Section(L10n.t(.settingsPrivacy, lang)) {
                        Text(L10n.t(.settingsPrivacyBody, lang))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Section(L10n.t(.settingsParental, lang)) {
                        Button(L10n.t(.settingsResetAge, lang), role: .destructive) {
                            ageGateAccepted = false
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L10n.t(.settingsTitle, lang))
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                refreshStorage()
                profile = .current
                refreshVoices()
                imagePackDownloader.refreshReadyState()
                packInstalled = ImagePackStore.isNeuralPackReady
            }
            .onChange(of: packInstalled) { _, _ in
                profile = .current
            }
            .onChange(of: languageStore.language) { _, _ in
                refreshVoices()
            }
            .onChange(of: imagePackDownloader.phase) { _, phase in
                if phase == .ready {
                    packInstalled = true
                    profile = .current
                    refreshStorage()
                }
                if phase == .idle {
                    packInstalled = ImagePackStore.isNeuralPackReady
                    profile = .current
                }
            }
        }
    }

    @ViewBuilder
    private var imagePackSection: some View {
        Text(ImagePackStore.statusSummary(lang: lang))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Text(L10n.t(.settingsImagePackSizeHint, lang))
            .font(.caption)
            .foregroundStyle(.secondary)

        switch imagePackDownloader.phase {
        case .listing, .downloading, .extracting, .verifying:
            ProgressView(value: max(imagePackDownloader.progress, 0.02)) {
                Text(L10n.t(.settingsImagePackDownloading, lang))
            } currentValueLabel: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(imagePackDownloader.progressPercent)% · \(imagePackDownloader.byteProgressLabel)")
                        .font(.caption.monospacedDigit())
                    if !imagePackDownloader.currentFileName.isEmpty {
                        Text(imagePackDownloader.currentFileName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Button(L10n.t(.settingsImagePackCancel, lang), role: .cancel) {
                imagePackDownloader.cancel()
            }

        case .ready:
            Label(L10n.t(.settingsImagePackReady, lang), systemImage: "checkmark.seal.fill")
                .foregroundStyle(VovoTheme.mint)
            Button(L10n.t(.settingsImagePackDelete, lang), role: .destructive) {
                try? imagePackDownloader.deleteInstalledPack()
                packInstalled = false
                profile = .current
                refreshStorage()
            }

        case .failed(let message):
            Text("\(L10n.t(.settingsImagePackFailed, lang)): \(message)")
                .font(.caption)
                .foregroundStyle(VovoTheme.softPink)
            Button(L10n.t(.settingsImagePackDownload, lang)) {
                imagePackDownloader.startDownload()
            }
            .buttonStyle(.borderedProminent)
            .tint(VovoTheme.amber)

        case .idle:
            Button(L10n.t(.settingsImagePackDownload, lang)) {
                imagePackDownloader.startDownload()
            }
            .buttonStyle(.borderedProminent)
            .tint(VovoTheme.amber)
        }
    }

    private func refreshStorage() {
        let bytes = FileStorage.shared.approximateStorageBytes()
        storageLabel = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func refreshVoices() {
        installedVoices = VoiceCatalog.voices(for: lang)
        // Drop stale selection if that voice was removed or is wrong language.
        if !preferredVoiceID.isEmpty,
           !installedVoices.contains(where: { $0.identifier == preferredVoiceID }) {
            preferredVoiceID = ""
        }
    }
}

private struct FeatureStatusRow: View {
    let feature: AppFeature
    let availability: FeatureAvailability
    let lang: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: availability.statusSymbolName)
                    .foregroundStyle(iconColor)
                Text(feature.displayName(lang))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VovoTheme.cream)
                Spacer()
                Text(availability.statusLabel(lang))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor)
            }
            Text(availability.userMessage(lang))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("iOS \(feature.minimumOS.displayString)+")
                .font(.caption2)
                .foregroundStyle(VovoTheme.amber.opacity(0.8))
        }
        .padding(.vertical, 4)
        .listRowBackground(VovoTheme.cardFill)
    }

    private var iconColor: Color {
        switch availability {
        case .available: return VovoTheme.mint
        case .disabledInBuild: return VovoTheme.cream.opacity(0.55)
        case .unavailableOS, .unavailableHardware, .unavailableConfig: return VovoTheme.amber
        }
    }
}

#Preview {
    SettingsView()
        .environment(LanguageStore())
}
