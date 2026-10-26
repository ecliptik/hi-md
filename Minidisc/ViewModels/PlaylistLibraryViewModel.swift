import Foundation
import OSLog
import SwiftSonic

/// The user's playlists with create, rename and delete, for the Mac app's sidebar. Each change goes
/// to the server first; the list updates only after the server confirms it.
@Observable
@MainActor
final class PlaylistLibraryViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var error: UserFacingError?

    private let playlistService: any PlaylistServiceProtocol
    private let toastService: ToastService

    init(playlistService: any PlaylistServiceProtocol, toastService: ToastService) {
        self.playlistService = playlistService
        self.toastService = toastService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            playlists = try await playlistService.listPlaylists()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            error = nil
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            self.error = UserFacingError.from(error)
        }
    }

    static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Creates the playlist, then adds `songs` to it. Returns the new playlist, or nil if the
    /// server refused it. A failed add keeps the new, empty playlist and reports the error.
    func create(name: String, songs: [DisplayableSong] = []) async -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let created: PlaylistWithSongs
        do {
            created = try await playlistService.createPlaylist(name: trimmed, description: nil)
        } catch {
            Logger.playlist.error("Failed to create playlist: \(error, privacy: .public)")
            toastService.showError(String(localized: "Failed to create playlist. Try again."))
            return nil
        }
        let summary = Playlist(id: created.id, name: created.name, songCount: created.songCount,
                               duration: created.duration, comment: created.comment, owner: created.owner,
                               isPublic: created.isPublic, created: created.created,
                               changed: created.changed, coverArt: created.coverArt)
        let added = songs.filter { !$0.isLocalFile }
        if !added.isEmpty {
            do {
                try await playlistService.addTracks(playlistId: created.id, songs: added.map { $0.asSong() })
            } catch {
                Logger.playlist.error("Failed to add songs to a new playlist: \(error, privacy: .public)")
                toastService.showError(String(localized: "Failed to add songs to the playlist."))
            }
        }
        await load()
        if !playlists.contains(where: { $0.id == summary.id }) { insertSorted(summary) }
        toastService.showSuccess(String(localized: "Playlist created"))
        return playlists.first { $0.id == summary.id } ?? summary
    }

    /// Returns false when the server refused the new name; the old name stays.
    @discardableResult
    func rename(_ playlist: Playlist, to name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed != playlist.name else { return true }
        do {
            try await playlistService.renamePlaylist(id: playlist.id, newName: trimmed)
        } catch {
            Logger.playlist.error("Failed to rename playlist \(playlist.id, privacy: .public): \(error, privacy: .public)")
            toastService.showError(String(localized: "Couldn't rename the playlist. Please try again."))
            return false
        }
        await load()
        return true
    }

    /// `purgeDownloads` also removes the playlist's downloaded files from this computer.
    @discardableResult
    func delete(_ playlist: Playlist, purgeDownloads: Bool) async -> Bool {
        do {
            try await playlistService.deletePlaylist(id: playlist.id, purgeDownloads: purgeDownloads)
        } catch {
            Logger.playlist.error("[PLAYLIST] delete failed id=\(playlist.id, privacy: .public): \(error, privacy: .public)")
            toastService.showError(String(localized: "Couldn't delete playlist. Please try again."))
            return false
        }
        playlists.removeAll { $0.id == playlist.id }
        postPlaylistDeleted()
        toastService.showConfirmation(String(localized: "Playlist deleted"))
        return true
    }

    private func insertSorted(_ playlist: Playlist) {
        let index = playlists.firstIndex {
            playlist.name.localizedStandardCompare($0.name) == .orderedAscending
        } ?? playlists.endIndex
        playlists.insert(playlist, at: index)
    }
}
