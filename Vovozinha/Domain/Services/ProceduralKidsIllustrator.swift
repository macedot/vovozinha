import Foundation
import UIKit

/// 100% offline page art: scene-aware procedural kids-book illustration.
/// Uses structured `SceneArtBrief`, previous-page underlay for temporal continuity,
/// and optional actor photo. Neural pack can replace this via `CoreMLDiffusionIllustrator`.
struct ProceduralKidsIllustrator: Illustrating {
    private let canvasSize = CGSize(width: 1024, height: 1024)

    func illustrate(_ request: IllustrationRequest) async throws -> UIImage {
        await Task.yield()

        let page = request.page
        let plan = request.plan
        let seed = request.pageSeed != 0
            ? request.pageSeed
            : Self.stableSeed(
                name: plan.character.name,
                setting: plan.setting,
                index: page.index,
                tag: page.sceneTag
            )
        let brief = request.brief
        let palette = Self.palette(
            setting: plan.setting,
            style: plan.artStyle,
            sceneTag: page.sceneTag,
            page: page.index,
            seed: seed,
            lighting: brief.lighting
        )
        // Props from brief + page text + setting (better scene match than tag alone).
        let propText = [
            page.text,
            plan.setting,
            brief.actionFocus,
            brief.propHints.joined(separator: " "),
            page.imagePrompt
        ].joined(separator: " ")
        let props = Self.detectProps(text: propText)
        let size = canvasSize
        let continuity = CGFloat(min(max(request.continuityStrength, 0), 0.75))

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Very light previous-frame wash only — strong underlay made every page look the same.
            if let prev = request.previousPageImage, continuity > 0.05 {
                prev.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: min(continuity * 0.18, 0.12))
                palette.top.withAlphaComponent(0.55).setFill()
                UIRectFill(CGRect(origin: .zero, size: size))
            }

            Self.drawBackground(cg, size: size, palette: palette, tag: page.sceneTag, seed: seed)
            Self.drawSettingAtmosphere(cg, size: size, palette: palette, setting: plan.setting, seed: seed)
            Self.drawProps(cg, size: size, props: props, palette: palette, seed: seed, page: page.index)
            Self.drawSecondaryCharacterIfNeeded(
                cg,
                size: size,
                tag: page.sceneTag,
                action: brief.actionFocus,
                palette: palette,
                seed: seed
            )
            Self.drawHero(
                cg,
                size: size,
                palette: palette,
                pageIndex: page.index,
                seed: seed,
                style: plan.artStyle
            )
            if let referencePhoto = request.referencePhoto, let ref = UIImage(data: referencePhoto) {
                Self.drawPhotoBadge(cg, size: size, photo: ref)
            }
            Self.drawSoftVignette(cg, size: size)
            Self.drawCaptionBar(cg, size: size, title: plan.title, pageIndex: page.index, total: plan.pageCount)
        }
    }

    // MARK: - Seed & props

    private static func stableSeed(name: String, setting: String, index: Int, tag: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        let raw = "\(name)|\(setting)|\(index)|\(tag)"
        for b in raw.utf8 {
            h ^= UInt64(b)
            h = h &* 1099511628211
        }
        return h
    }

    private static func unit(_ seed: UInt64, _ salt: UInt64) -> CGFloat {
        let x = seed &* (salt | 1) &+ 0x9E3779B97F4A7C15
        return CGFloat(x % 10_000) / 10_000
    }

    enum Prop: Hashable {
        case tree, bird, nest, star, moon, boat, bed, flower, cloud, door, fish, castle, sun
    }

    private static func detectProps(text: String) -> Set<Prop> {
        let t = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        var props = Set<Prop>()
        let map: [(Prop, [String])] = [
            (.tree, ["tree", "arvore", "bosque", "forest", "floresta", "folha", "leaf"]),
            (.bird, ["bird", "passaro", "pajaro", "ave", "nest", "ninho", "nido"]),
            (.nest, ["nest", "ninho", "nido"]),
            (.star, ["star", "estrela", "estrella"]),
            (.moon, ["moon", "lua", "luna", "bedtime", "night", "noite", "noche"]),
            (.boat, ["boat", "barco", "sea", "mar", "ocean", "oceano"]),
            (.bed, ["bed", "cama", "sleep", "dorm", "pillow", "travesseiro"]),
            (.flower, ["flower", "flor", "garden", "jardim", "jardin"]),
            (.cloud, ["cloud", "nuvem", "nube", "sky", "ceu", "cielo"]),
            (.door, ["door", "porta", "puerta", "castle", "castelo", "castillo"]),
            (.fish, ["fish", "peixe", "pez", "underwater", "fundo do mar"]),
            (.castle, ["castle", "castelo", "castillo", "reino", "kingdom"]),
            (.sun, ["sun", "sol", "morning", "manha", "manana", "day"])
        ]
        for (prop, keys) in map where keys.contains(where: { t.contains($0) }) {
            props.insert(prop)
        }
        return props
    }

    // MARK: - Palette

    private struct Palette {
        var top: UIColor
        var bottom: UIColor
        var ground: UIColor
        var accent: UIColor
        var accent2: UIColor
        var character: UIColor
        var secondary: UIColor
    }

    private static func palette(
        setting: String,
        style: ArtStyle,
        sceneTag: String,
        page: Int,
        seed: UInt64,
        lighting: String = ""
    ) -> Palette {
        let s = setting.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let tag = sceneTag.lowercased()
        let light = lighting.lowercased()
        var base: Palette

        if containsAny(s, ["mar", "sea", "ocean", "oceano", "praia", "beach", "underwater"]) {
            base = Palette(
                top: UIColor(red: 0.45, green: 0.75, blue: 0.98, alpha: 1),
                bottom: UIColor(red: 0.12, green: 0.35, blue: 0.65, alpha: 1),
                ground: UIColor(red: 0.20, green: 0.55, blue: 0.65, alpha: 0.95),
                accent: UIColor(red: 0.40, green: 0.95, blue: 0.90, alpha: 1),
                accent2: UIColor(red: 1.0, green: 0.75, blue: 0.55, alpha: 1),
                character: UIColor(red: 0.98, green: 0.80, blue: 0.40, alpha: 1),
                secondary: UIColor(red: 0.95, green: 0.55, blue: 0.65, alpha: 1)
            )
        } else if containsAny(s, ["espaco", "space", "galaxy", "estrela", "star", "galaxia"]) {
            base = Palette(
                top: UIColor(red: 0.18, green: 0.12, blue: 0.38, alpha: 1),
                bottom: UIColor(red: 0.06, green: 0.05, blue: 0.14, alpha: 1),
                ground: UIColor(red: 0.28, green: 0.18, blue: 0.42, alpha: 0.9),
                accent: UIColor(red: 0.98, green: 0.85, blue: 0.45, alpha: 1),
                accent2: UIColor(red: 0.75, green: 0.60, blue: 1.0, alpha: 1),
                character: UIColor(red: 0.88, green: 0.60, blue: 0.98, alpha: 1),
                secondary: UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
            )
        } else if containsAny(s, ["castelo", "castle", "reino", "kingdom", "palace"]) {
            base = Palette(
                top: UIColor(red: 0.62, green: 0.55, blue: 0.92, alpha: 1),
                bottom: UIColor(red: 0.35, green: 0.28, blue: 0.55, alpha: 1),
                ground: UIColor(red: 0.48, green: 0.58, blue: 0.42, alpha: 0.95),
                accent: UIColor(red: 0.98, green: 0.84, blue: 0.42, alpha: 1),
                accent2: UIColor(red: 0.98, green: 0.65, blue: 0.75, alpha: 1),
                character: UIColor(red: 0.45, green: 0.75, blue: 0.98, alpha: 1),
                secondary: UIColor(red: 0.95, green: 0.70, blue: 0.45, alpha: 1)
            )
        } else if containsAny(s, ["quarto", "bedroom", "bed", "noite", "night", "cama"]) {
            base = Palette(
                top: UIColor(red: 0.22, green: 0.20, blue: 0.45, alpha: 1),
                bottom: UIColor(red: 0.12, green: 0.10, blue: 0.28, alpha: 1),
                ground: UIColor(red: 0.45, green: 0.35, blue: 0.55, alpha: 0.9),
                accent: UIColor(red: 0.98, green: 0.88, blue: 0.55, alpha: 1),
                accent2: UIColor(red: 0.85, green: 0.70, blue: 1.0, alpha: 1),
                character: UIColor(red: 0.98, green: 0.72, blue: 0.55, alpha: 1),
                secondary: UIColor(red: 0.70, green: 0.85, blue: 0.98, alpha: 1)
            )
        } else if containsAny(s, ["fazenda", "farm", "campo", "garden", "jardim"]) {
            base = Palette(
                top: UIColor(red: 0.55, green: 0.80, blue: 0.98, alpha: 1),
                bottom: UIColor(red: 0.75, green: 0.90, blue: 0.55, alpha: 1),
                ground: UIColor(red: 0.40, green: 0.65, blue: 0.30, alpha: 0.95),
                accent: UIColor(red: 0.98, green: 0.75, blue: 0.35, alpha: 1),
                accent2: UIColor(red: 0.95, green: 0.55, blue: 0.45, alpha: 1),
                character: UIColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1),
                secondary: UIColor(red: 0.98, green: 0.85, blue: 0.50, alpha: 1)
            )
        } else {
            // Forest / default
            let warm = style == .pastel || style == .watercolor
            base = Palette(
                top: warm
                    ? UIColor(red: 0.72, green: 0.82, blue: 0.98, alpha: 1)
                    : UIColor(red: 0.40, green: 0.62, blue: 0.45, alpha: 1),
                bottom: warm
                    ? UIColor(red: 0.98, green: 0.86, blue: 0.72, alpha: 1)
                    : UIColor(red: 0.18, green: 0.32, blue: 0.22, alpha: 1),
                ground: UIColor(red: 0.32, green: 0.52, blue: 0.30, alpha: 0.95),
                accent: UIColor(red: 0.98, green: 0.78, blue: 0.38, alpha: 1),
                accent2: UIColor(red: 0.95, green: 0.58, blue: 0.58, alpha: 1),
                character: UIColor(red: 0.95, green: 0.62, blue: 0.38, alpha: 1),
                secondary: UIColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1)
            )
        }

        // Lighting from structured brief (temporal arc of the story day).
        if light.contains("night") || light.contains("moon") || tag == "bedtime" {
            base.top = blend(base.top, UIColor(red: 0.16, green: 0.14, blue: 0.38, alpha: 1), 0.45)
            base.bottom = blend(base.bottom, UIColor(red: 0.08, green: 0.08, blue: 0.22, alpha: 1), 0.35)
        } else if light.contains("sunset") || light.contains("golden hour") || light.contains("evening") {
            base.top = blend(base.top, UIColor(red: 0.98, green: 0.70, blue: 0.45, alpha: 1), 0.35)
            base.bottom = blend(base.bottom, UIColor(red: 0.85, green: 0.45, blue: 0.55, alpha: 1), 0.25)
        } else if light.contains("morning") || light.contains("sunrise") {
            base.top = blend(base.top, UIColor(red: 0.98, green: 0.90, blue: 0.65, alpha: 1), 0.3)
        }
        if tag == "feel" {
            base.top = blend(base.top, UIColor(red: 0.55, green: 0.65, blue: 0.95, alpha: 1), 0.2)
        }
        if style == .pastel {
            base.character = blend(base.character, .white, 0.15)
            base.accent = blend(base.accent, .white, 0.12)
        }
        // Keep hero hue almost fixed (coherence); tiny wobble only.
        let wobble = unit(seed, UInt64(page + 3)) * 0.02
        base.character = shiftHue(base.character, by: wobble - 0.01)
        return base
    }

    private static func containsAny(_ hay: String, _ needles: [String]) -> Bool {
        needles.contains { hay.contains($0) }
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
    }

    private static func shiftHue(_ color: UIColor, by delta: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        var nh = h + delta
        if nh < 0 { nh += 1 }
        if nh > 1 { nh -= 1 }
        return UIColor(hue: nh, saturation: s, brightness: b, alpha: a)
    }

    // MARK: - Drawing

    private static func drawBackground(
        _ cg: CGContext,
        size: CGSize,
        palette: Palette,
        tag: String,
        seed: UInt64
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [palette.top.cgColor, palette.bottom.cgColor] as CFArray,
            locations: [0, 1]
        )!
        let endY: CGFloat = tag == "bedtime" ? size.height * 0.95 : size.height
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size.width * 0.15, y: endY),
            options: []
        )

        // Soft orbs
        drawOrb(cg, center: CGPoint(x: size.width * (0.15 + unit(seed, 1) * 0.1), y: size.height * 0.22), radius: 100, color: palette.accent.withAlphaComponent(0.28))
        drawOrb(cg, center: CGPoint(x: size.width * (0.78 + unit(seed, 2) * 0.08), y: size.height * 0.28), radius: 80, color: palette.accent2.withAlphaComponent(0.25))

        // Ground
        palette.ground.setFill()
        let groundH = tag == "explore" ? size.height * 0.48 : size.height * 0.42
        UIBezierPath(
            ovalIn: CGRect(x: -80, y: size.height - groundH, width: size.width + 160, height: groundH * 1.2)
        ).fill()
    }

    private static func drawSettingAtmosphere(
        _ cg: CGContext,
        size: CGSize,
        palette: Palette,
        setting: String,
        seed: UInt64
    ) {
        let s = setting.lowercased()
        // Decorative far trees / hills
        for i in 0..<4 {
            let x = size.width * (0.1 + CGFloat(i) * 0.22 + unit(seed, UInt64(10 + i)) * 0.05)
            let h = size.height * (0.12 + unit(seed, UInt64(20 + i)) * 0.08)
            palette.ground.withAlphaComponent(0.55).setFill()
            cg.fillEllipse(in: CGRect(x: x - 40, y: size.height * 0.52 - h, width: 80, height: h + 40))
        }
        if containsAny(s, ["nuvem", "cloud", "ceu", "sky"]) || unit(seed, 99) > 0.4 {
            UIColor.white.withAlphaComponent(0.55).setFill()
            for i in 0..<3 {
                let x = size.width * (0.15 + CGFloat(i) * 0.28)
                let y = size.height * (0.12 + unit(seed, UInt64(30 + i)) * 0.08)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: 90, height: 45))
                cg.fillEllipse(in: CGRect(x: x + 30, y: y - 10, width: 70, height: 40))
            }
        }
    }

    private static func drawProps(
        _ cg: CGContext,
        size: CGSize,
        props: Set<Prop>,
        palette: Palette,
        seed: UInt64,
        page: Int
    ) {
        if props.contains(.sun) || (!props.contains(.moon) && page < 3) {
            palette.accent.setFill()
            let r: CGFloat = 55
            cg.fillEllipse(in: CGRect(x: size.width * 0.72, y: size.height * 0.1, width: r * 2, height: r * 2))
        }
        if props.contains(.moon) || props.contains(.star) {
            UIColor(red: 0.98, green: 0.95, blue: 0.75, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: size.width * 0.7, y: size.height * 0.08, width: 90, height: 90))
            palette.top.withAlphaComponent(0.9).setFill()
            cg.fillEllipse(in: CGRect(x: size.width * 0.74, y: size.height * 0.08, width: 70, height: 70))
        }
        if props.contains(.star) {
            UIColor.white.withAlphaComponent(0.9).setFill()
            for i in 0..<8 {
                let x = size.width * unit(seed, UInt64(40 + i))
                let y = size.height * (0.05 + unit(seed, UInt64(50 + i)) * 0.25)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: 8, height: 8))
            }
        }
        if props.contains(.tree) {
            drawTree(cg, at: CGPoint(x: size.width * 0.18, y: size.height * 0.58), palette: palette, scale: 1.1)
            drawTree(cg, at: CGPoint(x: size.width * 0.82, y: size.height * 0.6), palette: palette, scale: 0.85)
        }
        if props.contains(.flower) {
            for i in 0..<5 {
                let x = size.width * (0.2 + CGFloat(i) * 0.12)
                drawFlower(cg, at: CGPoint(x: x, y: size.height * 0.72), color: palette.accent2)
            }
        }
        if props.contains(.bird) || props.contains(.nest) {
            palette.secondary.setFill()
            let bx = size.width * 0.62
            let by = size.height * 0.42
            cg.fillEllipse(in: CGRect(x: bx, y: by, width: 50, height: 36))
            cg.fillEllipse(in: CGRect(x: bx + 28, y: by - 8, width: 28, height: 24))
            if props.contains(.nest) {
                UIColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: bx - 10, y: by + 28, width: 70, height: 28))
            }
        }
        if props.contains(.boat) {
            palette.accent2.setFill()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: size.width * 0.55, y: size.height * 0.68))
            path.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.68))
            path.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.76))
            path.addLine(to: CGPoint(x: size.width * 0.6, y: size.height * 0.76))
            path.close()
            path.fill()
            UIColor.white.withAlphaComponent(0.85).setFill()
            cg.fillEllipse(in: CGRect(x: size.width * 0.64, y: size.height * 0.58, width: 36, height: 48))
        }
        if props.contains(.bed) {
            UIColor(red: 0.75, green: 0.55, blue: 0.85, alpha: 1).setFill()
            UIRectFill(CGRect(x: size.width * 0.55, y: size.height * 0.62, width: 220, height: 90))
            UIColor.white.withAlphaComponent(0.9).setFill()
            cg.fillEllipse(in: CGRect(x: size.width * 0.58, y: size.height * 0.58, width: 70, height: 50))
        }
        if props.contains(.castle) || props.contains(.door) {
            UIColor(red: 0.72, green: 0.68, blue: 0.88, alpha: 1).setFill()
            UIRectFill(CGRect(x: size.width * 0.62, y: size.height * 0.38, width: 160, height: 200))
            UIRectFill(CGRect(x: size.width * 0.58, y: size.height * 0.32, width: 40, height: 80))
            UIRectFill(CGRect(x: size.width * 0.86, y: size.height * 0.32, width: 40, height: 80))
            UIColor(red: 0.35, green: 0.25, blue: 0.45, alpha: 1).setFill()
            UIRectFill(CGRect(x: size.width * 0.72, y: size.height * 0.52, width: 50, height: 86))
        }
        if props.contains(.fish) {
            palette.accent.setFill()
            cg.fillEllipse(in: CGRect(x: size.width * 0.2, y: size.height * 0.45, width: 60, height: 32))
            cg.fillEllipse(in: CGRect(x: size.width * 0.35, y: size.height * 0.55, width: 48, height: 26))
        }
        if props.contains(.cloud) {
            UIColor.white.withAlphaComponent(0.7).setFill()
            cg.fillEllipse(in: CGRect(x: size.width * 0.1, y: size.height * 0.15, width: 120, height: 55))
        }
    }

    private static func drawTree(_ cg: CGContext, at point: CGPoint, palette: Palette, scale: CGFloat) {
        UIColor(red: 0.45, green: 0.30, blue: 0.18, alpha: 1).setFill()
        UIRectFill(CGRect(x: point.x - 10 * scale, y: point.y, width: 20 * scale, height: 70 * scale))
        palette.ground.withAlphaComponent(0.95).setFill()
        cg.fillEllipse(in: CGRect(x: point.x - 45 * scale, y: point.y - 70 * scale, width: 90 * scale, height: 90 * scale))
        cg.fillEllipse(in: CGRect(x: point.x - 35 * scale, y: point.y - 100 * scale, width: 70 * scale, height: 70 * scale))
    }

    private static func drawFlower(_ cg: CGContext, at point: CGPoint, color: UIColor) {
        UIColor(red: 0.35, green: 0.65, blue: 0.35, alpha: 1).setStroke()
        let stem = UIBezierPath()
        stem.move(to: point)
        stem.addLine(to: CGPoint(x: point.x, y: point.y - 28))
        stem.lineWidth = 3
        stem.stroke()
        color.setFill()
        for i in 0..<5 {
            let a = CGFloat(i) * (.pi * 2 / 5)
            let c = CGPoint(x: point.x + cos(a) * 10, y: point.y - 28 + sin(a) * 10)
            cg.fillEllipse(in: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14))
        }
        UIColor(red: 0.98, green: 0.9, blue: 0.4, alpha: 1).setFill()
        cg.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 33, width: 10, height: 10))
    }

    private static func drawSecondaryCharacterIfNeeded(
        _ cg: CGContext,
        size: CGSize,
        tag: String,
        action: String,
        palette: Palette,
        seed: UInt64
    ) {
        let a = action.lowercased()
        let needsFriend = tag == "help" || tag == "try" || tag == "turn"
            || a.contains("friend") || a.contains("help") || a.contains("hug")
        guard needsFriend else { return }
        let center = CGPoint(x: size.width * 0.68, y: size.height * 0.58)
        palette.secondary.setFill()
        cg.fillEllipse(in: CGRect(x: center.x - 45, y: center.y - 20, width: 90, height: 100))
        UIColor.white.withAlphaComponent(0.95).setFill()
        cg.fillEllipse(in: CGRect(x: center.x - 35, y: center.y - 70, width: 70, height: 70))
        UIColor(red: 0.15, green: 0.12, blue: 0.25, alpha: 1).setFill()
        cg.fillEllipse(in: CGRect(x: center.x - 16, y: center.y - 48, width: 12, height: 16))
        cg.fillEllipse(in: CGRect(x: center.x + 6, y: center.y - 48, width: 12, height: 16))
        _ = seed
    }

    private static func drawHero(
        _ cg: CGContext,
        size: CGSize,
        palette: Palette,
        pageIndex: Int,
        seed: UInt64,
        style: ArtStyle
    ) {
        // Soft anime-ish silhouette (fallback only — true anime needs the neural pack).
        // Distinct pose offset per page so pages don't look stamped.
        let bob = CGFloat((pageIndex * 17) % 5) * 18 - 36
        let side = CGFloat((pageIndex % 4) - 1) * 28
        let drift = (unit(seed, 7) - 0.5) * 40
        let c = CGPoint(x: size.width * 0.38 + drift + side, y: size.height * 0.56 + bob)
        let bodyScale: CGFloat = style == .cartoon ? 1.08 : 1.02

        // Cel-like body block
        palette.character.setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 75 * bodyScale, y: c.y - 40, width: 150 * bodyScale, height: 170 * bodyScale))

        // Larger head + eyes (anime-leaning proportions)
        UIColor.white.withAlphaComponent(0.98).setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 62, y: c.y - 132, width: 124, height: 124))

        // Big dark eyes with simple highlight
        UIColor(red: 0.12, green: 0.10, blue: 0.22, alpha: 1).setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 32, y: c.y - 98, width: 26, height: 34))
        cg.fillEllipse(in: CGRect(x: c.x + 10, y: c.y - 98, width: 26, height: 34))
        UIColor.white.withAlphaComponent(0.9).setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 26, y: c.y - 92, width: 10, height: 12))
        cg.fillEllipse(in: CGRect(x: c.x + 16, y: c.y - 92, width: 10, height: 12))

        palette.accent2.withAlphaComponent(0.5).setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 44, y: c.y - 64, width: 18, height: 12))
        cg.fillEllipse(in: CGRect(x: c.x + 26, y: c.y - 64, width: 18, height: 12))

        let smile = UIBezierPath(
            arcCenter: CGPoint(x: c.x, y: c.y - 56),
            radius: 16,
            startAngle: 0.18 * .pi,
            endAngle: 0.82 * .pi,
            clockwise: true
        )
        UIColor(red: 0.15, green: 0.12, blue: 0.25, alpha: 1).setStroke()
        smile.lineWidth = 3.5
        smile.stroke()
    }

    private static func drawPhotoBadge(_ cg: CGContext, size: CGSize, photo: UIImage) {
        let badge: CGFloat = 140
        let rect = CGRect(x: size.width - badge - 48, y: 48, width: badge, height: badge)
        UIColor.white.withAlphaComponent(0.92).setFill()
        UIBezierPath(roundedRect: rect.insetBy(dx: -8, dy: -8), cornerRadius: 28).fill()
        // Clip circle
        cg.saveGState()
        UIBezierPath(ovalIn: rect).addClip()
        photo.draw(in: rect)
        cg.restoreGState()
        UIColor.white.setStroke()
        let ring = UIBezierPath(ovalIn: rect)
        ring.lineWidth = 6
        ring.stroke()
    }

    private static func drawSoftVignette(_ cg: CGContext, size: CGSize) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.18).cgColor
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.55, 1]) else { return }
        cg.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: 0,
            endCenter: CGPoint(x: size.width / 2, y: size.height / 2),
            endRadius: size.width * 0.72,
            options: []
        )
    }

    private static func drawCaptionBar(_ cg: CGContext, size: CGSize, title: String, pageIndex: Int, total: Int) {
        UIColor.black.withAlphaComponent(0.28).setFill()
        UIRectFill(CGRect(x: 0, y: size.height - 100, width: size.width, height: 100))
        let caption = "\(title) · \(pageIndex + 1)/\(total)" as NSString
        caption.draw(
            in: CGRect(x: 36, y: size.height - 72, width: size.width - 72, height: 44),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
        )
    }

    private static func drawOrb(_ cg: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
        color.setFill()
        cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
