import CoreGraphics
import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

private func queueSong(_ id: String, title: String? = nil, artist: String? = "Artist", album: String? = "Album",
                       duration: TimeInterval = 180, track: Int? = nil, suffix: String? = "flac") -> DisplayableSong {
    DisplayableSong(from: Song(id: id, title: title ?? "Song \(id)", album: album, artist: artist, track: track,
                               suffix: suffix, duration: Int(duration)))
}

// MARK: - M3U export

@Suite("M3U queue export")
struct M3UQueueExportTests {
    @Test func entriesUseServerPathsOrTheArtistAlbumLayout() {
        let songs = [queueSong("1", title: "Jóga", artist: "Björk", album: "Homogenic", duration: 305, track: 2),
                     queueSong("2", title: "AC/DC Song", artist: nil, album: nil, duration: 0, suffix: nil),
                     queueSong("3", title: "Known")]
        let entries = M3UQueueExport.entries(for: songs, paths: ["3": "Artist/Album/03 Known.mp3"])
        #expect(entries.map(\.location) == ["Björk/Homogenic/02 - Jóga.flac",
                                            "Unknown Artist/Unknown Album/AC-DC Song",
                                            "Artist/Album/03 Known.mp3"])
        #expect(entries[0].displayTitle == "Björk - Jóga")
        #expect(entries[0].duration == 305)
        #expect(entries[1].duration == nil)
    }

    @Test func localFilesAreLeftOut() {
        var local = queueSong("local")
        local.localFile = LocalFileReference(folderID: UUID(), relativePath: "a.flac")
        #expect(M3UQueueExport.entries(for: [local, queueSong("1")], paths: [:]).count == 1)
    }

    @Test func savedQueueReadsBackAsTheSameSongs() async throws {
        let library = [
            Song(id: "1", title: "Hyperballad", album: "Post", artist: "Björk", track: 5, suffix: "flac", duration: 321,
                 path: "Björk/Post/05 Hyperballad.flac"),
            Song(id: "2", title: "Intro", album: "First", artist: "Band A", track: 1, suffix: "flac", duration: 60,
                 path: "Band A/First/01 Intro.flac"),
            Song(id: "3", title: "Intro", album: "Second", artist: "Band B", track: 1, suffix: "flac", duration: 90,
                 path: "Band B/Second/01 Intro.flac"),
        ]
        let lookup = ExportLookup(songs: library)
        let queue = [library[2], library[0], library[1]].map { DisplayableSong(from: $0) }
        let paths = await M3UQueueExport.serverPaths(for: queue, lookup: lookup)
        #expect(paths.count == 3)
        let data = M3UPlaylist.encode(M3UQueueExport.entries(for: queue, paths: paths))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("#EXTM3U\n#EXTINF:90,Band B - Intro\nBand B/Second/01 Intro.flac\n"))

        let resolved = try await M3UPlaylistResolver(lookup: lookup).resolve(M3UPlaylist.decode(data))
        #expect(resolved.map(\.song?.id) == ["3", "1", "2"])
        #expect(resolved.allSatisfy { $0.match == .path })
    }

    @Test func pathsWithoutAServerStillResolveByTags() async throws {
        let library = [Song(id: "9", title: "Jóga", album: "Homogenic", artist: "Björk", duration: 305, path: "x/y/z.flac")]
        let queue = [DisplayableSong(from: library[0])]
        let data = M3UPlaylist.encode(M3UQueueExport.entries(for: queue, paths: [:]))
        let resolved = try await M3UPlaylistResolver(lookup: ExportLookup(songs: library)).resolve(M3UPlaylist.decode(data))
        #expect(resolved.first?.song?.id == "9")
        #expect(resolved.first?.match == .artistAndTitle)
    }
}

private actor ExportLookup: M3USongLookup {
    let songs: [Song]

    init(songs: [Song]) {
        self.songs = songs
    }

    func song(id: String) async throws -> Song? {
        songs.first { $0.id == id }
    }

    func searchSongs(_ query: String) async throws -> [Song] {
        songs.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
