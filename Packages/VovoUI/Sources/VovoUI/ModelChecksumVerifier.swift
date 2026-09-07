import Foundation
import CryptoKit

public enum ModelChecksumError: Error, LocalizedError, Equatable, Sendable {
    case checksumMismatch
    case checksumFileInvalid
    case checksumUnavailable

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "File failed integrity check."
        case .checksumFileInvalid:
            return "Could not read the download checksum from the server."
        case .checksumUnavailable:
            return "Could not download the integrity checksum."
        }
    }
}

/// Common SHA-256 downloading, parsing, and file hashing logic for on-device packs.
public enum ModelChecksumVerifier: Sendable {
    public static func fetchRemoteSHA256(
        from url: URL,
        userAgent: String,
        session: URLSession
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw ModelDownloadError.http(statusCode: http.statusCode)
            }
        } else if !url.isFileURL {
            throw ModelChecksumError.checksumUnavailable
        }
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            throw ModelChecksumError.checksumFileInvalid
        }
        return try parseSHA256File(text)
    }

    public static func parseSHA256File(_ text: String) throws -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        for line in lines {
            let token = line.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            let hex = token.lowercased()
            if hex.count == 64, hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) {
                return hex
            }
        }
        throw ModelChecksumError.checksumFileInvalid
    }

    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) // 1 MB
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verifySHA256(ofFileAt url: URL, expectedHex: String) throws {
        let actual = try sha256Hex(ofFileAt: url)
        let expected = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard actual == expected else {
            throw ModelChecksumError.checksumMismatch
        }
    }
}
