import Foundation
import SwiftSonic

/// Turns the play queue into `.m3u8` entries that `M3UPlaylistResolver` reads back.
///
/// Each entry has an `#EXTINF` line with "Artist - Title" and the song's path on the server,
/// "Artist/Album/01 - Title.flac", the layout Navidrome's folders follow. When the server doesn't
/// give a path, the same layout is built from the song's tags. Songs from local files aren't on
/// the server and are left out.
nonisolated enum M3UQueueExport {
    /// The queue's server songs as playlist entries; `paths` holds server paths by song ID.
    static func entries(for songs: [DisplayableSong], paths: [String: String]) -> [M3UPlaylist.Entry] {
        songs.prefix(M3UPlaylist.maximumEntries).compactMap { song in
            guard !song.isLocalFile else { return nil }
            let path = paths[song.id].flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            return M3UPlaylist.Entry(song: song, path: path ?? libraryPath(for: song))
        }
    }

    /// "Artist/Album/NN - Title", with characters that would split a folder name replaced.
    static func libraryPath(for song: DisplayableSong) -> String {
        let artist = component(song.artist, fallback: "Unknown Artist")
        let album = component(song.albumName, fallback: "Unknown Album")
        var file = component(song.title, fallback: song.id)
        if let track = song.trackNumber, track > 0 {
            file = String(format: "%02d - ", track) + file
        }
        if let format = song.audioFormat?.lowercased(), !format.isEmpty, format.allSatisfy({ $0.isLetter || $0.isNumber }) {
            file += "." + format
        }
        return [artist, album, file].joined(separator: "/")
    }

    private static func component(_ text: String?, fallback: String) -> String {
        let cleaned = (text ?? "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? fallback : cleaned
    }

    /// Server paths for the queue's songs, looked up four at a time like the resolver's lookups.
    /// Songs the server can't find, or lookups that fail, are simply missing from the result.
    static func serverPaths(for songs: [DisplayableSong], lookup: any M3USongLookup) async -> [String: String] {
        let ids = Array(Set(songs.prefix(M3UPlaylist.maximumEntries).filter { !$0.isLocalFile }.map(\.id)))
        var paths: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            var next = 0
            func addNext() {
                guard next < ids.count else { return }
                let id = ids[next]
                next += 1
                group.addTask { (id, try? await lookup.song(id: id)?.path) }
            }
            for _ in 0..<min(M3UPlaylistResolver.maximumConcurrentLookups, ids.count) { addNext() }
            while let (id, path) = await group.next() {
                if !Task.isCancelled, let path { paths[id] = path }
                if !Task.isCancelled { addNext() }
            }
        }
        return paths
    }
}
