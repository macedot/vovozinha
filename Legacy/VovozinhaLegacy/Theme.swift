import SwiftUI

enum VovoTheme {
    static let indigo = Color(red: 0.12, green: 0.10, blue: 0.28)
    static let deepNight = Color(red: 0.07, green: 0.06, blue: 0.16)
    static let amber = Color(red: 0.96, green: 0.72, blue: 0.35)
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.88)
    static let softPink = Color(red: 0.92, green: 0.62, blue: 0.70)
    static let mint = Color(red: 0.55, green: 0.82, blue: 0.72)

    static let backgroundGradient = LinearGradient(
        colors: [deepNight, indigo, Color(red: 0.18, green: 0.12, blue: 0.32)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardFill = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.12)
}

struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? VovoTheme.amber : VovoTheme.cardFill)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? VovoTheme.amber : VovoTheme.cardStroke, lineWidth: 1)
                )
                .foregroundStyle(isSelected ? VovoTheme.deepNight : VovoTheme.cream)
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(enabled ? VovoTheme.amber : Color.gray.opacity(0.35))
            )
            .foregroundStyle(enabled ? VovoTheme.deepNight : Color.white.opacity(0.5))
            .opacity(configuration.isPressed && enabled ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(VovoTheme.cream.opacity(0.35), lineWidth: 1.5)
            )
            .foregroundStyle(VovoTheme.cream)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
