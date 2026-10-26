import Foundation
import SwiftSonic

/// Reads and writes `.m3u` and `.m3u8` playlists for Winamp mode.
///
/// Saved lists use each song's server `path`, so Navidrome can import a file placed in its music
/// folder. A song without a path is written as a `subsonic:song:<id>` URI, which only Minidisc
/// resolves.
nonisolated enum M3UPlaylist {
    static let header = "#EXTM3U"
    static let songURIPrefix = "subsonic:song:"

    /// One playlist line, with the `#EXTINF` metadata that preceded it.
    nonisolated struct Entry: Sendable, Hashable {
        /// The path or URI exactly as written.
        var location: String
        /// Seconds from `#EXTINF`; nil when absent or written as -1.
        var duration: Int?
        /// The text after the comma in `#EXTINF`, usually "Artist - Title".
        var displayTitle: String?

        init(location: String, duration: Int? = nil, displayTitle: String? = nil) {
            self.location = location
            self.duration = duration
            self.displayTitle = displayTitle
        }

        init(song: Song) {
            self.init(id: song.id, path: song.path, artist: song.artist, title: song.title, duration: song.duration)
        }

        /// Queue songs carry no server path; pass one when it is known.
        init(song: DisplayableSong, path: String? = nil) {
            self.init(id: song.id, path: path, artist: song.artist, title: song.title,
                      duration: song.duration > 0 ? Int(song.duration.rounded()) : nil)
        }

        private init(id: String, path: String?, artist: String?, title: String, duration: Int?) {
            let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
            let location = trimmedPath.flatMap { $0.isEmpty ? nil : $0 } ?? M3UPlaylist.songURI(id: id)
            let artist = artist?.trimmingCharacters(in: .whitespaces)
            let display = [artist, title].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " - ")
            self.init(location: location, duration: duration, displayTitle: display.isEmpty ? nil : display)
        }

        /// The artist half of "Artist - Title", if the display title has one.
        var artist: String? {
            guard let displayTitle, let range = displayTitle.range(of: " - ") else { return nil }
            let artist = displayTitle[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            return artist.isEmpty ? nil : artist
        }

        /// The title half of "Artist - Title", or the whole display title.
        var title: String? {
            guard let displayTitle else { return nil }
            let title: Substring = displayTitle.range(of: " - ").map { displayTitle[$0.upperBound...] } ?? displayTitle[...]
            let trimmed = title.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }

        /// A song ID from a `subsonic:song:` URI or a Subsonic `stream`/`download` URL.
        var songID: String? {
            if location.lowercased().hasPrefix(M3UPlaylist.songURIPrefix) {
                let id = String(location.dropFirst(M3UPlaylist.songURIPrefix.count)).removingPercentEncoding
                return id?.isEmpty == false ? id : nil
            }
            guard let components = URLComponents(string: location),
                  let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            let endpoint = components.path.split(separator: "/").last?.lowercased() ?? ""
            guard ["stream", "stream.view", "download", "download.view"].contains(endpoint) else { return nil }
            return components.queryItems?.first { $0.name == "id" }?.value
        }

        /// Path components for matching against server paths: separators unified, `.`, `..` and
        /// drive letters dropped, case folded. Nil for URLs that aren't `file:` URLs.
        var pathComponents: [String]? {
            var path = location
            if let scheme = URLComponents(string: location)?.scheme?.lowercased(), scheme.count > 1 {
                guard scheme == "file", let url = URL(string: location) else { return nil }
                path = url.path(percentEncoded: false)
            }
            let components = path.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .map(String.init)
                .filter { $0 != "." && $0 != ".." && !($0.count == 2 && $0.hasSuffix(":")) }
                .map(M3UPlaylist.foldedComponent)
            return components.isEmpty ? nil : components
        }
    }

    // MARK: Encoding

    /// UTF-8 `.m3u8` text with an `#EXTINF` line before every entry.
    static func encode(_ entries: [Entry]) -> Data {
        var lines = [header]
        for entry in entries {
            let title = (entry.displayTitle ?? "")
                .components(separatedBy: .newlines)
                .joined(separator: " ")
            lines.append("#EXTINF:\(entry.duration ?? -1),\(title)")
            lines.append(entry.location.components(separatedBy: .newlines).joined())
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func songURI(id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return songURIPrefix + (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)
    }

    // MARK: Decoding

    static func decode(_ data: Data) -> [Entry] {
        decode(text: text(from: data))
    }

    /// Accepts files with or without `#EXTM3U`, CRLF or CR line endings, comments and entries
    /// with no `#EXTINF` line.
    static func decode(text: String) -> [Entry] {
        var entries: [Entry] = []
        var pendingDuration: Int?
        var pendingTitle: String?
        for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                if line.uppercased().hasPrefix("#EXTINF:") {
                    (pendingDuration, pendingTitle) = parseExtInf(line.dropFirst("#EXTINF:".count))
                }
                continue
            }
            entries.append(Entry(location: line, duration: pendingDuration, displayTitle: pendingTitle))
            pendingDuration = nil
            pendingTitle = nil
        }
        return entries
    }

    /// Detects the encoding: a BOM wins, then strict UTF-8, then Windows-1252 / Latin-1, which is
    /// what Winamp wrote to `.m3u` files.
    static func text(from data: Data) -> String {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if bytes.starts(with: [0xFF, 0xFE]), let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return text
        }
        if bytes.starts(with: [0xFE, 0xFF]), let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// `#EXTINF:<seconds>[ key="value" …],<title>`. Extended attributes are skipped.
    private static func parseExtInf(_ body: Substring) -> (Int?, String?) {
        guard let comma = body.firstIndex(of: ",") else {
            return (parseDuration(body), nil)
        }
        let title = body[body.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        return (parseDuration(body[..<comma]), title.isEmpty ? nil : title)
    }

    private static func parseDuration(_ text: Substring) -> Int? {
        let number = text.trimmingCharacters(in: .whitespaces).prefix { !$0.isWhitespace }
        guard let seconds = Double(number), seconds >= 0 else { return nil }
        return Int(seconds.rounded())
    }

    /// Case, accents and Unicode normalisation folded so Windows and macOS paths compare equal.
    static func foldedComponent(_ component: String) -> String {
        component.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}
