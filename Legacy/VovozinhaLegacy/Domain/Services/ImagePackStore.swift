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

        let hasUnet = hasChunkedUnet(at: url) || fm.fileExists(atPath: url.appendingPathComponent("Unet.mlmodelc").path)
        return hasUnet
            && fm.fileExists(atPath: textEncoder)
            && fm.fileExists(atPath: vaeDec)
            && fm.fileExists(atPath: vocab)
            && fm.fileExists(atPath: merges)
    }

    /// Chunked Unet peaks lower RAM than a single `Unet.mlmodelc` (preferred on iPhone).
    static func hasChunkedUnet(at url: URL = resourcesURL) -> Bool {
        let fm = FileManager.default
        let chunk1 = url.appendingPathComponent("UnetChunk1.mlmodelc").path
        let chunk2 = url.appendingPathComponent("UnetChunk2.mlmodelc").path
        return fm.fileExists(atPath: chunk1) && fm.fileExists(atPath: chunk2)
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
            if isAnimePack {
                switch lang {
                case .portugueseBrazil:
                    return "Pacote de imagens instalado · cenas mais ricas no aparelho."
                case .englishUS:
                    return "Picture pack installed · richer scenes on this device."
                case .spanishSpain:
                    return "Paquete de imágenes instalado · escenas más ricas en el dispositivo."
                }
            }
            // Older / unknown pack — parent-friendly upgrade nudge.
            return L10n.t(.settingsImagePackLegacyHint, lang)
        }
        switch lang {
        case .portugueseBrazil:
            return "Sem pacote de imagens · histórias usam desenhos simples. Baixe em Ajustes (~1,5 GB, Wi‑Fi)."
        case .englishUS:
            return "No picture pack · stories use simple drawings. Download in Settings (~1.5 GB, Wi‑Fi)."
        case .spanishSpain:
            return "Sin paquete de imágenes · las historias usan dibujos simples. Descarga en Ajustes (~1,5 GB, Wi‑Fi)."
        }
    }
}
