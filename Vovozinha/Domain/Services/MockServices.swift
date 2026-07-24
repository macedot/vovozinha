import Foundation
import UIKit

// MARK: - Character analyzer (description / photo → profile; no cloud)

/// Local placeholder until a vision model is available. Respects `input.language`.
struct MockCharacterAnalyzer: CharacterAnalyzing {
    func analyze(input: StoryDraftInput) async throws -> CharacterProfile {
        try await Task.sleep(for: .milliseconds(400))

        guard input.hasActorIdentity else {
            throw CharacterAnalysisError.missingInput
        }

        let lang = input.language
        let name = input.resolvedActorName()
        let desc = input.trimmedActorDescription

        if !desc.isEmpty {
            return CharacterProfile.fromManual(name: name, description: desc, language: lang)
        }

        if input.hasPhoto {
            let cute = CharacterProfile.defaultCuteAppearance(name: name, language: lang)
            return CharacterProfile(
                name: name.isEmpty ? CharacterProfile.defaultHeroName(lang) : name,
                appearance: cute.appearance,
                personality: CharacterProfile.defaultPersonality(lang),
                lockedDescription: cute.locked
            )
        }

        return CharacterProfile.fromManual(
            name: name,
            description: CharacterProfile.defaultNameOnlyDescription(name: name, language: lang),
            language: lang
        )
    }
}


// MARK: - Procedural kids illustrator

struct ProceduralKidsIllustrator: Illustrating {
    func illustrate(
        page: StoryPlanPage,
        plan: StoryPlan,
        referencePhoto: Data?
    ) async throws -> UIImage {
        try await Task.sleep(for: .milliseconds(250))

        let size = CGSize(width: 768, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        let colors = palette(for: plan.setting, style: plan.artStyle, page: page.index)

        return renderer.image { ctx in
            let cg = ctx.cgContext

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [colors.top.cgColor, colors.bottom.cgColor] as CFArray,
                locations: [0, 1]
            )!
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            drawOrb(cg, center: CGPoint(x: size.width * 0.2, y: size.height * 0.25), radius: 90, color: colors.accent.withAlphaComponent(0.35))
            drawOrb(cg, center: CGPoint(x: size.width * 0.8, y: size.height * 0.3), radius: 70, color: colors.accent2.withAlphaComponent(0.3))
            drawOrb(cg, center: CGPoint(x: size.width * 0.7, y: size.height * 0.75), radius: 110, color: colors.accent.withAlphaComponent(0.25))

            colors.ground.setFill()
            UIBezierPath(
                ovalIn: CGRect(x: -40, y: size.height * 0.62, width: size.width + 80, height: size.height * 0.55)
            ).fill()

            let seed = CGFloat(plan.character.name.hashValue % 100) / 100.0
            drawCharacter(
                cg,
                center: CGPoint(
                    x: size.width * (0.35 + 0.1 * seed),
                    y: size.height * 0.55
                ),
                body: colors.character,
                cheek: colors.accent2,
                pageIndex: page.index
            )

            if let referencePhoto, let ref = UIImage(data: referencePhoto) {
                let badgeSize: CGFloat = 120
                let badgeRect = CGRect(
                    x: size.width - badgeSize - 36,
                    y: 36,
                    width: badgeSize,
                    height: badgeSize
                )
                UIColor.white.withAlphaComponent(0.9).setFill()
                UIBezierPath(roundedRect: badgeRect.insetBy(dx: -6, dy: -6), cornerRadius: 24).fill()
                ref.draw(in: badgeRect)
            }

            UIColor.black.withAlphaComponent(0.28).setFill()
            UIRectFill(CGRect(x: 0, y: size.height - 96, width: size.width, height: 96))

            let caption = "\(plan.title) · \(page.index + 1)/\(plan.pageCount)" as NSString
            caption.draw(
                in: CGRect(x: 28, y: size.height - 70, width: size.width - 56, height: 40),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
            )
        }
    }

    private func drawOrb(_ cg: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
        color.setFill()
        cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func drawCharacter(_ cg: CGContext, center: CGPoint, body: UIColor, cheek: UIColor, pageIndex: Int) {
        let bob = CGFloat(pageIndex % 3) * 8
        let c = CGPoint(x: center.x, y: center.y - bob)

        body.setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 70, y: c.y - 40, width: 140, height: 160))

        UIColor.white.withAlphaComponent(0.95).setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 55, y: c.y - 120, width: 110, height: 110))

        UIColor(red: 0.15, green: 0.12, blue: 0.25, alpha: 1).setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 28, y: c.y - 85, width: 16, height: 22))
        cg.fillEllipse(in: CGRect(x: c.x + 12, y: c.y - 85, width: 16, height: 22))

        cheek.withAlphaComponent(0.55).setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 42, y: c.y - 58, width: 18, height: 12))
        cg.fillEllipse(in: CGRect(x: c.x + 24, y: c.y - 58, width: 18, height: 12))

        let smile = UIBezierPath(
            arcCenter: CGPoint(x: c.x, y: c.y - 55),
            radius: 18,
            startAngle: 0.15 * .pi,
            endAngle: 0.85 * .pi,
            clockwise: true
        )
        UIColor(red: 0.15, green: 0.12, blue: 0.25, alpha: 1).setStroke()
        smile.lineWidth = 4
        smile.stroke()
    }

    private struct Palette {
        var top: UIColor
        var bottom: UIColor
        var ground: UIColor
        var accent: UIColor
        var accent2: UIColor
        var character: UIColor
    }

    private func palette(for setting: String, style: ArtStyle, page: Int) -> Palette {
        let s = setting.lowercased()
        if s.contains("mar") || s.contains("oceano") {
            return Palette(
                top: UIColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 1),
                bottom: UIColor(red: 0.10, green: 0.25, blue: 0.55, alpha: 1),
                ground: UIColor(red: 0.15, green: 0.45, blue: 0.55, alpha: 0.9),
                accent: UIColor(red: 0.40, green: 0.90, blue: 0.85, alpha: 1),
                accent2: UIColor(red: 1.0, green: 0.70, blue: 0.75, alpha: 1),
                character: UIColor(red: 0.95, green: 0.75, blue: 0.35, alpha: 1)
            )
        }
        if s.contains("espaço") || s.contains("galáxia") || s.contains("estrela") {
            return Palette(
                top: UIColor(red: 0.12, green: 0.08, blue: 0.30, alpha: 1),
                bottom: UIColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1),
                ground: UIColor(red: 0.25, green: 0.15, blue: 0.40, alpha: 0.85),
                accent: UIColor(red: 0.95, green: 0.80, blue: 0.40, alpha: 1),
                accent2: UIColor(red: 0.70, green: 0.55, blue: 1.0, alpha: 1),
                character: UIColor(red: 0.85, green: 0.55, blue: 0.95, alpha: 1)
            )
        }
        if s.contains("castelo") || s.contains("reino") {
            return Palette(
                top: UIColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1),
                bottom: UIColor(red: 0.30, green: 0.20, blue: 0.45, alpha: 1),
                ground: UIColor(red: 0.45, green: 0.55, blue: 0.40, alpha: 0.9),
                accent: UIColor(red: 0.98, green: 0.82, blue: 0.40, alpha: 1),
                accent2: UIColor(red: 0.95, green: 0.60, blue: 0.70, alpha: 1),
                character: UIColor(red: 0.40, green: 0.70, blue: 0.95, alpha: 1)
            )
        }
        let warm = style == .pastel
        return Palette(
            top: warm
                ? UIColor(red: 0.70, green: 0.78, blue: 0.95, alpha: 1)
                : UIColor(red: 0.35, green: 0.55, blue: 0.40, alpha: 1),
            bottom: warm
                ? UIColor(red: 0.95, green: 0.80, blue: 0.70, alpha: 1)
                : UIColor(red: 0.12, green: 0.22, blue: 0.18, alpha: 1),
            ground: UIColor(red: 0.30, green: 0.45, blue: 0.28, alpha: 0.9),
            accent: UIColor(red: 0.98, green: 0.75, blue: 0.35, alpha: 1),
            accent2: UIColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1),
            character: UIColor(red: 0.95, green: 0.60, blue: 0.35, alpha: 1)
        )
    }
}
