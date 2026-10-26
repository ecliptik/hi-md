import Observation
import SwiftSonic
import SwiftUI

/// The sidebar's playlists and the requests that need a sheet or a confirmation: naming a new
/// playlist, renaming, deleting, and adding songs that are already in the playlist. The main window
/// presents them, so a context menu anywhere can start one.
@Observable
@MainActor
final class MacPlaylists {
    struct Creation: Identifiable {
        let id = UUID()
        var songs: [DisplayableSong]
    }

    /// Songs that are partly in the playlist already, waiting for Add Anyway or Add Only New Songs.
    struct PendingDuplicate: Identifiable {
        let id = UUID()
        let playlist: Playlist
        fileprivate let model: AddToPlaylistViewModel
    }

    let library: PlaylistLibraryViewModel
    var creation: Creation?
    var renaming: Playlist?
    var deleting: Playlist?
    var pendingDuplicate: PendingDuplicate?

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        library = PlaylistLibraryViewModel(playlistService: container.playlistService,
                                           toastService: container.toastService)
    }

    var playlists: [Playlist] { library.playlists }
    var canEdit: Bool { container.serverState.isOnline }

    func playlist(id: String) -> Playlist? {
        library.playlists.first { $0.id == id }
    }

    func requestNewPlaylist(with songs: [DisplayableSong] = []) {
        creation = Creation(songs: songs.filter { !$0.isLocalFile })
    }

    /// Adds songs to a playlist, asking first when some of them are already there.
    func add(_ songs: [DisplayableSong], to playlist: Playlist) {
        let songs = songs.filter { !$0.isLocalFile }
        guard !songs.isEmpty else { return }
        let model = AddToPlaylistViewModel(
            songs: songs, playlistService: container.playlistService, toastService: container.toastService,
            recents: RecentPlaylistDestinations(serverID: container.serverState.activeServer?.id.uuidString ?? "")
        )
        Task {
            if await model.checkAndAdd(to: playlist) == .duplicate {
                pendingDuplicate = PendingDuplicate(playlist: playlist, model: model)
            } else if let error = model.error {
                container.toastService.showError(error.displayMessage)
            }
        }
    }

    func resolveDuplicate(_ pending: PendingDuplicate, skippingDuplicates: Bool) {
        pendingDuplicate = nil
        Task {
            if !(await pending.model.forceAdd(to: pending.playlist, skippingDuplicates: skippingDuplicates)),
               let error = pending.model.error {
                container.toastService.showError(error.displayMessage)
            }
        }
    }
}
