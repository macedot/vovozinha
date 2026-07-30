import Foundation

/// UI strings for PT / EN / ES loaded from Markdown under `Resources/Strings/`.
///
/// Edit `Resources/Strings/{en-US,pt-BR,es-ES}.md` and rebuild — do not hardcode
/// user-facing copy here.
public enum VovoL10n {
    public enum Key: String, Sendable {
        case language

        // Story prompt feature
        case storySeedTitle
        case storySeedSubtitle
        case storySeedPlaceholder
        case storyWordCount
        case storyNeedMinWords
        case storyTooLong
        case storyCreate
        case storyScene
        case storyInvalidPrompt
        case storyGenerateFailed
        case storyModelNotInstalled
        case storyModelGateTitle
        case storyModelGateBody
        case storyModelGateDownload
        case storyModelGateImport
        case storyModelGateOpenFallback
        case storyModelGateNotNow
        case storyModelGateDownloading
        case storyModelGateVerifying
        case storyModelGateUnpacking
        case storyModelGateImporting
        case storyModelGateRetry
        case storyModelGateHaltedTitle
        case storyModelGateHaltedBody
        case storyModelGateChecking
        case storyModelGateFilenameHint
        case storyModelGateDownloadSpeed
        case storyModelGateDownloadElapsed
        case storyModelGateDownloadETA
        case storyModelGateDownloadETAUnknown
        case storyModelGateDownloadBytes
        case storyModelUpdateTitle
        case storyModelUpdateBody
        case storyModelUpdateAction
        case storyModelUpdateLater
        case storyModelRemove
        case storyModelRemoveConfirmTitle
        case storyModelRemoveConfirmBody
        case storyModelRemoveConfirmAction
        case storyModelRemoveCancel
        case storyValidationTooShort
        case storyValidationTooLong
    }

    public static func t(_ key: Key, _ lang: AppLanguage) -> String {
        string(key.rawValue, lang: lang)
    }

    public static func wordCount(current: Int, max: Int, lang: AppLanguage) -> String {
        string(
            "wordCount",
            lang: lang,
            vars: ["current": "\(current)", "max": "\(max)"]
        )
    }

    public static func needMinWords(_ min: Int, lang: AppLanguage) -> String {
        string("needMinWords", lang: lang, vars: ["min": "\(min)"])
    }

    public static func tooLong(max: Int, lang: AppLanguage) -> String {
        string("tooLongMax", lang: lang, vars: ["max": "\(max)"])
    }

    public static func scene(_ index: Int, lang: AppLanguage) -> String {
        string("sceneLabel", lang: lang, vars: ["index": "\(index)"])
    }

    public static func validationTooShort(min: Int, current: Int, lang: AppLanguage) -> String {
        string(
            "validationTooShort",
            lang: lang,
            vars: ["min": "\(min)", "current": "\(current)"]
        )
    }

    public static func validationTooLong(max: Int, current: Int, lang: AppLanguage) -> String {
        string(
            "validationTooLong",
            lang: lang,
            vars: ["max": "\(max)", "current": "\(current)"]
        )
    }

    public static func downloadSpeed(_ speed: String, lang: AppLanguage) -> String {
        string("storyModelGateDownloadSpeed", lang: lang, vars: ["speed": speed])
    }

    public static func downloadElapsed(_ time: String, lang: AppLanguage) -> String {
        string("storyModelGateDownloadElapsed", lang: lang, vars: ["time": time])
    }

    public static func downloadETA(_ time: String, lang: AppLanguage) -> String {
        string("storyModelGateDownloadETA", lang: lang, vars: ["time": time])
    }

    public static func downloadBytes(received: String, total: String, lang: AppLanguage) -> String {
        string(
            "storyModelGateDownloadBytes",
            lang: lang,
            vars: ["received": received, "total": total]
        )
    }

    public static func seedSubtitle(min: Int, max: Int, lang: AppLanguage) -> String {
        string(
            "seedSubtitle",
            lang: lang,
            vars: ["min": "\(min)", "max": "\(max)"]
        )
    }

    // MARK: - Loading

    private static func string(
        _ key: String,
        lang: AppLanguage,
        vars: [String: String] = [:]
    ) -> String {
        let path = "Strings/\(lang.rawValue).md"
        let fallbackPath = "Strings/\(AppLanguage.englishUS.rawValue).md"
        let primary = MarkdownTextCatalog.text(
            key,
            from: path,
            bundle: .module,
            vars: vars,
            sourceFallbackRoot: sourceStringsRoot
        )
        if !primary.isEmpty { return primary }

        let english = MarkdownTextCatalog.text(
            key,
            from: fallbackPath,
            bundle: .module,
            vars: vars,
            sourceFallbackRoot: sourceStringsRoot
        )
        return english.isEmpty ? key : english
    }

    /// Repo path when `Bundle.module` resources are missing (some test hosts).
    private static var sourceStringsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VovoUI/
            .appendingPathComponent("Resources")
    }
}
