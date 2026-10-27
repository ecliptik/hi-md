import Foundation
import OSLog
import SwiftSonic

/// Renames a playlist on the server, with Subsonic's `updatePlaylist` and its `name` parameter.
nonisolated protocol PlaylistRenaming: Sendable {
    func renamePlaylist(id: String, to name: String) async throws
}

extension SwiftSonicClient: PlaylistRenaming {
    func renamePlaylist(id: String, to name: String) async throws {
        try await updatePlaylist(id: id, name: name)
    }
}

/// The one-time rename of the playlists the app keeps on the server, from the names they had
/// when the app was called Minidisc ("Minidisc · Night", "Minidisc Wrapped 2025") to the Hi-MD
/// ones ("Hi-MD · Night", "Hi-MD Wrapped 2025").
///
/// The mood and Wrapped services run it when they list the server's playlists, and record per
/// server that it is done. It only renames:
/// - a playlist whose name is exactly one the app gave it,
/// - owned by the signed-in user (the same rule the mood service uses for its own writes),
/// - when no playlist has the new name yet; if both exist, both stay and the new one is used.
/// A failed rename is logged and tried again on the next listing; it is never fatal.
nonisolated struct PlaylistNameMigration: Sendable {
    nonisolated struct Rename: Sendable, Equatable {
        let playlistId: String
        let from: String
        let to: String
    }

    nonisolated struct Outcome: Sendable {
        /// The listing with the renamed playlists under their new names.
        let playlists: [Playlist]
        /// The playlists that now have their new names.
        let renamed: [Playlist]
        /// Renames the server refused; the migration isn't finished while this is non-zero.
        let failed: Int
    }

    let label: String
    /// The current name for a name the app gave a playlist before; nil for every other name.
    let currentName: @Sendable (String) -> String?

    static let moods = PlaylistNameMigration(label: "moods") { name in
        Mood.allCases.first { $0.legacyPlaylistName == name }?.playlistName
    }

    static let wrapped = PlaylistNameMigration(label: "wrapped") { name in
        WrappedPlaylistService.legacyWrappedYear(fromPlaylistName: name).map(WrappedPlaylistService.playlistName(year:))
    }

    /// Which playlists to rename. Where the user has several playlists with the same old name,
    /// only one is renamed: the one the app already uses (`preferredIDs`), otherwise the lowest id,
    /// the same one the services pick.
    func plan(_ playlists: [Playlist], owner: String?, preferredIDs: Set<String> = []) -> [Rename] {
        let taken = Set(playlists.map(\.name))
        var claimed = Set<String>()
        let candidates = playlists
            .filter { Self.isOwned($0, by: owner) }
            .sorted { lhs, rhs in
                let lhsPreferred = preferredIDs.contains(lhs.id), rhsPreferred = preferredIDs.contains(rhs.id)
                return lhsPreferred != rhsPreferred ? lhsPreferred : lhs.id < rhs.id
            }
        var renames: [Rename] = []
        for playlist in candidates {
            guard let newName = currentName(playlist.name),
                  !taken.contains(newName),
                  claimed.insert(newName).inserted
            else { continue }
            renames.append(Rename(playlistId: playlist.id, from: playlist.name, to: newName))
        }
        return renames
    }

    /// Carries out `renames` one at a time. A failure is logged and counted, and the rest still
    /// run; cancellation stops it.
    func perform(_ renames: [Rename], in playlists: [Playlist], client: any PlaylistRenaming) async throws -> Outcome {
        var listing = playlists
        var renamed: [Playlist] = []
        var failed = 0
        for rename in renames {
            try Task.checkCancellation()
            do {
                try await client.renamePlaylist(id: rename.playlistId, to: rename.to)
            } catch {
                if error is CancellationError { throw CancellationError() }
                try Task.checkCancellation()
                failed += 1
                Logger.playlist.warning("[NAME-MIGRATION] \(label, privacy: .public): could not rename '\(rename.from, privacy: .public)' (\(rename.playlistId, privacy: .public)) — will retry: \(error, privacy: .public)")
                continue
            }
            Logger.playlist.info("[NAME-MIGRATION] \(label, privacy: .public): renamed '\(rename.from, privacy: .public)' to '\(rename.to, privacy: .public)' (\(rename.playlistId, privacy: .public))")
            if let index = listing.firstIndex(where: { $0.id == rename.playlistId }) {
                let updated = listing[index].renamed(rename.to)
                listing[index] = updated
                renamed.append(updated)
            }
        }
        return Outcome(playlists: listing, renamed: renamed, failed: failed)
    }

    /// The mood service's ownership rule: a playlist is the user's unless the server says it
    /// belongs to someone else.
    static func isOwned(_ playlist: Playlist, by owner: String?) -> Bool {
        owner == nil || playlist.owner == nil || playlist.owner == owner
    }
}

extension Playlist {
    /// The same playlist under another name.
    nonisolated func renamed(_ name: String) -> Playlist {
        Playlist(
            id: id, name: name, songCount: songCount, duration: duration, comment: comment, owner: owner,
            isPublic: isPublic, created: created, changed: changed, coverArt: coverArt
        )
    }
}

extension Array where Element == Playlist {
    /// One playlist per key, in the order given: where a key has playlists under both its current
    /// and its legacy name, the current one wins.
    nonisolated func preferringCurrentNames<Key: Hashable>(_ key: (Playlist) -> (key: Key, isLegacy: Bool)?) -> [(playlist: Playlist, key: Key)] {
        var chosen: [Key: (index: Int, isLegacy: Bool)] = [:]
        for (index, playlist) in enumerated() {
            guard let match = key(playlist) else { continue }
            if let existing = chosen[match.key], !(existing.isLegacy && !match.isLegacy) { continue }
            chosen[match.key] = (index, match.isLegacy)
        }
        return chosen.map { (key: $0.key, index: $0.value.index) }
            .sorted { $0.index < $1.index }
            .map { (playlist: self[$0.index], key: $0.key) }
    }
}
