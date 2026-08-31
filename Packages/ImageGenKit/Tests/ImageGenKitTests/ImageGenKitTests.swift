import CoreGraphics
import CoreImage
import XCTest
import VovoUI
@testable import ImageGenKit

final class ImageGenKitTests: XCTestCase {

    // MARK: - Templates

    func testPositivePromptLoadsForAllLanguages() {
        for lang in [AppLanguage.englishUS, .portugueseBrazil, .spanishSpain] {
            let p = ImageGenTemplate.positive(for: lang)
            XCTAssertFalse(p.isEmpty, "empty positive for \(lang)")
            XCTAssertTrue(p.lowercased().contains("anime"), "expected anime style in \(lang): \(p.prefix(60))")
        }
    }

    func testDefaultNegativeIsLockedKidsAntiPhotoreal() {
        let n = ImageGenTemplate.defaultNegativePrompt
        for term in ["photorealistic", "nsfw", "violence", "scary"] {
            XCTAssertTrue(n.lowercased().contains(term), "negative missing \(term): \(n.prefix(80))")
        }
    }

    // MARK: - Input

    func testEmptyImageIsInvalid() {
        let input = ImageGenInput(imageData: Data())
        XCTAssertTrue(input.isEmpty)
        XCTAssertNil(input.makeCGImage())
    }

    // MARK: - Config

    func testConfigDefaults() {
        let c = ImageGenConfig()
        XCTAssertEqual(c.strength, 0.6, accuracy: 0.001)
        XCTAssertEqual(c.stepCount, 25)
        XCTAssertEqual(c.guidanceScale, 6.0, accuracy: 0.001)
        XCTAssertEqual(c.scheduler, .dpmSolverMultistep)
        XCTAssertNil(c.seed)
        XCTAssertEqual(c.bucket, .square)
        XCTAssertEqual(c.mode, .imageToImage)
    }

    func testTextToImageModeIsDistinct() {
        var c = ImageGenConfig()
        c.mode = .textToImage
        XCTAssertEqual(c.mode, .textToImage)
        XCTAssertEqual(ImageGenMode.allCases.count, 2)
    }

    // MARK: - Bucket

    func testBucketPixelsForSD15() {
        let sq = ImageGenBucket.square.pixels(modelSize: .sd15)
        XCTAssertEqual(sq.width, 512); XCTAssertEqual(sq.height, 512)
        let pt = ImageGenBucket.portrait.pixels(modelSize: .sd15)
        XCTAssertEqual(pt.width, 512); XCTAssertEqual(pt.height, 768)
        let ls = ImageGenBucket.landscape.pixels(modelSize: .sd15)
        XCTAssertEqual(ls.width, 768); XCTAssertEqual(ls.height, 512)
    }

    func testBucketPixelsForSDXL() {
        let sq = ImageGenBucket.square.pixels(modelSize: .sdxl)
        XCTAssertEqual(sq.width, 1024); XCTAssertEqual(sq.height, 1024)
    }

    func testNearestBucketByAspect() {
        XCTAssertEqual(ImageGenBucket.nearest(toWidth: 1000, height: 1000), .square)
        XCTAssertEqual(ImageGenBucket.nearest(toWidth: 1080, height: 1920), .portrait)
        XCTAssertEqual(ImageGenBucket.nearest(toWidth: 1920, height: 1080), .landscape)
    }

    // MARK: - Resizer

    func testResizerProducesExactBucketDimensions() {
        guard let src = Self.makeCGImage(width: 4032, height: 3024) else { return XCTFail("src") }
        let out = ImageResizer.resize(src, toBucket: .square, modelSize: .sd15)
        XCTAssertEqual(out?.bucket, .square)
        XCTAssertEqual(out?.cgImage.width, 512)
        XCTAssertEqual(out?.cgImage.height, 512)
    }

    func testResizerCapsHugeInput() {
        // A 4000px-wide source should still be accepted (capped to maxInputSide then bucketed).
        guard let src = Self.makeCGImage(width: 4000, height: 4000) else { return XCTFail("src") }
        let out = ImageResizer.resize(src, toBucket: .square, modelSize: .sd15)
        XCTAssertEqual(out?.cgImage.width, 512)
        XCTAssertEqual(out?.cgImage.height, 512)
    }

    func testResizerPicksNearestBucketWhenUnspecified() {
        guard let portrait = Self.makeCGImage(width: 1080, height: 1920) else { return XCTFail("portrait") }
        let out = ImageResizer.resize(portrait, toBucket: nil, modelSize: .sd15)
        XCTAssertEqual(out?.bucket, .portrait)

        guard let landscape = Self.makeCGImage(width: 1920, height: 1080) else { return XCTFail("landscape") }
        let out2 = ImageResizer.resize(landscape, toBucket: nil, modelSize: .sd15)
        XCTAssertEqual(out2?.bucket, .landscape)
    }

    // MARK: - Pack store paths & validity

    func testPackResourcesPathIsUnderApplicationSupportNotDocuments() async throws {
        let store = CoreMLImagePackStore(storageRootURL: FileManager.default.temporaryDirectory)
        let url = await store.resourcesDirectory()
        let path = url.path
        // Injected temp root → path is under that temp dir, not under ~/Documents.
        XCTAssertFalse(path.contains("/Documents/Vovozinha/"), "pack must not be under Documents: \(path)")
        XCTAssertTrue(path.contains("ImagePack/Resources"), "expected ImagePack/Resources: \(path)")
    }

    func testEmptyDirectoryIsNotAValidPack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CoreMLImagePackStore(storageRootURL: root)
        let present = await store.isPackPresent()
        XCTAssertFalse(present)
    }

    func testDirectoryWithAllModelsButNoVAEEncoderIsInvalid() async throws {
        // A pack without VAEEncoder must NOT be considered valid (img2img requires it).
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("Vovozinha/ImagePack/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for m in ["TextEncoder.mlmodelc", "VAEDecoder.mlmodelc", "Unet.mlmodelc"] {
            try FileManager.default.createDirectory(
                at: resources.appendingPathComponent(m), withIntermediateDirectories: true
            )
        }
        // Deliberately omit VAEEncoder.mlmodelc.
        try Data("{}".utf8).write(to: resources.appendingPathComponent("vocab.json"))
        try Data("{}".utf8).write(to: resources.appendingPathComponent("merges.txt"))

        let store = CoreMLImagePackStore(storageRootURL: root)
        let present = await store.isPackPresent()
        XCTAssertFalse(present, "pack without VAEEncoder must be invalid for img2img")
    }

    func testDirectoryWithAllModelsIncludingVAEEncoderIsValid() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("Vovozinha/ImagePack/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for m in ["TextEncoder.mlmodelc", "VAEDecoder.mlmodelc", "VAEEncoder.mlmodelc", "Unet.mlmodelc"] {
            try FileManager.default.createDirectory(
                at: resources.appendingPathComponent(m), withIntermediateDirectories: true
            )
        }
        try Data("{}".utf8).write(to: resources.appendingPathComponent("vocab.json"))
        try Data("{}".utf8).write(to: resources.appendingPathComponent("merges.txt"))

        let store = CoreMLImagePackStore(storageRootURL: root)
        let present = await store.isPackPresent()
        XCTAssertTrue(present)
        let supportsImg2Img = await store.supportsImageToImage()
        XCTAssertTrue(supportsImg2Img)
        let supportsTxt2Img = await store.supportsTextToImage()
        XCTAssertTrue(supportsTxt2Img)
    }

    func testChunkedUnetIsValid() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("Vovozinha/ImagePack/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for m in ["TextEncoder.mlmodelc", "VAEDecoder.mlmodelc", "VAEEncoder.mlmodelc",
                  "UnetChunk1.mlmodelc", "UnetChunk2.mlmodelc"] {
            try FileManager.default.createDirectory(
                at: resources.appendingPathComponent(m), withIntermediateDirectories: true
            )
        }
        try Data("{}".utf8).write(to: resources.appendingPathComponent("vocab.json"))
        try Data("{}".utf8).write(to: resources.appendingPathComponent("merges.txt"))

        let store = CoreMLImagePackStore(storageRootURL: root)
        let present = await store.isPackPresent()
        XCTAssertTrue(present)
    }

    // MARK: - SHA-256 parsing

    func testParseSHA256AcceptsShasumStyle() throws {
        let hex = try CoreMLImagePackStore.parseSHA256File(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  AnimeImg2Img-SD15.zip"
        )
        XCTAssertEqual(hex.count, 64)
        XCTAssertTrue(hex.allSatisfy { $0.isHex })
    }

    func testParseSHA256AcceptsBareHex() throws {
        let hex = try CoreMLImagePackStore.parseSHA256File(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(hex.count, 64)
    }

    func testParseSHA256RejectsGarbage() {
        XCTAssertThrowsError(try CoreMLImagePackStore.parseSHA256File("not a hash"))
    }

    func testSHA256RoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello imagegen".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let hex = try CoreMLImagePackStore.sha256Hex(ofFileAt: tmp)
        XCTAssertEqual(hex.count, 64)
        try CoreMLImagePackStore.verifySHA256(ofFileAt: tmp, expectedHex: hex)  // no throw
    }

    // MARK: - DeviceImageGenerator error paths

    func testDeviceGeneratorThrowsPackNotInstalledWhenAbsent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CoreMLImagePackStore(storageRootURL: root)
        let gen = DeviceImageGenerator(
            packStore: store,
            modelSize: .sd15,
            sessionProvider: { _ in MockImageGenSession() }  // must not be called
        )
        let png = Self.onePixelPNG()
        do {
            _ = try await gen.generate(ImageGenInput(imageData: png), config: ImageGenConfig())
            XCTFail("expected packNotInstalled")
        } catch let e as ImageGenError {
            XCTAssertEqual(e, .packNotInstalled)
        }
    }

    func testDeviceGeneratorThrowsInvalidImageForEmptyInput() async throws {
        // Build a store that reports present + supports img2img, so we reach the image check.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("Vovozinha/ImagePack/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for m in ["TextEncoder.mlmodelc", "VAEDecoder.mlmodelc", "VAEEncoder.mlmodelc", "Unet.mlmodelc"] {
            try FileManager.default.createDirectory(at: resources.appendingPathComponent(m), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: resources.appendingPathComponent("vocab.json"))
        try Data("{}".utf8).write(to: resources.appendingPathComponent("merges.txt"))

        let store = CoreMLImagePackStore(storageRootURL: root)
        let gen = DeviceImageGenerator(
            packStore: store, modelSize: .sd15,
            sessionProvider: { _ in MockImageGenSession() }
        )
        do {
            _ = try await gen.generate(ImageGenInput(imageData: Data()), config: ImageGenConfig())
            XCTFail("expected invalidImage")
        } catch let e as ImageGenError {
            XCTAssertEqual(e, .invalidImage)
        }
    }

    // MARK: - Helpers

    private static func onePixelPNG() -> Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
    }

    private static func makeCGImage(width: Int, height: Int) -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

private extension Character {
    var isHex: Bool { ("0"..."9").contains(self) || ("a"..."f").contains(self) }
}

// MARK: - Mock session

private final class MockImageGenSession: CoreMLImageGenSessioning, @unchecked Sendable {
    func generate(
        from sourceImage: CGImage?,
        prompt: String,
        negativePrompt: String,
        config: ImageGenConfig,
        modelSize: ImageGenModelSize
    ) async throws -> ImageGenResult {
        throw ImageGenError.generationFailed  // default mock: not exercised in the error-path tests
    }
}
