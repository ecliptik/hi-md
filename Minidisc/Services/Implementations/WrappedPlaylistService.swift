import Foundation
import SwiftSonic
import OSLog

// MARK: - PlaylistSyncClient

nonisolated protocol PlaylistSyncClient: Sendable {
    func getPlaylists(username: String?) async throws -> [Playlist]
    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs
}

extension SwiftSonicClient: PlaylistSyncClient {}

// MARK: - WrappedYearlyPlaylist

nonisolated struct WrappedYearlyPlaylist: Sendable, Identifiable {
    let id: String
    let year: Int
    let name: String
    let coverArtId: String?
}

// MARK: - SyncResult

nonisolated enum SyncResult: Sendable, Equatable {
    case upToDate
    case updated(tracksCount: Int)
    case skippedNoData
    case serverError(String)
    case cancelled
}

// MARK: - WrappedPlaylistService

/// Refreshes the annual top-100 playlist monthly using createPlaylist replacement.
actor WrappedPlaylistService {
    nonisolated static let wrappedPlaylistNamePrefix = "Hi-MD Wrapped "
    /// The prefix from before the app was called Hi-MD. Still recognised, and renamed to the
    /// current one once per server by `PlaylistNameMigration`.
    nonisolated static let legacyWrappedPlaylistNamePrefix = "Minidisc Wrapped "

    /// The name the app gives the year's playlist, e.g. "Hi-MD Wrapped 2026".
    nonisolated static func playlistName(year: Int) -> String {
        wrappedPlaylistNamePrefix + String(year)
    }

    /// The year of a Wrapped playlist, under its current or legacy name; nil for any other name.
    nonisolated static func wrappedYear(fromPlaylistName name: String) -> Int? {
        wrappedYear(name, prefix: wrappedPlaylistNamePrefix) ?? legacyWrappedYear(fromPlaylistName: name)
    }

    /// The year of a Wrapped playlist that still has its legacy name.
    nonisolated static func legacyWrappedYear(fromPlaylistName name: String) -> Int? {
        wrappedYear(name, prefix: legacyWrappedPlaylistNamePrefix)
    }

    private nonisolated static func wrappedYear(_ name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }

    /// A client, and who it is signed in as on which server, for the name migration.
    private nonisolated struct ClientContext: Sendable {
        let client: any PlaylistSyncClient
        /// nil when the factory can't tell, as in tests.
        let serverId: String?
        let owner: String?
    }

    private let statsService: StatsService
    private let preferences: WrappedPreferences
    private let makeClientContext: @Sendable () async throws -> ClientContext
    private let serverService: (any ServerServiceProtocol)?
    private let isOnline: @Sendable () async -> Bool
    private let recordRename: (@Sendable (Playlist) async -> Void)?
    private var isMigratingNames = false

    init(
        serverService: any ServerServiceProtocol,
        statsService: StatsService,
        preferences: WrappedPreferences = WrappedPreferences(),
        catalog: LibraryCatalog? = nil
    ) {
        self.statsService = statsService
        self.preferences = preferences
        self.serverService = serverService
        self.makeClientContext = {
            let connection = try await serverService.activeConnection()
            return ClientContext(
                client: connection.makeSwiftSonicClient(),
                serverId: connection.server.id.uuidString,
                owner: connection.server.username
            )
        }
        self.isOnline = { await MainActor.run { serverService.state.isOnline } }
        if let catalog {
            self.recordRename = { summary in await catalog.recordPlaylistMutation(summary: summary, detail: nil) }
        } else {
            self.recordRename = nil
        }
    }

    init(
        clientFactory: @escaping @Sendable () async throws -> any PlaylistSyncClient,
        statsService: StatsService,
        preferences: WrappedPreferences,
        playlistOwner: String? = nil,
        isOnline: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.statsService = statsService
        self.preferences = preferences
        self.serverService = nil
        self.makeClientContext = { ClientContext(client: try await clientFactory(), serverId: nil, owner: playlistOwner) }
        self.isOnline = isOnline
        self.recordRename = nil
    }

    // MARK: - Public API

    /// Replaces the annual "Hi-MD Wrapped <year>" playlist with the top 100
    /// tracks listened to so far this year. Idempotent within a calendar month:
    /// a second call in the same month returns `.upToDate` without a server round-trip.
    func runYearlyPlaylistSyncIfNeeded(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async -> SyncResult {
        do {
            return try await runYearlyPlaylistSyncIfNeededCancellable(
                serverId: serverId,
                calendar: calendar,
                currentDate: currentDate
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .serverError(error.localizedDescription)
        }
    }

    /// Cancellation-preserving entry point used by BackgroundSyncCoordinator.
    /// Completion markers are written only after the final cancellation check.
    func runYearlyPlaylistSyncIfNeededCancellable(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async throws -> SyncResult {
        try Task.checkCancellation()
        let year = calendar.component(.year, from: currentDate)
        let currentYearMonth = YearMonth(year: year, month: calendar.component(.month, from: currentDate))

        if let last = preferences.lastUpdatedMonth(serverId: serverId), last >= currentYearMonth {
            Logger.wrapped.debug("[WRAPPED-SYNC] up-to-date last=\(last, privacy: .public) current=\(currentYearMonth, privacy: .public)")
            return .upToDate
        }

        Logger.wrapped.debug("[WRAPPED-SYNC] start year=\(year, privacy: .public) serverId=\(serverId, privacy: .public)")

        let tracks = await statsService.topTracks(forPeriod: .year(year), serverId: serverId, limit: 100, calendar: calendar)
        try Task.checkCancellation()
        Logger.wrapped.debug("[WRAPPED-SYNC] top tracks count=\(tracks.count, privacy: .public)")

        guard !tracks.isEmpty else {
            try Task.checkCancellation()
            preferences.setLastUpdatedMonth(currentYearMonth, serverId: serverId)
            Logger.wrapped.debug("[WRAPPED-SYNC] no data for year=\(year, privacy: .public) — skipped")
            return .skippedNoData
        }

        let context: ClientContext
        do {
            context = try await makeClientContext()
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.error("[WRAPPED-SYNC] client init failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }
        let client = context.client
        try Task.checkCancellation()

        let pid: String
        do {
            pid = try await getOrCreatePlaylist(for: year, serverId: serverId, context: context)
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.error("[WRAPPED-SYNC] getOrCreatePlaylist failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }
        try Task.checkCancellation()

        let trackIds = tracks.map(\.trackId)
        do {
            try await replacePlaylistTracks(playlistId: pid, trackIds: trackIds, client: client)
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.error("[WRAPPED-SYNC] replace playlist failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }
        try Task.checkCancellation()

        try await uploadWrappedCover(year: year, playlistId: pid)

        try Task.checkCancellation()
        preferences.setLastUpdatedMonth(currentYearMonth, serverId: serverId)
        preferences.setLastWrappedYear(year, serverId: serverId)
        Logger.wrapped.info("[WRAPPED-SYNC] updated year=\(year, privacy: .public) tracks=\(tracks.count, privacy: .public) playlist=\(pid, privacy: .public)")
        return .updated(tracksCount: tracks.count)
    }

    func playlistId(year: Int, serverId: String) -> String? {
        preferences.playlistId(year: year, serverId: serverId)
    }

    /// Checks whether the calendar year has advanced since the last recorded marker.
    /// When it has, clears the monthly idempotence key so the sync runs fresh for
    /// the new year, then updates the year marker. No-op if already current.
    func handleYearTransitionIfNeeded(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async {
        try? await handleYearTransitionIfNeededCancellable(
            serverId: serverId,
            calendar: calendar,
            currentDate: currentDate
        )
    }

    func handleYearTransitionIfNeededCancellable(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async throws {
        try Task.checkCancellation()
        let currentYear = calendar.component(.year, from: currentDate)
        if let last = preferences.lastWrappedYear(serverId: serverId), last >= currentYear { return }
        try Task.checkCancellation()
        preferences.clearLastUpdatedMonth(serverId: serverId)
        preferences.setLastWrappedYear(currentYear, serverId: serverId)
        Logger.wrapped.info("Year marker → \(currentYear, privacy: .public) (serverId=\(serverId, privacy: .public))")
    }

    func fetchYearlyPlaylists(
        serverId: String,
        calendar: Calendar = .current,
        currentDate: Date = Date()
    ) async -> [WrappedYearlyPlaylist] {
        let context: ClientContext
        do {
            context = try await makeClientContext()
        } catch {
            Logger.wrapped.error("[WRAPPED] fetchYearlyPlaylists client init failed: \(error, privacy: .public)")
            return []
        }
        do {
            var all = try await context.client.getPlaylists(username: nil)
            all = try await migrateNamesIfNeeded(all, serverId: serverId, context: context)
            // Clear stale identity and cadence markers so a deleted playlist can be recreated.
            reconcileCurrentYearPlaylist(serverId: serverId, livePlaylists: all, calendar: calendar, currentDate: currentDate)
            return WrappedYearlyPlaylist.saved(in: all).sorted { $0.year > $1.year }
        } catch {
            Logger.wrapped.error("[WRAPPED] fetchYearlyPlaylists failed: \(error, privacy: .public)")
            return []
        }
    }

    // MARK: - Name migration

    /// Renames this server's Wrapped playlists from "Minidisc Wrapped 2025" to "Hi-MD Wrapped 2025",
    /// once. Only while online, only on the server the client is signed in to, only the user's own
    /// playlists, and only where no playlist has the new name yet (see `PlaylistNameMigration`).
    /// Returns the listing with the new names; a failed rename is tried again on the next listing.
    private func migrateNamesIfNeeded(_ playlists: [Playlist], serverId: String, context: ClientContext) async throws -> [Playlist] {
        guard !isMigratingNames,
              !preferences.hasMigratedPlaylistNames(serverId: serverId),
              context.serverId == nil || context.serverId == serverId,
              let renamer = context.client as? any PlaylistRenaming,
              await isOnline()
        else { return playlists }
        // Checked again: the actor may have run another listing while `isOnline` was awaited.
        guard !isMigratingNames, !preferences.hasMigratedPlaylistNames(serverId: serverId) else { return playlists }
        isMigratingNames = true
        defer { isMigratingNames = false }
        try Task.checkCancellation()
        let migration = PlaylistNameMigration.wrapped
        let inUse = Set(playlists.compactMap { playlist in
            WrappedPlaylistService.wrappedYear(fromPlaylistName: playlist.name)
                .flatMap { preferences.playlistId(year: $0, serverId: serverId) }
        })
        let renames = migration.plan(playlists, owner: context.owner, preferredIDs: inUse)
        let outcome = try await migration.perform(renames, in: playlists, client: renamer)
        for playlist in outcome.renamed {
            await recordRename?(playlist)
        }
        try Task.checkCancellation()
        if outcome.failed == 0 {
            preferences.setMigratedPlaylistNames(serverId: serverId)
            Logger.wrapped.info("[NAME-MIGRATION] wrapped done for \(serverId, privacy: .public): renamed \(outcome.renamed.count, privacy: .public)")
        }
        return outcome.playlists
    }

    // MARK: - Replace playlist tracks

    private func replacePlaylistTracks(
        playlistId: String,
        trackIds: [String],
        client: any PlaylistSyncClient
    ) async throws {
        _ = try await client.createPlaylist(name: nil, playlistId: playlistId, songIds: trackIds)
        Logger.wrapped.debug("[WRAPPED-SYNC] replaced playlist=\(playlistId, privacy: .public) with \(trackIds.count, privacy: .public) tracks")
    }

    // MARK: - Cover art upload

    private func uploadWrappedCover(year: Int, playlistId: String) async throws {
        try Task.checkCancellation()
        guard let serverService else { return }
        let snapshot = await MainActor.run { serverService.state.activeServer }
        try Task.checkCancellation()
        guard let snapshot, let baseURL = URL(string: snapshot.baseURL) else { return }

        let jpegData = await MainActor.run {
            WrappedCoverRenderer.generateCoverData(year: year)
        }
        try Task.checkCancellation()
        guard let jpegData else {
            Logger.wrapped.warning("[WRAPPED] Cover generation failed for \(year, privacy: .public)")
            return
        }

        do {
            let connection = try await serverService.activeConnection()
            let api = NavidromeNativeAPI(
                transport: CustomHeadersTransport(headers: connection.credentials.customHeaders)
            )
            let token = try await api.authenticate(
                baseURL: baseURL,
                username: snapshot.username,
                password: connection.credentials.password
            )
            try await api.uploadPlaylistCover(
                baseURL: baseURL,
                token: token,
                playlistId: playlistId,
                imageData: jpegData,
                mimeType: "image/jpeg"
            )
            try Task.checkCancellation()
            Logger.wrapped.info("[WRAPPED] Cover uploaded for \(year, privacy: .public) playlist")
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.warning("[WRAPPED] Cover upload failed — \(error, privacy: .public)")
        }
    }

    /// Invalidates the current-year sync markers when its cached playlist is absent from the server.
    private func reconcileCurrentYearPlaylist(
        serverId: String,
        livePlaylists: [Playlist],
        calendar: Calendar,
        currentDate: Date
    ) {
        let year = calendar.component(.year, from: currentDate)
        guard let cached = preferences.playlistId(year: year, serverId: serverId) else { return }
        guard !livePlaylists.contains(where: { $0.id == cached }) else { return }
        preferences.clearPlaylistId(year: year, serverId: serverId)
        preferences.clearLastUpdatedMonth(serverId: serverId)
        Logger.wrapped.info("[WRAPPED] \(year, privacy: .public) playlist \(cached, privacy: .public) gone from server — cleared markers so it rebuilds next launch")
    }

    // MARK: - Get-or-create annual playlist

    private func getOrCreatePlaylist(for year: Int, serverId: String, context: ClientContext) async throws -> String {
        try Task.checkCancellation()
        let client = context.client
        let name = WrappedPlaylistService.playlistName(year: year)
        // Validate cached IDs against the live list before replacing playlist contents.
        var playlists = try await client.getPlaylists(username: nil)
        try Task.checkCancellation()
        playlists = try await migrateNamesIfNeeded(playlists, serverId: serverId, context: context)
        try Task.checkCancellation()

        // A playlist with the Hi-MD name wins over the cached one, which may be a Minidisc-named
        // playlist that couldn't be renamed because both exist.
        let current = playlists.first { $0.name == name }
        if let cached = preferences.playlistId(year: year, serverId: serverId),
           playlists.contains(where: { $0.id == cached }),
           current == nil || current?.id == cached {
            return cached
        }

        let legacyName = WrappedPlaylistService.legacyWrappedPlaylistNamePrefix + String(year)
        if let existing = current ?? playlists.first(where: { $0.name == legacyName }) {
            preferences.setPlaylistId(existing.id, year: year, serverId: serverId)
            Logger.wrapped.info("Found '\(existing.name, privacy: .public)' id=\(existing.id, privacy: .public)")
            return existing.id
        }

        let created = try await client.createPlaylist(name: name, playlistId: nil, songIds: [])
        try Task.checkCancellation()
        preferences.setPlaylistId(created.id, year: year, serverId: serverId)
        Logger.wrapped.info("Created '\(name, privacy: .public)' id=\(created.id, privacy: .public) (serverId=\(serverId, privacy: .public))")
        return created.id
    }
}
