import Foundation
import Observation
import SwiftData

/// Hearts for Winamp mode: whether the playing song is a favourite, for the main window's heart and
/// View > Winamp, and starring the playlist's selected songs. Only songs are starred, through the
/// app's FavoritesService, so the server passes them on to Last.fm, ListenBrainz and Apple Music.
///
/// The state comes from the same `FavoriteRecord` store every other heart reads. It's read again
/// when the song or the connection changes and whenever the store is saved, which covers stars
/// made anywhere in the app, a failed star being put back, and a sync from the server.
@Observable
final class WinampFavoritesModel {
    private(set) var current: WinampFavoriteStatus = .unavailable

    @ObservationIgnored private var container: AppContainer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var watchGeneration = 0

    func attach(_ container: AppContainer) {
        guard self.container !== container else { return }
        self.container = container
        if observers.isEmpty {
            for name in [ModelContext.didSave, .minidiscFavoritesChanged] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                })
            }
        }
        watchPlayer()
    }

    // MARK: State

    func isFavorite(songID: String) -> Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: songID) ?? false
    }

    /// Reads the playing song and the connection under observation, so either changing reads the
    /// heart again.
    private func watchPlayer() {
        guard container != nil else { return }
        watchGeneration += 1
        let generation = watchGeneration
        let status = withObservationTracking {
            readStatus()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                // A newer attach started its own watch; this one stops.
                guard let self, self.watchGeneration == generation else { return }
                self.watchPlayer()
            }
        }
        set(status)
    }

    private func update() {
        set(readStatus())
    }

    private func set(_ status: WinampFavoriteStatus) {
        if status != current { current = status }
    }

    private func readStatus() -> WinampFavoriteStatus {
        guard let container else { return .unavailable }
        let player = container.playerState
        let track = player.currentTrack
        return WinampFavoriteStatus.current(
            songID: track?.id, isLocalFile: track?.isLocalFile == true, isRadio: player.currentRadio != nil,
            isOnline: container.serverState.isOnline, isFavorite: isFavorite(songID:)
        )
    }

    // MARK: Actions

    /// The heart, the main window's menu and View > Winamp: stars the playing song, or unstars it.
    func toggleCurrent() {
        guard current.canToggle, let songID = current.songID else { return }
        let star = !current.isFavorite
        // Shown straight away; the store's save confirms it, or puts it back if the server refuses.
        current.isFavorite = star
        apply(star ? .star([songID]) : .unstar([songID]))
    }

    /// The playlist's selected songs: all unstarred if every one is a favourite already,
    /// otherwise the rest are starred.
    func action(for songs: [DisplayableSong]) -> WinampFavoriteSelection.Action? {
        WinampFavoriteSelection.action(
            for: songs.map { WinampFavoriteSelection.Song(id: $0.id, isLocalFile: $0.isLocalFile) },
            isFavorite: isFavorite(songID:)
        )
    }

    var canChange: Bool { container?.serverState.isOnline == true }

    func apply(_ action: WinampFavoriteSelection.Action) {
        guard let container else { return }
        let service = container.favoritesService
        let toasts = container.toastService
        Task { [weak self] in
            await toasts.perform {
                switch action {
                case .star(let ids):
                    for id in ids { try await service.star(itemType: .song, itemId: id) }
                case .unstar(let ids):
                    for id in ids { try await service.unstar(itemType: .song, itemId: id) }
                }
            }
            self?.update()
        }
    }
}
