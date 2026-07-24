import SwiftUI

struct OnboardingView: View {
    @Environment(LanguageStore.self) private var languageStore
    @AppStorage(AppSettings.ageGateAcceptedKey) private var ageGateAccepted = false
    @State private var confirmedAge = false

    private var lang: AppLanguage { languageStore.language }

    var body: some View {
        ZStack {
            VovoTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                LanguageBar()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Spacer(minLength: 16)

                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(VovoTheme.amber)
                            .symbolRenderingMode(.hierarchical)

                        Text(L10n.t(.onboardingTitle, lang))
                            .font(.largeTitle.bold())
                            .foregroundStyle(VovoTheme.cream)

                        Text(L10n.t(.onboardingSubtitle, lang))
                            .font(.title2.weight(.medium))
                            .foregroundStyle(VovoTheme.cream.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 14) {
                            bullet(L10n.t(.onboardingBullet1, lang))
                            bullet(L10n.t(.onboardingBullet2, lang))
                            bullet(L10n.t(.onboardingBullet3, lang))
                            bullet(L10n.t(.onboardingBullet4, lang))
                        }
                        .padding(.top, 8)

                        Toggle(isOn: $confirmedAge) {
                            Text(L10n.t(.onboardingAgeToggle, lang))
                                .font(.subheadline)
                                .foregroundStyle(VovoTheme.cream.opacity(0.9))
                        }
                        .tint(VovoTheme.amber)
                        .padding(.top, 12)

                        Button(L10n.t(.onboardingStart, lang)) {
                            ageGateAccepted = true
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: confirmedAge))
                        .disabled(!confirmedAge)
                        .padding(.top, 8)

                        Text(L10n.t(.onboardingDevices, lang))
                            .font(.caption)
                            .foregroundStyle(VovoTheme.cream.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                    }
                    .padding(28)
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(VovoTheme.mint)
            Text(text)
                .font(.body)
                .foregroundStyle(VovoTheme.cream.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    OnboardingView()
        .environment(LanguageStore())
}
