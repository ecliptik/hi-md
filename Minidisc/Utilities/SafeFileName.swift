import CryptoKit
import Foundation

/// Song and cover IDs come from the server and become file names. An ordinary ID is used as it is,
/// so files saved by earlier builds keep their names. An ID that could leave its folder, or that is
/// too long for a file name, is replaced by its SHA-256 hash.
nonisolated enum SafeFileName {
    /// Leaves room for an extension or a `@tier` suffix under the 255-byte file-name limit.
    static let maximumIDBytes = 200
    static let hashedPrefix = "id-sha256-"

    /// Extensions a downloaded song may be saved with; anything else becomes `bin`.
    static let audioExtensions: Set<String> = [
        "aac", "ac3", "aif", "aiff", "alac", "ape", "caf", "dff", "dsf", "flac", "m4a", "m4b",
        "mka", "mp3", "mp4", "mpc", "mpeg", "oga", "ogg", "opus", "spx", "tta", "wav", "webm",
        "wma", "wv",
    ]

    static func forID(_ id: String) -> String {
        guard !isSafe(id) else { return id }
        let digest = SHA256.hash(data: Data(id.utf8))
        return hashedPrefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id != "." && id != ".."
            && id.utf8.count <= maximumIDBytes
            // A server could otherwise pick an ID that collides with another ID's hashed name.
            && !id.hasPrefix(hashedPrefix)
            && !id.unicodeScalars.contains { $0 == "/" || $0 == "\\" || $0 == "\u{0}" }
    }

    /// The lowercased extension if it is a known audio container, otherwise nil.
    static func audioExtension(_ candidate: String?) -> String? {
        guard let candidate = candidate?.lowercased(), audioExtensions.contains(candidate) else { return nil }
        return candidate
    }

    /// `relativePath` inside `directory`, or nil if it would resolve anywhere else.
    static func url(forRelativePath relativePath: String, in directory: URL) -> URL? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("\u{0}") })
        else { return nil }
        let url = directory.appendingPathComponent(relativePath, isDirectory: false)
        let root = directory.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return nil }
        return url
    }
}
