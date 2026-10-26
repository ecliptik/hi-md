import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Playlist library")
@MainActor
struct PlaylistLibraryViewModelTests {
    @Test("Playlists load sorted by name")
    func loadsSortedPlaylists() async {
        let service = PlaylistLibraryStub(names: ["Zebra", "alpha", "Mix 10", "Mix 2"])
        let model = PlaylistLibraryViewModel(playlistService: service, toastService: ToastService())
        await model.load()
        #expect(model.playlists.map(\.name) == ["alpha", "Mix 2", "Mix 10", "Zebra"])
        #expect(model.error == nil)
    }

    @Test("A failed load keeps the list and reports the error")
    func failedLoadKeepsList() async {
        let service = PlaylistLibraryStub(names: ["Road Trip"])
        let model = PlaylistLibraryViewModel(playlistService: service, toastService: ToastService())
        await model.load()
        service.fails = true
        await model.load()
        #expect(model.playlists.map(\.name) == ["Road Trip"])
        #expect(model.error != nil)
    }

    @Test("Creating trims the name, adds the dragged songs and lists the new playlist")
    func createsWithSongs() async throws {
        let service = PlaylistLibraryStub(names: ["Existing"])
        let model = PlaylistLibraryViewModel(playlistService: service, toastService: ToastService())
        let created = try #require(await model.create(name: "  Late Night  ", songs: [song("s1"), song("s2")]))
        #expect(created.name == "Late Night")
        #expect(service.createdNames == ["Late Night"])
        #expect(service.added[created.id] == ["s1", "s2"])
        #expect(model.playlists.map(\.name) == ["Existing", "Late Night"])
    }

    @Test("A blank name creates nothing")
    func blankNameIsRejected() async {
        let service = PlaylistLibraryStub(names: [])
        let model = PlaylistLibraryViewModel(playlistService: service, toastService: ToastService())
        #expect(await model.create(name: "   ") == nil)
        #expect(service.createdNames.isEmpty)
        #expect(!PlaylistLibraryViewModel.isValidName(" \n"))
        #expect(PlaylistLibraryViewModel.isValidName("x"))
    }

    @Test("Renaming sends the trimmed name and skips an unchanged one")
    func renames() async throws {
        let service = PlaylistLibraryStub(names: ["Old"])
        let model = PlaylistLibraryViewModel(playlistService: service, toastService: ToastService())
        await model.load()
        let playlist = try #require(model.playlists.first)
        #expect(await model.rename(playlist, to: "Old"))
        #expect(service.renames.isEmpty)
        #expect(await model.rename(playlist, to: " New "))
        #expect(service.renames.map(\.name) == ["New"])
        #expect(model.playlists.map(\.name) == ["New"])
    }

    @Test("A refused rename keeps the old name and shows an error")
    func refusedRename() async throws {
        let service = PlaylistLibraryStub(names: ["Old"])
        let toasts = ToastService()
        let model = PlaylistLibraryViewModel(playlistService: service, toastService: toasts)
        await model.load()
        service.fails = true
        #expect(!(await model.rename(try #require(model.playlists.first), to: "New")))
        #expect(model.playlists.map(\.name) == ["Old"])
        #expect(toasts.current?.style == .error)
    }

    @Test("Deleting removes the playlist only after the server confirms it")
    func deletes() async throws {
        let service = PlaylistLibraryStub(names: ["Keep", "Gone"])
        let model = PlaylistLibraryViewModel(playlistService: service, toastService: ToastService())
        await model.load()
        let gone = try #require(model.playlists.first { $0.name == "Gone" })

        service.fails = true
        #expect(!(await model.delete(gone, purgeDownloads: false)))
        #expect(model.playlists.count == 2)

        service.fails = false
        #expect(await model.delete(gone, purgeDownloads: true))
        #expect(model.playlists.map(\.name) == ["Keep"])
        #expect(service.deletions.map(\.purge) == [true])
    }

    private func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: id, artist: nil, albumId: nil, albumName: nil, artistId: nil, genre: nil,
            duration: 60, trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }
}

/// An in-memory server: no request reaches a real Navidrome.
@MainActor
private final class PlaylistLibraryStub: PlaylistServiceProtocol {
    var fails = false
    private var playlists: [Playlist]
    private(set) var createdNames: [String] = []
    private(set) var added: [String: [String]] = [:]
    private(set) var renames: [(id: String, name: String)] = []
    private(set) var deletions: [(id: String, purge: Bool)] = []

    init(names: [String]) {
        playlists = names.enumerated().map { Playlist(id: "p\($0.offset)", name: $0.element, songCount: 0, duration: 0) }
    }

    func listPlaylists() async throws -> [Playlist] {
        if fails { throw URLError(.timedOut) }
        return playlists
    }

    func getPlaylist(id: String) async throws -> PlaylistWithSongs {
        PlaylistWithSongs(id: id, name: playlists.first { $0.id == id }?.name ?? "", songCount: 0, duration: 0, entry: [])
    }

    func createPlaylist(name: String, description: String?) async throws -> PlaylistWithSongs {
        if fails { throw URLError(.timedOut) }
        createdNames.append(name)
        let id = "new\(createdNames.count)"
        playlists.append(Playlist(id: id, name: name, songCount: 0, duration: 0))
        return PlaylistWithSongs(id: id, name: name, songCount: 0, duration: 0, entry: [])
    }

    func renamePlaylist(id: String, newName: String) async throws {
        if fails { throw URLError(.timedOut) }
        renames.append((id, newName))
        playlists = playlists.map { $0.id == id ? Playlist(id: id, name: newName, songCount: 0, duration: 0) : $0 }
    }

    func addTracks(playlistId: String, songs: [Song]) async throws {
        if fails { throw URLError(.timedOut) }
        added[playlistId, default: []] += songs.map(\.id)
    }

    func deletePlaylist(id: String, purgeDownloads: Bool) async throws {
        if fails { throw URLError(.timedOut) }
        deletions.append((id, purgeDownloads))
        playlists.removeAll { $0.id == id }
    }

    func updateDescription(id: String, description: String) async throws {}
    func removeTracks(playlistId: String, indices: [Int]) async throws {}
    func reorderTracks(playlistId: String, orderedSongIds: [String]) async throws {}
}
