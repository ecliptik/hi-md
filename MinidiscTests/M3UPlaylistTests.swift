import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("M3U playlists")
struct M3UPlaylistTests {
    private func song(_ id: String, _ title: String, artist: String? = nil, path: String? = nil, duration: Int? = nil) -> Song {
        Song(id: id, title: title, isDir: false, artist: artist, duration: duration, path: path)
    }

    // MARK: Encoding

    @Test func encodesExtendedM3U8WithPathsAndSongURIFallback() throws {
        let entries = [
            M3UPlaylist.Entry(song: song("s1", "Dancing Queen", artist: "ABBA", path: "ABBA/Arrival/02 - Dancing Queen.flac", duration: 231)),
            M3UPlaylist.Entry(song: song("s 2/x", "Untitled", path: nil, duration: nil)),
        ]
        let text = try #require(String(data: M3UPlaylist.encode(entries), encoding: .utf8))
        #expect(text == """
        #EXTM3U
        #EXTINF:231,ABBA - Dancing Queen
        ABBA/Arrival/02 - Dancing Queen.flac
        #EXTINF:-1,Untitled
        subsonic:song:s%202%2Fx

        """)
    }

    @Test func encodesQueueSongsWithAKnownPath() {
        let queued = DisplayableSong(from: song("q1", "Jóga", artist: "Björk", duration: 305))
        let withPath = M3UPlaylist.Entry(song: queued, path: "Björk/Homogenic/02 Jóga.mp3")
        let withoutPath = M3UPlaylist.Entry(song: queued)
        #expect(withPath.location == "Björk/Homogenic/02 Jóga.mp3")
        #expect(withPath.duration == 305)
        #expect(withPath.displayTitle == "Björk - Jóga")
        #expect(withoutPath.location == "subsonic:song:q1")
    }

    @Test func newlinesInTagsCannotBreakTheFile() {
        let entry = M3UPlaylist.Entry(location: "a.mp3", duration: 1, displayTitle: "Line\nBreak")
        let decoded = M3UPlaylist.decode(M3UPlaylist.encode([entry]))
        #expect(decoded == [M3UPlaylist.Entry(location: "a.mp3", duration: 1, displayTitle: "Line Break")])
    }

    @Test func roundTripsUnicodeThroughUTF8() {
        let entries = [M3UPlaylist.Entry(song: song("1", "Ænima", artist: "Tool", path: "Tool/Ænima/13 Ænima.flac", duration: 400))]
        #expect(M3UPlaylist.decode(M3UPlaylist.encode(entries)) == entries)
    }

    // MARK: Decoding

    @Test func decodesCRLFCommentsAndMissingExtInf() {
        let text = "#EXTM3U\r\n# a comment\r\n#EXTINF:120,Artist - Song\r\nfolder\\song.mp3\r\n\r\n#EXTGRP:ignored\r\nplain.mp3\r\n"
        let entries = M3UPlaylist.decode(Data(text.utf8))
        #expect(entries == [
            M3UPlaylist.Entry(location: "folder\\song.mp3", duration: 120, displayTitle: "Artist - Song"),
            M3UPlaylist.Entry(location: "plain.mp3"),
        ])
    }

    @Test func decodesFilesWithoutHeaderAndOldMacLineEndings() {
        let entries = M3UPlaylist.decode(Data("one.mp3\rtwo.mp3\r".utf8))
        #expect(entries.map(\.location) == ["one.mp3", "two.mp3"])
    }

    @Test func extInfWithAttributesAndMinusOne() {
        let text = "#EXTINF:-1 tvg-id=\"x\",Stream Title\nhttp://radio/stream\n#EXTINF:12.6,A - B\nb.mp3\n"
        let entries = M3UPlaylist.decode(text: text)
        #expect(entries[0].duration == nil)
        #expect(entries[0].displayTitle == "Stream Title")
        #expect(entries[1].duration == 13)
        #expect(entries[1].artist == "A")
        #expect(entries[1].title == "B")
    }

    @Test func stripsUTF8ByteOrderMark() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("#EXTM3U\n#EXTINF:5,Sigur Rós - Hoppípolla\nx.mp3\n".utf8))
        let entries = M3UPlaylist.decode(data)
        #expect(entries.count == 1)
        #expect(entries[0].artist == "Sigur Rós")
        #expect(entries[0].title == "Hoppípolla")
    }

    @Test func decodesUTF16WithByteOrderMark() throws {
        var data = Data([0xFF, 0xFE])
        data.append(try #require("#EXTINF:1,Café - Señor\nc.mp3\n".data(using: .utf16LittleEndian)))
        #expect(M3UPlaylist.decode(data).first?.displayTitle == "Café - Señor")
    }

    @Test func fallsBackToLatin1ForInvalidUTF8() {
        // "Café - Señor" in Latin-1: é = 0xE9, ñ = 0xF1, which aren't valid UTF-8 on their own.
        let bytes = Array("#EXTINF:1,Caf".utf8) + [0xE9] + Array(" - Se".utf8) + [0xF1] + Array("or\nCaf".utf8) + [0xE9] + Array(".mp3\n".utf8)
        let entries = M3UPlaylist.decode(Data(bytes))
        #expect(entries.first?.displayTitle == "Café - Señor")
        #expect(entries.first?.location == "Café.mp3")
    }

    @Test func songIDsFromURIsAndStreamURLs() {
        #expect(M3UPlaylist.Entry(location: "subsonic:song:abc%2F1").songID == "abc/1")
        #expect(M3UPlaylist.Entry(location: "SUBSONIC:song:xyz").songID == "xyz")
        #expect(M3UPlaylist.Entry(location: "https://music.example/rest/stream.view?u=a&id=42&v=1").songID == "42")
        #expect(M3UPlaylist.Entry(location: "https://music.example/rest/stream?id=7").songID == "7")
        #expect(M3UPlaylist.Entry(location: "https://example.com/other?id=7").songID == nil)
        #expect(M3UPlaylist.Entry(location: "Artist/Album/a.mp3").songID == nil)
    }

    @Test func pathComponentsNormaliseRelativeWindowsAndFileURLs() {
        #expect(M3UPlaylist.Entry(location: "../Artist/Album/01 Song.MP3").pathComponents == ["artist", "album", "01 song.mp3"])
        #expect(M3UPlaylist.Entry(location: "C:\\Music\\Artist\\Song.mp3").pathComponents == ["music", "artist", "song.mp3"])
        #expect(M3UPlaylist.Entry(location: "./Song.mp3").pathComponents == ["song.mp3"])
        #expect(M3UPlaylist.Entry(location: "file:///Users/me/Music/A%20B/c.flac").pathComponents == ["users", "me", "music", "a b", "c.flac"])
        #expect(M3UPlaylist.Entry(location: "http://host/a.mp3").pathComponents == nil)
    }
}

// MARK: - Resolving

private actor FakeSongLookup: M3USongLookup {
    let songs: [Song]
    private(set) var queries: [String] = []

    init(songs: [Song]) {
        self.songs = songs
    }

    func song(id: String) async throws -> Song? {
        songs.first { $0.id == id }
    }

    func searchSongs(_ query: String) async throws -> [Song] {
        queries.append(query)
        let folded = query.lowercased()
        return songs.filter { $0.title.lowercased().contains(folded) }
    }
}

@Suite("M3U playlist resolver")
struct M3UPlaylistResolverTests {
    private static let library = [
        Song(id: "1", title: "Intro", isDir: false, artist: "Band A", duration: 60, path: "Band A/First/01 Intro.flac"),
        Song(id: "2", title: "Intro", isDir: false, artist: "Band B", duration: 90, path: "Band B/Second/01 Intro.flac"),
        Song(id: "3", title: "Hyperballad", isDir: false, artist: "Björk", duration: 321, path: "Björk/Post/05 Hyperballad.flac"),
        Song(id: "4", title: "Teardrop", isDir: false, artist: "Massive Attack", duration: 330, path: "Massive Attack/Mezzanine/03 Teardrop.flac"),
        Song(id: "5", title: "Teardrop", isDir: false, artist: "Massive Attack", duration: 200, path: "Massive Attack/Live/07 Teardrop.flac"),
    ]

    @Test func resolvesBySongIDFirst() async throws {
        let resolver = M3UPlaylistResolver(lookup: FakeSongLookup(songs: Self.library))
        let results = try await resolver.resolve([M3UPlaylist.Entry(location: "subsonic:song:3")])
        #expect(results[0].song?.id == "3")
        #expect(results[0].match == .songID)
    }

    @Test func resolvesByPathSuffixBeforeTags() async throws {
        let resolver = M3UPlaylistResolver(lookup: FakeSongLookup(songs: Self.library))
        // The tags say Band A, but the path is Band B's: the path wins.
        let entry = M3UPlaylist.Entry(location: "/mnt/music/band b/Second/01 Intro.flac", duration: 60, displayTitle: "Band A - Intro")
        let results = try await resolver.resolve([entry])
        #expect(results[0].song?.id == "2")
        #expect(results[0].match == .path)
    }

    @Test func aBareFileNameMatchesOnlyWhenUnique() async throws {
        let resolver = M3UPlaylistResolver(lookup: FakeSongLookup(songs: Self.library))
        let results = try await resolver.resolve([
            M3UPlaylist.Entry(location: "05 Hyperballad.flac"),
            M3UPlaylist.Entry(location: "01 Intro.flac"),
        ])
        #expect(results[0].song?.id == "3")
        #expect(results[0].match == .path)
        // Two albums open with "01 Intro.flac" and there is no artist to choose between them.
        #expect(results[1].song == nil)
        #expect(results[1].match == .unresolved)
    }

    @Test func fallsBackToArtistAndTitleIgnoringCaseAndAccents() async throws {
        let resolver = M3UPlaylistResolver(lookup: FakeSongLookup(songs: Self.library))
        let entry = M3UPlaylist.Entry(location: "D:\\Old Rips\\track05.mp3", duration: 321, displayTitle: "BJORK - hyperballad")
        let results = try await resolver.resolve([entry])
        #expect(results[0].song?.id == "3")
        #expect(results[0].match == .artistAndTitle)
    }

    @Test func durationBreaksTiesBetweenVersions() async throws {
        let resolver = M3UPlaylistResolver(lookup: FakeSongLookup(songs: Self.library))
        let entry = M3UPlaylist.Entry(location: "teardrop.mp3", duration: 201, displayTitle: "Massive Attack - Teardrop")
        let results = try await resolver.resolve([entry])
        #expect(results[0].song?.id == "5")
    }

    @Test func tagsComeFromThePathWithoutExtInf() async throws {
        let resolver = M3UPlaylistResolver(lookup: FakeSongLookup(songs: Self.library))
        let entry = M3UPlaylist.Entry(location: "Elsewhere/Massive Attack/Mezzanine/03 - Teardrop.mp3")
        #expect(M3UPlaylistResolver.tags(for: entry) == .init(artist: "Massive Attack", title: "Teardrop"))
        let results = try await resolver.resolve([entry])
        // The path differs (mp3 vs flac), so this is a tag match on the first Massive Attack Teardrop.
        #expect(results[0].match == .artistAndTitle)
        #expect(results[0].song?.artist == "Massive Attack")
    }

    @Test func unknownSongsStayUnresolvedInOrder() async throws {
        let lookup = FakeSongLookup(songs: Self.library)
        let resolver = M3UPlaylistResolver(lookup: lookup)
        let results = try await resolver.resolve([
            M3UPlaylist.Entry(location: "x.mp3", displayTitle: "Nobody - Nothing"),
            M3UPlaylist.Entry(location: "subsonic:song:404"),
            M3UPlaylist.Entry(location: "Band A/First/01 Intro.flac", displayTitle: "Band A - Intro"),
            M3UPlaylist.Entry(location: "Band B/Second/01 Intro.flac", displayTitle: "Band B - Intro"),
        ])
        #expect(results.map(\.song?.id) == [nil, nil, "1", "2"])
        // Both Intro entries share one cached search.
        #expect(await lookup.queries.filter { $0 == "Intro" }.count == 1)
    }

    @Test func stripsTrackNumbers() {
        #expect(M3UPlaylistResolver.stripTrackNumber("01 - Song") == "Song")
        #expect(M3UPlaylistResolver.stripTrackNumber("1-03 Song Name") == "Song Name")
        #expect(M3UPlaylistResolver.stripTrackNumber("07. Song") == "Song")
        #expect(M3UPlaylistResolver.stripTrackNumber("Song 2") == "Song 2")
    }

    @Test func honoursCancellation() async {
        let resolver = M3UPlaylistResolver(lookup: FakeSongLookup(songs: Self.library))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await resolver.resolve([M3UPlaylist.Entry(location: "subsonic:song:1")])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
