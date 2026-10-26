import Observation
import OSLog
import SwiftSonic
import SwiftUI

/// The Mac app's playback actions, shared by the player bar, the menus, the menu bar player and
/// every song list, so they behave alike. Playback itself stays in the shared PlayerService.
@Observable
@MainActor
final class MacPlayback {
    let container: AppContainer
    /// The app's own volume, applied on top of the system volume. Saved by the player.
    private(set) var volume: Float

    private var player: any PlayerServiceProtocol { container.playerService }
    var state: PlayerState { container.playerState }
    var commands: PlaybackCommandState { PlaybackCommandState(playerState: state) }

    init(container: AppContainer) {
        self.container = container
        let restored = container.playbackPreferences.restoredVolume
        volume = restored
        // The engine starts at full volume; bring it to the volume the slider shows.
        Task { await container.playerService.setVolume(restored) }
    }

    // MARK: - Transport

    func togglePlayPause() {
        Task { await player.togglePlayPause() }
    }

    func skipToNext() {
        Task { await container.toastService.perform { try await self.player.skipToNext() } }
    }

    func skipToPrevious() {
        Task { await container.toastService.perform { try await self.player.skipToPrevious() } }
    }

    /// Seeks, moving the lyrics to `position` at once rather than when the player gets there.
    func seek(to position: TimeInterval) async {
        state.noteSeek(to: position)
        await player.seek(to: position)
    }

    /// A scrubber is being dragged: the lyrics follow it before the seek.
    func scrub(to position: TimeInterval) {
        state.noteScrub(to: position)
    }

    func cancelScrub() {
        state.cancelScrub()
    }

    func toggleShuffle() {
        Task { await player.toggleShuffle() }
    }

    func setRepeatMode(_ mode: RepeatMode) {
        Task { await player.setRepeatMode(mode) }
    }

    func cycleRepeatMode() {
        setRepeatMode(state.repeatMode.next)
    }

    func setVolume(_ newValue: Float) {
        volume = min(1, max(0, newValue))
        let level = volume
        Task { await player.setVolume(level) }
    }

    func changeVolume(steps: Int) {
        setVolume(PlaybackVolume.adjusted(volume, steps: steps))
    }

    // MARK: - Queueing songs

    /// Starts `songs` at `index`, replacing the queue. `context` is where they came from, for
    /// "Playing from"; without one the new queue has none.
    func play(_ songs: [DisplayableSong], from index: Int = 0, context: PlaybackContext? = nil) {
        guard songs.indices.contains(index) else { return }
        Task {
            await container.toastService.perform {
                try await self.player.play(tracks: songs, startIndex: index, context: context)
            }
        }
    }

    /// Loads a playlist's songs, then plays or shuffles them, playing from that playlist (or its
    /// mood or Wrapped year).
    func playPlaylist(id playlistID: String, shuffled: Bool = false) {
        Task {
            let playlist: PlaylistWithSongs
            do {
                playlist = try await container.playlistService.getPlaylist(id: playlistID)
            } catch {
                guard !UserFacingError.isCancellation(error) else { return }
                container.toastService.showError(UserFacingError.from(error).displayMessage)
                return
            }
            let songs = playlist.entry?.map { DisplayableSong(from: $0) } ?? []
            let context = PlaybackContext.forPlaylist(id: playlistID, name: playlist.name, coverArtId: playlist.coverArt)
            play(shuffled ? songs.shuffled() : songs, context: context)
        }
    }

    /// An Instant Mix of songs like this one.
    func playInstantMix(from song: DisplayableSong) {
        startInstantMix(from: .song(id: song.id), using: container, startingWith: song, context: songMixContext(song))
    }

    /// An Instant Mix of songs like this album's.
    func playInstantMix(albumID: String, name: String) {
        startInstantMix(from: .album(id: albumID), using: container,
                        context: .instantMix(seed: .album, id: albumID, name: name))
    }

    /// An artist and similar artists, from Discover's Stations for You.
    func playStation(_ station: ArtistStation) async {
        await container.toastService.perform {
            try await self.player.playInstantMix(
                from: .artist(id: station.id),
                startingWith: station.starter,
                context: .artistStation(artistId: station.id, artistName: station.artist.name)
            )
        }
    }

    /// Rediscover Your Library: a new mix from the whole library, or offline from the downloads.
    func playSmartShuffle() async {
        do {
            try await player.playSmartShuffle()
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            if case MinidiscError.smartShuffleEmpty = error {
                container.toastService.showError(String(localized: "Smart Shuffle unavailable — try playing some tracks first or download more music for offline use."))
            } else {
                container.toastService.showError(String(localized: "Smart Shuffle failed. Please try again."))
            }
        }
    }

    func playRadio(_ station: InternetRadioStation) {
        Task {
            do {
                try await player.playRadio(station)
            } catch {
                guard !UserFacingError.isCancellation(error) else { return }
                container.toastService.showError(String(localized: "Unable to play this radio station."))
                Logger.player.error("[RADIO] play failed: \(error, privacy: .public)")
            }
        }
    }

    func shuffle(_ songs: [DisplayableSong]) {
        play(songs.shuffled())
    }

    func playNext(_ songs: [DisplayableSong]) {
        guard !songs.isEmpty else { return }
        Task { await player.playNext(songs) }
    }

    func addToQueue(_ songs: [DisplayableSong]) {
        guard !songs.isEmpty else { return }
        Task { await player.addToQueue(songs) }
    }

    /// Loads an album's songs, then plays, shuffles or queues them.
    func playAlbum(id albumID: String, action: CollectionAction = .play) {
        Task {
            let model = AlbumDetailViewModel(
                albumId: albumID,
                libraryService: container.libraryService,
                downloadService: container.downloadService,
                toastService: container.toastService,
                serverState: container.serverState,
                offlineFavorites: container.offlineFavoritesStore
            )
            await model.load()
            perform(action, on: model.songs)
        }
    }

    /// Loads every song by an artist, then plays, shuffles or queues them.
    func playArtist(id artistID: String, action: CollectionAction = .play) {
        Task {
            do {
                let songs = try await container.libraryService.fetchAllTracks(forArtistID: artistID)
                perform(action, on: songs)
            } catch {
                guard !UserFacingError.isCancellation(error) else { return }
                container.toastService.showError(UserFacingError.from(error).displayMessage)
            }
        }
    }

    enum CollectionAction {
        case play, shuffle, playNext, addToQueue
    }

    func perform(_ action: CollectionAction, on songs: [DisplayableSong]) {
        switch action {
        case .play: play(songs)
        case .shuffle: shuffle(songs)
        case .playNext: playNext(songs)
        case .addToQueue: addToQueue(songs)
        }
    }

    // MARK: - Favourites and downloads

    /// Stars or unstars a song on the server.
    func setFavorite(_ isFavorite: Bool, songs: [DisplayableSong]) {
        let ids = songs.filter { !$0.isLocalFile }.map(\.id)
        guard !ids.isEmpty else { return }
        Task {
            await container.toastService.perform {
                for id in ids {
                    if isFavorite {
                        try await self.container.favoritesService.star(itemType: .song, itemId: id)
                    } else {
                        try await self.container.favoritesService.unstar(itemType: .song, itemId: id)
                    }
                }
            }
        }
    }

    func setFavorite(_ isFavorite: Bool, itemType: FavoriteType, id: String) {
        Task {
            await container.toastService.perform {
                if isFavorite {
                    try await self.container.favoritesService.star(itemType: itemType, itemId: id)
                } else {
                    try await self.container.favoritesService.unstar(itemType: itemType, itemId: id)
                }
            }
        }
    }

    /// Saves songs to this Mac for offline listening.
    func download(_ songs: [DisplayableSong]) {
        guard let serverID = container.serverState.activeServer?.id else { return }
        let wanted = songs.filter { !$0.isDownloaded && !$0.isLocalFile }
        guard !wanted.isEmpty else { return }
        Task {
            let succeeded = await container.toastService.perform {
                for song in wanted {
                    try await self.container.downloadService.download(song: song.asSong(), serverId: serverID)
                }
            }
            if succeeded { showDownloadStarted(count: wanted.count) }
        }
    }

    func downloadAlbum(id albumID: String) {
        guard let serverID = container.serverState.activeServer?.id else { return }
        Task {
            let succeeded = await container.toastService.perform {
                let album = try await self.container.libraryService.album(id: albumID)
                try await self.container.downloadService.download(album: album, serverId: serverID)
            }
            if succeeded { showDownloadStarted(count: nil) }
        }
    }

    func downloadPlaylist(id playlistID: String) {
        guard let serverID = container.serverState.activeServer?.id else { return }
        Task {
            let succeeded = await container.toastService.perform {
                let playlist = try await self.container.playlistService.getPlaylist(id: playlistID)
                try await self.container.downloadService.download(playlist: playlist, serverId: serverID)
            }
            if succeeded { showDownloadStarted(count: nil) }
        }
    }

    private func showDownloadStarted(count: Int?) {
        let message = count.map { String(localized: "Downloading \($0) songs") } ?? String(localized: "Downloading")
        container.toastService.showConfirmation(message, action: .navigateToDownloads)
    }

    // MARK: - Queue

    /// Removes songs from Up Next. One song can be put back with Undo in the toast.
    func removeFromQueue(_ selections: [QueueTrackSelection]) {
        guard selections.count > 1 else {
            guard let selection = selections.first else { return }
            Task {
                guard let removal = await player.removeQueueTrack(selection) else { return }
                container.toastService.show(String(localized: "Removed from queue"), subtitle: removal.song.title,
                                            style: .success, duration: 6, coverArtId: removal.song.coverArtId,
                                            action: .undoQueueRemoval(removal))
            }
            return
        }
        // Each removal changes the queue, so every later request is captured again. Going from the
        // end keeps the earlier positions where they were.
        let targets = selections.sorted { $0.destinationIndex > $1.destinationIndex }
        Task {
            for target in targets {
                guard let fresh = QueueTrackSelection(playerState: state, destinationIndex: target.destinationIndex,
                                                      destinationTrackID: target.destinationTrackID) else { continue }
                _ = await player.removeQueueTrack(fresh)
            }
        }
    }

    func moveInQueue(_ selection: QueueTrackSelection, to index: Int) {
        Task { await player.moveQueueTrack(selection, toIndex: index) }
    }

    func jump(to selection: QueueTrackSelection) {
        Task { await container.toastService.perform { _ = try await self.player.selectQueueTrack(selection) } }
    }

    func clearUpNext() {
        Task { await UpNextClearing.clear(player: player, state: state) }
    }
}
