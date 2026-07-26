import Foundation
import zlib

/// Minimal ZIP reader for Core ML pack archives (store + raw deflate).
/// Streams large entries to disk so ~1.5 GB packs fit on-device.
enum ZipExtractor {
    enum ZipError: LocalizedError {
        case notAZip
        case unsupportedCompression(UInt16)
        case corrupt
        case inflateFailed
        case io

        var errorDescription: String? {
            switch self {
            case .notAZip: return "Not a valid ZIP archive."
            case .unsupportedCompression(let m): return "Unsupported ZIP compression method (\(m))."
            case .corrupt: return "ZIP archive is corrupt."
            case .inflateFailed: return "Failed to decompress a ZIP entry."
            case .io: return "ZIP read/write failed."
            }
        }
    }

    /// Extract `zipURL` into `destination`.
    /// - Parameter skipPathContains: path fragments to skip (e.g. SafetyChecker).
    static func extract(
        zipURL: URL,
        to destination: URL,
        skipPathContains: [String] = ["SafetyChecker"],
        onProgress: ((Double) -> Void)? = nil
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let data = try Data(contentsOf: zipURL, options: [.mappedIfSafe])
        guard data.count >= 22 else { throw ZipError.notAZip }

        guard let eocd = findEOCD(in: data) else { throw ZipError.notAZip }
        let entryCount = Int(eocd.totalEntries)
        var cdOffset = Int(eocd.cdOffset)
        var extracted = 0

        for _ in 0..<entryCount {
            guard cdOffset + 46 <= data.count else { throw ZipError.corrupt }
            let sig = readU32(data, cdOffset)
            guard sig == 0x0201_4b50 else { throw ZipError.corrupt }

            let method = readU16(data, cdOffset + 10)
            let compSize = Int(readU32(data, cdOffset + 20))
            let nameLen = Int(readU16(data, cdOffset + 28))
            let extraLen = Int(readU16(data, cdOffset + 30))
            let commentLen = Int(readU16(data, cdOffset + 32))
            let localHeaderOffset = Int(readU32(data, cdOffset + 42))

            let nameStart = cdOffset + 46
            guard nameStart + nameLen <= data.count else { throw ZipError.corrupt }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? "entry"
            cdOffset = nameStart + nameLen + extraLen + commentLen

            if skipPathContains.contains(where: { name.contains($0) }) {
                extracted += 1
                onProgress?(Double(extracted) / Double(max(entryCount, 1)))
                continue
            }

            if name.hasSuffix("/") {
                let dir = destination.appendingPathComponent(name)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                extracted += 1
                onProgress?(Double(extracted) / Double(max(entryCount, 1)))
                continue
            }

            guard localHeaderOffset + 30 <= data.count else { throw ZipError.corrupt }
            let localSig = readU32(data, localHeaderOffset)
            guard localSig == 0x0403_4b50 else { throw ZipError.corrupt }
            let localNameLen = Int(readU16(data, localHeaderOffset + 26))
            let localExtraLen = Int(readU16(data, localHeaderOffset + 28))
            let dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            guard dataStart + compSize <= data.count else { throw ZipError.corrupt }

            let outURL = destination.appendingPathComponent(name)
            try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            switch method {
            case 0:
                let payload = data.subdata(in: dataStart..<(dataStart + compSize))
                try payload.write(to: outURL, options: .atomic)
            case 8:
                try inflateRawDeflateToFile(
                    data: data,
                    compressedRange: dataStart..<(dataStart + compSize),
                    to: outURL
                )
            default:
                throw ZipError.unsupportedCompression(method)
            }

            extracted += 1
            onProgress?(Double(extracted) / Double(max(entryCount, 1)))
        }
    }

    // MARK: - zlib raw inflate → file

    private static func inflateRawDeflateToFile(
        data: Data,
        compressedRange: Range<Int>,
        to outURL: URL
    ) throws {
        if FileManager.default.fileExists(atPath: outURL.path) {
            try FileManager.default.removeItem(at: outURL)
        }
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outURL)
        defer { try? handle.close() }

        var strm = z_stream()
        // windowBits = -15 → raw DEFLATE (ZIP)
        let initRC = inflateInit2_(&strm, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initRC == Z_OK else { throw ZipError.inflateFailed }
        defer { inflateEnd(&strm) }

        let outChunk = 256 * 1024
        var outBuf = [UInt8](repeating: 0, count: outChunk)
        let inChunk = 256 * 1024
        var offset = compressedRange.lowerBound
        let end = compressedRange.upperBound

        try data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw ZipError.inflateFailed
            }

            var finished = false
            while offset < end && !finished {
                let len = min(inChunk, end - offset)
                strm.next_in = UnsafeMutablePointer(mutating: base + offset)
                strm.avail_in = uInt(len)
                offset += len
                let isLast = offset >= end

                repeat {
                    guard let outBase = outBuf.withUnsafeMutableBufferPointer({ $0.baseAddress }) else {
                        throw ZipError.inflateFailed
                    }
                    strm.next_out = outBase
                    strm.avail_out = uInt(outChunk)
                    let flush = isLast ? Z_FINISH : Z_NO_FLUSH
                    let rc = inflate(&strm, flush)
                    if rc != Z_OK && rc != Z_STREAM_END && rc != Z_BUF_ERROR {
                        throw ZipError.inflateFailed
                    }
                    let produced = outChunk - Int(strm.avail_out)
                    if produced > 0 {
                        try handle.write(contentsOf: Data(bytes: outBase, count: produced))
                    }
                    if rc == Z_STREAM_END {
                        finished = true
                        break
                    }
                } while strm.avail_out == 0
            }
        }
    }

    // MARK: - EOCD

    private struct EOCD {
        var totalEntries: UInt16
        var cdOffset: UInt32
    }

    private static func findEOCD(in data: Data) -> EOCD? {
        let maxScan = min(data.count, 22 + 65_535)
        let start = data.count - maxScan
        var i = data.count - 22
        while i >= start {
            if readU32(data, i) == 0x0605_4b50 {
                let totalEntries = readU16(data, i + 10)
                let cdOffset = readU32(data, i + 16)
                return EOCD(totalEntries: totalEntries, cdOffset: cdOffset)
            }
            i -= 1
        }
        return nil
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
