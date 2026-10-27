import Testing
import Foundation
import SwiftSonic
@testable import Minidisc

// MARK: - Stubs

/// Every endpoint throws — PlaylistDetailViewModel's offline paths must never
/// reach the server; loadFromAPI's failure is the trigger under test.
@MainActor
private final class PDLibraryStub: PlaylistBrowsing {
    /// When set, `playlist(id:)` returns this instead of throwing — used to drive the
    /// empty-but-successful (200, no entries) path that the catch block can't catch.
    var playlistResult: PlaylistWithSongs?
    var failure: SwiftSonicError?
    @MainActor
    func playlist(id: String) async throws -> PlaylistWithSongs {
        if let failure { throw failure }
        if let playlistResult { return playlistResult }
        throw URLError(.notConnectedToInternet)
    }
    func playlists() async throws -> [Playlist] { throw URLError(.unknown) }
}

@MainActor
private final class PDDownloadStub: DownloadServiceProtocol {
    var playlistData: LocalPlaylistData?

    let progressStream: AsyncStream<[DownloadProgress]> = AsyncStream { $0.finish() }
    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? { playlistData }
    func localArtistData(artistId: String, artistName: String?, serverId: UUID) async -> LocalArtistData? { nil }
    func backfillPlaylistSongIds(playlistId: String, serverId: UUID, orderedSongIds: [String]) async {}
    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData? { nil }
    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? { nil }
    func isDownloaded(songId: String, serverId: UUID) async -> Bool { false }
    func downloadedSongIds(serverId: UUID) async -> Set<String> { [] }
    func localCoverArtURL(forId coverArtId: String) async -> URL? { nil }
    func persistCover(_ data: Data, forId coverArtId: String) async {}
    func removeCover(forId coverArtId: String) async {}
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int { 0 }
    func coverCacheStats() async -> (count: Int, bytes: Int64) { (0, 0) }
    func clearAllCovers() async {}
    func download(song: Song, serverId: UUID) async throws { throw URLError(.unknown) }
    func download(album: AlbumID3, serverId: UUID) async throws { throw URLError(.unknown) }
    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws { throw URLError(.unknown) }
    func isDownloading(songId: String, serverId: UUID) async -> Bool { false }
    func isDownloadingAlbum(_ albumId: String) async -> Bool { false }
    func isDownloadingPlaylist(_ playlistId: String) async -> Bool { false }
    func cancelDownload(songId: String, serverId: UUID) async {}
    func remove(songId: String, serverId: UUID) async throws { throw URLError(.unknown) }
    func remove(albumId: String, serverId: UUID) async throws { throw URLError(.unknown) }
    func remove(playlistId: String, serverId: UUID) async throws { throw URLError(.unknown) }
    func removeAll() async throws { throw URLError(.unknown) }
}

@MainActor
private final class PDPlaylistStub: PlaylistServiceProtocol {
    var calls: [String] = []
    var failsAt: String?
    private func record(_ operation: String) throws {
        calls.append(operation)
        if failsAt == operation { throw URLError(.timedOut) }
    }
    func listPlaylists() async throws -> [Playlist] { throw URLError(.unknown) }
    func getPlaylist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    @discardableResult
    func createPlaylist(name: String, description: String?) async throws -> PlaylistWithSongs { throw URLError(.unknown) }
    func renamePlaylist(id: String, newName: String) async throws { try record("rename") }
    func updateDescription(id: String, description: String) async throws { try record("description:\(description)") }
    func addTracks(playlistId: String, songs: [Song]) async throws { throw URLError(.unknown) }
    func removeTracks(playlistId: String, indices: [Int]) async throws { try record("remove:\(indices)") }
    func reorderTracks(playlistId: String, orderedSongIds: [String]) async throws { try record("reorder") }
    func deletePlaylist(id: String, purgeDownloads: Bool) async throws { throw URLError(.unknown) }
}

// MARK: - Tests

@Suite("PlaylistDetailViewModel — offline local fallback")
@MainActor
struct PlaylistDetailOfflineTests {

    private func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Track \(id)", artist: "Artist", albumId: nil,
            albumName: nil, artistId: nil, genre: nil, duration: 180,
            trackNumber: nil, isDownloaded: true, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private func makeVM(playlistData: LocalPlaylistData?, isOnline: Bool, apiPlaylist: PlaylistWithSongs? = nil, failure: SwiftSonicError? = nil) -> PlaylistDetailViewModel {
        let state = ServerState()
        state.isOnline = isOnline
        state.activeServer = ServerSnapshot(from: ServerConfig(
            displayName: "S", baseURL: "https://s.example.com", username: "u", isActive: true
        ))
        let download = PDDownloadStub()
        download.playlistData = playlistData
        let library = PDLibraryStub()
        library.playlistResult = apiPlaylist
        library.failure = failure
        return PlaylistDetailViewModel(
            playlistId: "playlist-1",
            libraryService: library,
            downloadService: download,
            playlistService: PDPlaylistStub(),
            toastService: ToastService(),
            serverState: state
        )
    }

    private var emptySuccessPlaylist: PlaylistWithSongs {
        PlaylistWithSongs(id: "playlist-1", name: "Road Trip", songCount: 0, duration: 0)
    }

    private var downloadedPlaylist: LocalPlaylistData {
        LocalPlaylistData(
            playlistId: "playlist-1", name: "Road Trip", coverArtId: nil,
            songs: [song("1"), song("2")]
        )
    }

    @Test("downloaded playlist falls back to local when the server call fails (stale isOnline)")
    func downloadedPlaylistFallsBackOnServerFailure() async {
        let vm = makeVM(playlistData: downloadedPlaylist, isOnline: true)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
        #expect(vm.name == "Road Trip")
    }

    @Test("transient failure with no local copy shows the error, not a false offline state")
    func transientFailureWithoutLocalCopyShowsError() async {
        let vm = makeVM(playlistData: nil, isOnline: true)
        await vm.load()
        #expect(vm.error != nil)
        #expect(vm.isOffline == false)
        #expect(vm.songs.isEmpty)
    }

    @Test("genuinely offline, downloaded playlist loads from local with no server call")
    func offlineDownloadedPlaylistLoadsLocally() async {
        let vm = makeVM(playlistData: downloadedPlaylist, isOnline: false)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
    }

    @Test("genuinely offline, non-downloaded playlist shows the empty state — no error")
    func offlineNonDownloadedShowsEmptyState() async {
        let vm = makeVM(playlistData: nil, isOnline: false)
        await vm.load()
        #expect(vm.songs.isEmpty)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
    }

    // MARK: - Empty-success (WARP / Cloudflare edge) — the case the throw-only stubs missed

    @Test("empty-success playlist response with a downloaded copy loads local, not Empty")
    func emptySuccessFallsBackToLocal() async {
        let vm = makeVM(playlistData: downloadedPlaylist, isOnline: true, apiPlaylist: emptySuccessPlaylist)
        await vm.load()
        #expect(vm.songs.count == 2)
        #expect(vm.error == nil)
        #expect(vm.isOffline == true)
        #expect(vm.name == "Road Trip")
    }

    @Test("empty-success playlist with NO downloaded copy stays empty, no error")
    func emptySuccessNoLocalStaysEmpty() async {
        let vm = makeVM(playlistData: nil, isOnline: true, apiPlaylist: emptySuccessPlaylist)
        await vm.load()
        #expect(vm.songs.isEmpty)
        #expect(vm.error == nil)
    }
    @Test func removedPlaylistPreservesDownloadedCopy() async throws {
        let vm = makeVM(playlistData: downloadedPlaylist, isOnline: true, failure: try await playlistServerError())
        await vm.load()
        #expect(vm.isRemovedFromServer)
        #expect(vm.songs.map(\.id) == ["1", "2"])
        #expect(vm.playlistDetail == nil)
        #expect(vm.error == nil)
        let playable = await vm.playbackSongs(from: downloadedPlaylist.songs)
        #expect(playable.map(\.id) == ["1", "2"])
    }

    @Test func removedPlaylistClearsAnOldScreenAndDoesNotStartDeadTracks() async throws {
        let vm = makeVM(playlistData: nil, isOnline: true, failure: try await playlistServerError())
        vm.songs = downloadedPlaylist.songs
        await vm.load()
        #expect(vm.isRemovedFromServer)
        #expect(vm.songs.isEmpty)
        #expect(await vm.playbackSongs(from: downloadedPlaylist.songs).isEmpty)
    }

    @Test func proxy404DoesNotConfirmPlaylistRemoval() async {
        let vm = makeVM(playlistData: nil, isOnline: true, failure: .httpError(
            statusCode: 404, endpoint: "getPlaylist", serverHost: "s.example.com"
        ))
        vm.songs = downloadedPlaylist.songs
        await vm.load()
        #expect(!vm.isRemovedFromServer)
        #expect(vm.songs.count == 2)
        #expect(vm.error != nil)
    }

}

@Suite @MainActor
struct PlaylistEditCommitterTests {
    @Test func metadataFollowsReplacementIncludingEmptyDescription() async throws {
        let service = PDPlaylistStub()
        try await PlaylistEditCommitter.commit(.init(name: "New", orderedSongIDs: ["2", "1"], description: ""), playlistID: "p", service: service)
        #expect(service.calls == ["reorder", "rename", "description:"])
    }

    @Test func failureStopsTheCommitAndAllowsAnIdempotentRetry() async {
        let service = PDPlaylistStub()
        let toast = ToastService()
        service.failsAt = "rename"
        let edits = PlaylistEdits(name: "New", orderedSongIDs: ["2", "1"], description: "Notes")
        let first = await toast.perform { try await PlaylistEditCommitter.commit(edits, playlistID: "p", service: service) }
        #expect(!first)
        #expect(service.calls == ["reorder", "rename"])
        #expect(toast.current?.style == .error)
        service.failsAt = nil
        let retry = await toast.perform { try await PlaylistEditCommitter.commit(edits, playlistID: "p", service: service) }
        #expect(retry)
        #expect(service.calls == ["reorder", "rename", "reorder", "rename", "description:Notes"])
    }

    @Test func cancellationDoesNotShowAnError() async {
        let toast = ToastService()
        let saved = await toast.perform { throw CancellationError() }
        #expect(!saved)
        #expect(toast.current == nil)
    }
}

/// Removing rows sends the server the swiped copies' positions, in one request.
@Suite("PlaylistDetailViewModel — removing rows")
@MainActor
struct PlaylistDetailRemovalTests {
    private static func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Track \(id)", artist: "Artist", albumId: nil,
            albumName: nil, artistId: nil, genre: nil, duration: 180,
            trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private static func makeVM(_ ids: [String], playlist: PDPlaylistStub) -> PlaylistDetailViewModel {
        let state = ServerState()
        state.isOnline = true
        let vm = PlaylistDetailViewModel(playlistId: "playlist-1", libraryService: PDLibraryStub(),
                                         downloadService: PDDownloadStub(), playlistService: playlist,
                                         toastService: ToastService(), serverState: state)
        vm.songs = ids.map(song)
        return vm
    }

    @Test func theSecondCopyOfASongIsTheOneRemoved() async {
        let playlist = PDPlaylistStub()
        let vm = Self.makeVM(["a", "b", "a", "c"], playlist: playlist)
        let positions = PlaylistRowPositions(vm.songs).storedPositions(ofRows: [2])
        await vm.removeTracks(at: positions)
        #expect(playlist.calls == ["remove:[2]"])
        #expect(vm.songs.map(\.id) == ["a", "b", "c"])
    }

    @Test func severalRowsGoInOneRequestHighestFirst() async {
        let playlist = PDPlaylistStub()
        let vm = Self.makeVM(["a", "b", "a", "c", "a"], playlist: playlist)
        await vm.removeTracks(at: [0, 4, 2, 4])
        #expect(playlist.calls == ["remove:[4, 2, 0]"])
        #expect(vm.songs.map(\.id) == ["b", "c"])
    }

    @Test func aFailedRemovalPutsTheSongsBackInPlace() async {
        let playlist = PDPlaylistStub()
        playlist.failsAt = "remove:[3, 1]"
        let vm = Self.makeVM(["a", "b", "a", "c"], playlist: playlist)
        await vm.removeTracks(at: [1, 3])
        #expect(vm.songs.map(\.id) == ["a", "b", "a", "c"])
    }

    @Test func positionsOutsideThePlaylistAreIgnored() async {
        let playlist = PDPlaylistStub()
        let vm = Self.makeVM(["a", "b"], playlist: playlist)
        await vm.removeTracks(at: [5, -1])
        #expect(playlist.calls.isEmpty)
        #expect(vm.songs.count == 2)
    }
}
