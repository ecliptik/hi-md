import AppIntents
import CoreSpotlight
import CryptoKit
import Foundation
import Observation
import OSLog
import SwiftSonic

/// Indexes the active server's artists, albums and playlists in Spotlight from the local library
/// index, so it works offline and never asks the server for anything.
///
/// The index is rebuilt only when that set changes, which a fingerprint of the indexed names
/// detects, and is replaced when the active server changes.
@MainActor
final class SpotlightIndexer {
    private static let fingerprintKey = "spotlight.indexFingerprint"
    private nonisolated static let batchSize = 500

    private let serverState: ServerState
    private let store: LibraryIndexStore
    private let defaults: UserDefaults
    private var pending: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []

    init(serverState: ServerState, store: LibraryIndexStore, defaults: UserDefaults) {
        self.serverState = serverState
        self.store = store
        self.defaults = defaults
    }

    func start() {
        guard tasks.isEmpty else { return }
        let serverState = serverState
        tasks.append(Task { [weak self] in
            for await _ in Observations({ serverState.activeServer?.id }) { self?.setNeedsIndex() }
        })
        tasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .minidiscPlaylistsChanged) {
                self?.setNeedsIndex()
            }
        })
    }

    /// Called after library syncs and when the app goes to the background.
    func setNeedsIndex() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await self?.update()
        }
    }

    func update() async {
        do {
            guard let server = serverState.activeServer else {
                try await removeAll()
                return
            }
            let scope = MusicIntentID.scope(baseURL: server.baseURL, username: server.username)
            let artists = try await store.artists(serverID: server.id).flatMap(\.artist)
                .map { MusicIntentRecord(scope: scope, artist: $0) }
            let albums = try await store.albums(serverID: server.id).map { MusicIntentRecord(scope: scope, album: $0) }
            let playlists = try await store.playlists(serverID: server.id).map { MusicIntentRecord(scope: scope, playlist: $0) }
            try Task.checkCancellation()
            guard serverState.activeServer?.id == server.id else { return }

            let fingerprint = Self.fingerprint(of: artists + albums + playlists)
            guard fingerprint != defaults.string(forKey: Self.fingerprintKey) else { return }
            try await removeAll()
            try await Self.index(artists.map(SiriArtistEntity.init))
            try await Self.index(albums.map(SiriAlbumEntity.init))
            try await Self.index(playlists.map(SiriPlaylistEntity.init))
            defaults.set(fingerprint, forKey: Self.fingerprintKey)
            Logger.ui.info("Spotlight indexed \(artists.count) artists, \(albums.count) albums, \(playlists.count) playlists")
        } catch is CancellationError {
        } catch {
            Logger.ui.debug("Spotlight indexing failed: \(error, privacy: .public)")
        }
    }

    private func removeAll() async throws {
        defaults.removeObject(forKey: Self.fingerprintKey)
        try await Self.deleteAll()
    }

    // CSSearchableIndex is not Sendable, so each call uses the shared index off the main actor
    // instead of keeping one in the indexer's state.

    @concurrent
    private nonisolated static func index<Entity: IndexedEntity>(_ entities: [Entity]) async throws {
        let index = CSSearchableIndex.default()
        for start in stride(from: 0, to: entities.count, by: batchSize) {
            try Task.checkCancellation()
            try await index.indexAppEntities(Array(entities[start..<min(start + batchSize, entities.count)]))
        }
    }

    @concurrent
    private nonisolated static func deleteAll() async throws {
        let index = CSSearchableIndex.default()
        try await index.deleteAppEntities(ofType: SiriArtistEntity.self)
        try await index.deleteAppEntities(ofType: SiriAlbumEntity.self)
        try await index.deleteAppEntities(ofType: SiriPlaylistEntity.self)
    }

    /// Changes when any indexed item is added, removed or renamed, or the account changes.
    nonisolated static func fingerprint(of records: [MusicIntentRecord]) -> String {
        var hasher = SHA256()
        for record in records {
            hasher.update(data: Data((record.id + "\u{1F}" + record.title + "\u{1F}" + record.subtitle + "\n").utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
