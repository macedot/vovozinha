import SwiftUI

/// Top language toggle: PT / EN / ES. Selection pins the language.
public struct LanguageBar: View {
    @Environment(LanguageStore.self) private var languageStore

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VovoTheme.amber.opacity(0.9))

            Text(VovoL10n.t(.language, languageStore.language))
                .font(.caption.weight(.semibold))
                .foregroundStyle(VovoTheme.cream.opacity(0.7))

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        languageStore.select(lang)
                    } label: {
                        Text(lang.shortLabel)
                            .font(.caption.weight(.bold))
                            .frame(minWidth: 36)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected(lang) ? VovoTheme.amber : Color.clear)
                            )
                            .foregroundStyle(isSelected(lang) ? VovoTheme.deepNight : VovoTheme.cream.opacity(0.85))
                            // Keep label text for XCUITest fallback (PT / EN / ES).
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    // Combined a11y on the control (identifiers without hyphens for XCUITest).
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lang.displayName)
                    .accessibilityIdentifier(lang.accessibilityIdentifier)
                    .accessibilityAddTraits(isSelected(lang) ? [.isButton, .isSelected] : [.isButton])
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(VovoTheme.cardFill)
                    .overlay(Capsule().stroke(VovoTheme.cardStroke))
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("languageBar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(VovoTheme.deepNight.opacity(0.92))
    }

    private func isSelected(_ lang: AppLanguage) -> Bool {
        // When following system, highlight the resolved language.
        languageStore.language == lang
    }
}
