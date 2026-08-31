import SwiftUI

/// Shared visual language for Vovozinha and all feature debug apps.
public enum VovoTheme {
    public static let indigo = Color(red: 0.12, green: 0.10, blue: 0.28)
    public static let deepNight = Color(red: 0.07, green: 0.06, blue: 0.16)
    public static let amber = Color(red: 0.96, green: 0.72, blue: 0.35)
    public static let cream = Color(red: 0.98, green: 0.95, blue: 0.88)
    public static let softPink = Color(red: 0.92, green: 0.62, blue: 0.70)
    public static let mint = Color(red: 0.55, green: 0.82, blue: 0.72)

    public static let backgroundGradient = LinearGradient(
        colors: [deepNight, indigo, Color(red: 0.18, green: 0.12, blue: 0.32)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let cardFill = Color.white.opacity(0.08)
    public static let cardStroke = Color.white.opacity(0.12)
}

public struct VovoPrimaryButtonStyle: ButtonStyle {
    public var enabled: Bool = true

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public func makeBody(configuration: Configuration) -> some View {
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

public struct VovoSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
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

/// Shared screen chrome: night gradient + cream content + optional title.
///
/// When `scrolls` is true (default), the title and content live in a single
/// `ScrollView` so long results (e.g. a 10-scene story) scroll naturally.
public struct VovoScreen<Content: View>: View {
    public let title: String
    public let subtitle: String?
    /// Use a single outer scroll for the whole screen body.
    public var scrolls: Bool
    @ViewBuilder public var content: () -> Content

    public init(
        title: String,
        subtitle: String? = nil,
        scrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
        self.content = content
    }

    public var body: some View {
        ZStack {
            VovoTheme.backgroundGradient.ignoresSafeArea()
            if scrolls {
                ScrollView {
                    mainColumn
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    mainColumn
                        .padding(24)
                    Spacer(minLength: 0)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(VovoTheme.cream)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(VovoTheme.cream.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
    }
}

public struct VovoCardFieldStyle: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(VovoTheme.cardFill)
            )
            .foregroundStyle(VovoTheme.cream)
            .tint(VovoTheme.amber)
    }
}

public extension View {
    func vovoCardField() -> some View {
        modifier(VovoCardFieldStyle())
    }
}
