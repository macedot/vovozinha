import Foundation
import UIKit
import PDFKit

enum PDFExporter {
    static func export(story: Story, storage: FileStorage = .shared) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let lang = story.language

        let data = renderer.pdfData { context in
            context.beginPage()
            drawCover(in: pageRect, story: story, storage: storage, lang: lang)

            for page in story.sortedPages {
                context.beginPage()
                drawStoryPage(in: pageRect, page: page, title: story.title, storage: storage, lang: lang)
            }
        }

        return try storage.savePDF(data: data, storyID: story.id)
    }

    private static func drawCover(in rect: CGRect, story: Story, storage: FileStorage, lang: AppLanguage) {
        let bg = UIColor(red: 0.12, green: 0.10, blue: 0.28, alpha: 1)
        bg.setFill()
        UIRectFill(rect)

        // TEXT_ONLY_PHASE: optional cover image only if graphics produced one.
        if FeatureFlags.graphicsEnabled, let image = story.coverUIImage(storage: storage) {
            let imageRect = CGRect(x: 72, y: 100, width: rect.width - 144, height: 320)
            image.draw(in: imageRect)
        }

        let titleY: CGFloat = FeatureFlags.graphicsEnabled ? 450 : 220
        let title = story.title as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1)
        ]
        title.draw(in: CGRect(x: 48, y: titleY, width: rect.width - 96, height: 120), withAttributes: titleAttrs)

        let blurb = coverBlurb(lang: lang, lesson: story.lesson, pageCount: story.sortedPages.count) as NSString
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor(red: 0.96, green: 0.72, blue: 0.35, alpha: 1)
        ]
        blurb.draw(
            in: CGRect(x: 48, y: titleY + 130, width: rect.width - 96, height: 80),
            withAttributes: subAttrs
        )
    }

    private static func drawStoryPage(
        in rect: CGRect,
        page: StoryPage,
        title: String,
        storage: FileStorage,
        lang: AppLanguage
    ) {
        UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1).setFill()
        UIRectFill(rect)

        var textTop: CGFloat = 48
        if FeatureFlags.graphicsEnabled,
           let path = page.imagePath,
           let image = storage.loadImage(relativePath: path) {
            let imageRect = CGRect(x: 48, y: 40, width: rect.width - 96, height: 300)
            image.draw(in: imageRect)
            textTop = 360
        }

        let pageLabel = pageLabelText(lang: lang, index: page.index + 1) as NSString
        pageLabel.draw(
            in: CGRect(x: 48, y: textTop, width: rect.width - 96, height: 20),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.darkGray
            ]
        )

        let body = page.text as NSString
        body.draw(
            in: CGRect(x: 48, y: textTop + 28, width: rect.width - 96, height: rect.height - textTop - 80),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor.black
            ]
        )
    }

    private static func coverBlurb(lang: AppLanguage, lesson: String, pageCount: Int) -> String {
        switch lang {
        case .portugueseBrazil:
            return "Uma história infantil da Vovozinha\nLição: \(lesson)\n\(pageCount) páginas"
        case .englishUS:
            return "A Vovozinha children's story\nLesson: \(lesson)\n\(pageCount) pages"
        case .spanishSpain:
            return "Un cuento infantil de Vovozinha\nLección: \(lesson)\n\(pageCount) páginas"
        }
    }

    private static func pageLabelText(lang: AppLanguage, index: Int) -> String {
        switch lang {
        case .portugueseBrazil: return "Página \(index)"
        case .englishUS: return "Page \(index)"
        case .spanishSpain: return "Página \(index)"
        }
    }
}
