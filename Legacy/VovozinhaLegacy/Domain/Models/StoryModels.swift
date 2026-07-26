import Foundation
import SwiftData
import UIKit

@Model
final class Story {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String
    var characterName: String
    var characterAppearance: String
    var setting: String
    var lesson: String
    var ageBandRaw: String
    var artStyleRaw: String
    var childName: String
    /// BCP-47 style code for the language the story text was written in (pt-BR / en-US / es-ES).
    /// Default keeps older SwiftData rows readable if the field is missing.
    var languageRaw: String = AppLanguage.portugueseBrazil.rawValue
    var createdAt: Date
    var coverImagePath: String?
    @Relationship(deleteRule: .cascade, inverse: \StoryPage.story)
    var pages: [StoryPage]

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        characterName: String,
        characterAppearance: String,
        setting: String,
        lesson: String,
        ageBand: AgeBand,
        artStyle: ArtStyle,
        childName: String = "",
        language: AppLanguage = .portugueseBrazil,
        createdAt: Date = .now,
        coverImagePath: String? = nil,
        pages: [StoryPage] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.characterName = characterName
        self.characterAppearance = characterAppearance
        self.setting = setting
        self.lesson = lesson
        self.ageBandRaw = ageBand.rawValue
        self.artStyleRaw = artStyle.rawValue
        self.childName = childName
        self.languageRaw = language.rawValue
        self.createdAt = createdAt
        self.coverImagePath = coverImagePath
        self.pages = pages
    }

    var ageBand: AgeBand {
        AgeBand(rawValue: ageBandRaw) ?? .threeToFive
    }

    var artStyle: ArtStyle {
        ArtStyle(rawValue: artStyleRaw) ?? .watercolor
    }

    /// Language the body text was generated in (fallback: system).
    var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.fromSystem()
    }

    var sortedPages: [StoryPage] {
        pages.sorted { $0.index < $1.index }
    }

    var fullText: String {
        sortedPages.map(\.text).joined(separator: "\n\n")
    }
}

@Model
final class StoryPage {
    var id: UUID
    var index: Int
    var text: String
    var imagePrompt: String
    var imagePath: String?
    var story: Story?

    init(
        id: UUID = UUID(),
        index: Int,
        text: String,
        imagePrompt: String,
        imagePath: String? = nil
    ) {
        self.id = id
        self.index = index
        self.text = text
        self.imagePrompt = imagePrompt
        self.imagePath = imagePath
    }
}

extension Story {
    func coverUIImage(storage: FileStorage = .shared) -> UIImage? {
        if let coverImagePath {
            return storage.loadImage(relativePath: coverImagePath)
        }
        if let first = sortedPages.first?.imagePath {
            return storage.loadImage(relativePath: first)
        }
        return nil
    }
}
