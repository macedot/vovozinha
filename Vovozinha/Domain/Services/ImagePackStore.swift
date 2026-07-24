import Foundation

/// Offline image-model pack layout for Core ML Stable Diffusion (anime-tuned by default).
///
/// Install (once, offline use forever after):
/// - In-app: Settings → Image pack → Download
/// - CLI: `./scripts/download_sd_pack.sh`
///
/// Layout:
/// ```
/// Application Support/Vovozinha/ImagePack/Resources/
///   TextEncoder.mlmodelc
///   Unet.mlmodelc  OR  UnetChunk1.mlmodelc + UnetChunk2.mlmodelc
///   VAEDecoder.mlmodelc
///   VAEEncoder.mlmodelc   # required for page-to-page img2img
///   vocab.json
///   merges.txt
/// pack.json               # manifest (anime vs legacy)
/// ```
enum ImagePackStore {
    static let packFolderName = "ImagePack"
    static let resourcesFolderName = "Resources"
    static let manifestFileName = "pack.json"

    struct PackManifest: Codable, Equatable {
        var id: String
        var repoID: String
        var zipFileName: String
        var displayName: String
        var installedAt: String
    }

    static var packRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = base
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent(packFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static var resourcesURL: URL {
        packRootURL.appendingPathComponent(resourcesFolderName, isDirectory: true)
    }

    static var manifestURL: URL {
        packRootURL.appendingPathComponent(manifestFileName)
    }

    /// Documents mirror for Simulator convenience (optional).
    static var documentsPackURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs
            .appendingPathComponent("Vovozinha", isDirectory: true)
            .appendingPathComponent(packFolderName, isDirectory: true)
            .appendingPathComponent(resourcesFolderName, isDirectory: true)
    }

    /// Prefer Application Support; fall back to Documents path used by download script --sim.
    static var activeResourcesURL: URL? {
        if hasRequiredModels(at: resourcesURL) { return resourcesURL }
        if hasRequiredModels(at: documentsPackURL) { return documentsPackURL }
        return nil
    }

    static var isNeuralPackReady: Bool {
        activeResourcesURL != nil
    }

    static var isAnimePack: Bool {
        if let m = readManifest(), m.id == ImagePackDownloader.packKindID {
            return true
        }
        // Heuristic: no manifest but models present → legacy Apple / unknown.
        return false
    }

    static func hasRequiredModels(at url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let textEncoder = url.appendingPathComponent("TextEncoder.mlmodelc").path
        let vaeDec = url.appendingPathComponent("VAEDecoder.mlmodelc").path
        let vocab = url.appendingPathComponent("vocab.json").path
        let merges = url.appendingPathComponent("merges.txt").path
        let unet = url.appendingPathComponent("Unet.mlmodelc").path
        let chunk1 = url.appendingPathComponent("UnetChunk1.mlmodelc").path
        let chunk2 = url.appendingPathComponent("UnetChunk2.mlmodelc").path

        let hasUnet = fm.fileExists(atPath: unet)
            || (fm.fileExists(atPath: chunk1) && fm.fileExists(atPath: chunk2))
        return hasUnet
            && fm.fileExists(atPath: textEncoder)
            && fm.fileExists(atPath: vaeDec)
            && fm.fileExists(atPath: vocab)
            && fm.fileExists(atPath: merges)
    }

    /// Whether img2img temporal chain is available (VAEEncoder present).
    static var supportsImageToImage: Bool {
        guard let base = activeResourcesURL else { return false }
        return FileManager.default.fileExists(
            atPath: base.appendingPathComponent("VAEEncoder.mlmodelc").path
        )
    }

    static func writeManifest(_ manifest: PackManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    static func readManifest() -> PackManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(PackManifest.self, from: data)
    }

    static func clearManifest() {
        try? FileManager.default.removeItem(at: manifestURL)
    }

    static func statusSummary(lang: AppLanguage) -> String {
        if isNeuralPackReady {
            let img2 = supportsImageToImage
            let anime = isAnimePack
            switch lang {
            case .portugueseBrazil:
                if anime {
                    return img2
                        ? "Pack anime (Anything V5 Ink) · img2img entre páginas."
                        : "Pack anime instalado · sem VAEEncoder (só text2img)."
                }
                return img2
                    ? "Pack Core ML (legado) · re-baixe para o pack anime."
                    : "Pack Core ML (legado, sem img2img) · re-baixe o pack anime em Ajustes."
            case .englishUS:
                if anime {
                    return img2
                        ? "Anime pack (Anything V5 Ink) · page-to-page img2img."
                        : "Anime pack installed · no VAEEncoder (text2img only)."
                }
                return img2
                    ? "Legacy Core ML pack · re-download for the anime pack."
                    : "Legacy Core ML pack (no img2img) · re-download the anime pack in Settings."
            case .spanishSpain:
                if anime {
                    return img2
                        ? "Pack anime (Anything V5 Ink) · img2img entre páginas."
                        : "Pack anime instalado · sin VAEEncoder (solo text2img)."
                }
                return img2
                    ? "Pack Core ML (legado) · vuelve a descargar el pack anime."
                    : "Pack Core ML (legado, sin img2img) · descarga el pack anime en Ajustes."
            }
        }
        switch lang {
        case .portugueseBrazil:
            return "Sem pack: arte procedural. Baixe o pack anime em Ajustes (~1,5 GB). Depois fica offline."
        case .englishUS:
            return "No pack: procedural art. Download the anime pack in Settings (~1.5 GB). Then it stays offline."
        case .spanishSpain:
            return "Sin pack: arte procedural. Descarga el pack anime en Ajustes (~1,5 GB). Luego queda offline."
        }
    }
}
