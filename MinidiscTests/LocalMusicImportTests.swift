import Foundation
import Testing
@testable import Minidisc

/// Files and folders chosen for the queue, as Winamp mode's ADD > FILE and ADD > DIR add them on
/// the Mac. The store and its bookmarks are shared with the iPhone's local music.
@Suite struct LocalMusicImportTests {
    private struct Library {
        let root: URL
        let index: URL
        let album: URL
        let loose: URL

        /// Music/Album/{B, A, Disc 2/C}.wav and Elsewhere/Loose.wav.
        init() throws {
            root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            index = root.appendingPathComponent("Index")
            album = root.appendingPathComponent("Music/Album")
            let disc = album.appendingPathComponent("Disc 2")
            let elsewhere = root.appendingPathComponent("Elsewhere")
            for folder in [disc, elsewhere] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            try LocalMusicFixture.wav(at: album.appendingPathComponent("B.wav"))
            try LocalMusicFixture.wav(at: album.appendingPathComponent("A.wav"))
            try LocalMusicFixture.wav(at: disc.appendingPathComponent("C.wav"))
            try Data("not audio".utf8).write(to: album.appendingPathComponent("cover.txt"))
            loose = elsewhere.appendingPathComponent("Loose.wav")
            try LocalMusicFixture.wav(at: loose)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func chosenFilesAndFoldersComeBackInTheOrderChosen() async throws {
        let library = try Library()
        defer { library.remove() }
        let store = LocalMusicStore(directory: library.index)
        let imported = try await store.importSongs([library.loose, library.album], limit: 100)
        // The file where it was picked, then the folder's files by path, subfolders included.
        #expect(imported.songs.map(\.title) == ["Loose", "A", "B", "C"])
        #expect(!imported.isTruncated)
        #expect(imported.songs.allSatisfy { $0.isLocalFile && $0.id.hasPrefix("local:") && $0.duration > 0 })

        // Choosing them again adds no new entries and no duplicates.
        let again = try await store.importSongs([library.album, library.loose, library.loose], limit: 100)
        #expect(again.songs.map(\.title) == ["A", "B", "C", "Loose"])
        #expect(await store.current().folders.count == 2)
    }

    @Test func aChosenFilePlaysAfterARelaunch() async throws {
        let library = try Library()
        defer { library.remove() }
        let store = LocalMusicStore(directory: library.index)
        let imported = try await store.importSongs([library.loose], limit: 100)
        let song = try #require(imported.songs.first)
        let reference = try #require(song.localFile)
        #expect(reference.relativePath == "Loose.wav")
        let entry = try #require(await store.current().folders.first)
        #expect(entry.isFile == true)

        let relaunched = LocalMusicStore(directory: library.index)
        let access = try await relaunched.access(reference)
        #expect(access.url.standardizedFileURL == library.loose.standardizedFileURL)
        // A rescan keeps the same song.
        #expect(try await relaunched.refresh().tracks.map(\.id) == [song.id])

        // Removed from disk, it's unavailable rather than gone from the index.
        try FileManager.default.removeItem(at: library.loose)
        await #expect(throws: LocalMusicError.self) { try await relaunched.access(reference) }
        let rescanned = try await relaunched.refresh()
        #expect(rescanned.tracks.map(\.isAvailable) == [false])
        #expect(rescanned.folders.first?.isAccessible == false)
    }

    @Test func aFolderInsideAnAddedOneIsFoundByWhereItsFilesAre() async throws {
        let library = try Library()
        defer { library.remove() }
        let store = LocalMusicStore(directory: library.index)
        _ = try await store.importSongs([library.album.deletingLastPathComponent()], limit: 100)
        // Disc 2's song is already indexed under Music; choosing Disc 2 still finds it.
        let disc = try await store.importSongs([library.album.appendingPathComponent("Disc 2")], limit: 100)
        #expect(disc.songs.map(\.title) == ["C"])
        let music = try #require(await store.current().folders.first)
        #expect(disc.songs.first?.localFile?.folderID == music.id)
    }

    @Test func importsStopAtTheLimit() async throws {
        let library = try Library()
        defer { library.remove() }
        let store = LocalMusicStore(directory: library.index)
        let imported = try await store.importSongs([library.album], limit: 2)
        #expect(imported.songs.map(\.title) == ["A", "B"])
        #expect(imported.isTruncated)
    }

    @Test func aFolderWithNoAudioGivesNoSongs() async throws {
        let library = try Library()
        defer { library.remove() }
        let empty = library.root.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let store = LocalMusicStore(directory: library.index)
        #expect(try await store.importSongs([empty], limit: 100).songs.isEmpty)
        await #expect(throws: LocalMusicError.self) {
            try await store.importSongs([library.root.appendingPathComponent("Missing")], limit: 100)
        }
    }

    @Test func indexesFromBeforeChosenFilesStillDecode() throws {
        let legacy = #"{"folders":[{"id":"6F1C2D3E-0000-4000-8000-000000000001","name":"Music","bookmark":"","isAccessible":true}],"tracks":[]}"#
        let snapshot = try JSONDecoder().decode(LocalMusicSnapshot.self, from: Data(legacy.utf8))
        #expect(snapshot.folders.first?.isFile == nil)
        // A folder entry is written without the key, as before.
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("isFile"))
    }
}
