import Foundation
import SwiftData
import SwiftSonic
import OSLog

actor FavoritesService: FavoritesServiceProtocol {
    private let libraryService: any FavoriteEditing
    private nonisolated let serverState: ServerState
    nonisolated let modelContainer: ModelContainer
    private lazy var backgroundContext: ModelContext = ModelContext(modelContainer)
    /// Stars and unstars on their way to the server, and when the last one finished: a starred
    /// list requested before then may not have it yet, so it mustn't overwrite the local hearts.
    private var editsInFlight = 0
    private var lastEditFinished = Date.distantPast
    /// Changes made while the server was out of reach, sent when it's back.
    private let outbox: FavoriteOutbox

    init(libraryService: any FavoriteEditing, serverState: ServerState, modelContainer: ModelContainer,
         outbox: FavoriteOutbox = FavoriteOutbox(directory: URL.temporaryDirectory.appendingPathComponent("favorites-\(UUID())"))) {
        self.libraryService = libraryService
        self.serverState = serverState
        self.modelContainer = modelContainer
        self.outbox = outbox
    }

    // MARK: - Query

    @MainActor
    func isFavorite(itemType: FavoriteType, itemId: String) -> Bool {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<FavoriteRecord>(
            predicate: #Predicate<FavoriteRecord> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContainer.mainContext.fetchCount(descriptor)) ?? 0 > 0
    }

    // MARK: - Star and unstar

    func star(itemType: FavoriteType, itemId: String) async throws {
        try await setFavorite(true, itemType: itemType, itemId: itemId)
    }

    func unstar(itemType: FavoriteType, itemId: String) async throws {
        try await setFavorite(false, itemType: itemType, itemId: itemId)
    }

    /// The heart changes at once. Offline, or when the server can't be reached, the change waits
    /// in the outbox and goes out with the next sync; a server that refuses it puts the heart back.
    private func setFavorite(_ starred: Bool, itemType: FavoriteType, itemId: String) async throws {
        guard let serverId = await MainActor.run(body: { serverState.activeServer?.id }) else { throw MinidiscError.serverNotConfigured }
        let compositeId = FavoriteToggle.recordID(itemType, id: itemId)
        var descriptor = FetchDescriptor<FavoriteRecord>(predicate: #Predicate<FavoriteRecord> { $0.id == compositeId })
        descriptor.fetchLimit = 1
        let existing = try backgroundContext.fetch(descriptor).first
        if !starred, existing == nil { return }
        beginEdit()
        defer { endEdit() }

        let previousDate = existing?.starredDate
        if starred {
            if existing == nil {
                backgroundContext.insert(FavoriteRecord(itemType: itemType, itemId: itemId, starredDate: Date(), serverId: serverId))
            }
        } else if let existing {
            backgroundContext.delete(existing)
        }
        try saveChanges()

        let change = FavoriteOutbox.Change(serverID: serverId, itemType: itemType.rawValue, itemID: itemId, starred: starred, date: Date())
        guard await MainActor.run(body: { serverState.isOnline }) else {
            await queue(change)
            return
        }
        do {
            try await send(starred, itemType: itemType, ids: [itemId])
            // A change queued earlier for the item is now out of date.
            await outbox.discard(recordID: compositeId, serverID: serverId)
            Logger.favorites.info("\(starred ? "Starred" : "Unstarred", privacy: .public) \(itemType.rawValue, privacy: .public) \(itemId, privacy: .public)")
        } catch where Self.isUnreachable(error) {
            await queue(change)
        } catch {
            if starred {
                if existing == nil, let added = try backgroundContext.fetch(descriptor).first { backgroundContext.delete(added) }
            } else {
                backgroundContext.insert(FavoriteRecord(itemType: itemType, itemId: itemId,
                                                        starredDate: previousDate ?? Date(), serverId: serverId))
            }
            try saveChanges()
            throw error
        }
    }

    private func queue(_ change: FavoriteOutbox.Change) async {
        await outbox.record(change)
        Logger.favorites.info("Queued \(change.starred ? "star" : "unstar", privacy: .public) of \(change.recordID, privacy: .public) until the server is back")
        await MainActor.run { NotificationCenter.default.post(name: .minidiscFavoritesChanged, object: nil) }
    }

    private func send(_ starred: Bool, itemType: FavoriteType, ids: [String]) async throws {
        let songs = itemType == .song ? ids : [], albums = itemType == .album ? ids : [], artists = itemType == .artist ? ids : []
        if starred { try await libraryService.star(songIds: songs, albumIds: albums, artistIds: artists) }
        else { try await libraryService.unstar(songIds: songs, albumIds: albums, artistIds: artists) }
    }

    /// Sends what was starred and unstarred while offline, a batch of each. A batch the server
    /// can't be reached for waits for the next try; one it refuses, such as a song deleted since,
    /// is dropped rather than retried forever.
    func flushPending() async {
        guard await MainActor.run(body: { serverState.isOnline }),
              let serverId = await MainActor.run(body: { serverState.activeServer?.id }) else { return }
        let pending = await outbox.pending(serverID: serverId)
        guard !pending.isEmpty else { return }
        for starred in [true, false] {
            let batch = pending.filter { $0.starred == starred }
            guard !batch.isEmpty else { continue }
            func ids(_ type: FavoriteType) -> [String] { batch.filter { $0.itemType == type.rawValue }.map(\.itemID) }
            do {
                if starred { try await libraryService.star(songIds: ids(.song), albumIds: ids(.album), artistIds: ids(.artist)) }
                else { try await libraryService.unstar(songIds: ids(.song), albumIds: ids(.album), artistIds: ids(.artist)) }
                await outbox.remove(batch)
                Logger.favorites.info("Sent \(batch.count) queued \(starred ? "stars" : "unstars", privacy: .public)")
            } catch where Self.isUnreachable(error) {
                return
            } catch {
                Logger.favorites.error("The server refused \(batch.count) queued favourite changes: \(error, privacy: .public)")
                await outbox.remove(batch)
            }
        }
    }

    /// No network, or the server didn't answer or is down: worth trying again later. An answer
    /// that refuses the change, such as a Subsonic API error, is not.
    nonisolated static func isUnreachable(_ error: any Error) -> Bool {
        if let error = error as? SwiftSonicError {
            switch error {
            case .network(let underlying): return isUnreachable(underlying)
            case .httpError(let status, _, _): return status == 408 || status >= 500
            case .rateLimited: return true
            default: return false
            }
        }
        guard !UserFacingError.isCancellation(error) else { return false }
        let mapped = UserFacingError.from(error)
        return mapped == .noNetwork || mapped == .serverUnreachable || mapped == .contentUnavailableOffline
    }

    // MARK: - Sync

    func syncFromServer() async throws {
        guard let serverId = await MainActor.run(body: { serverState.activeServer?.id }) else { return }

        // Queued changes go first, so the list fetched next already has them.
        await flushPending()
        let requestedAt = Date()
        let starred = try await libraryService.getStarred2()
        try Task.checkCancellation()
        try await reconcile(with: starred, serverID: serverId, requestedAt: requestedAt)
    }

    /// Makes the local hearts match a starred list someone else already fetched, such as Home's,
    /// so a shelf of favourites and its hearts come from the same answer.
    func reconcile(with starred: Starred2, serverID serverId: UUID, requestedAt: Date) async throws {
        guard await MainActor.run(body: { serverState.activeServer?.id }) == serverId else { throw CancellationError() }
        // Changes still waiting to be sent win over the server's list, which doesn't have them yet.
        let queued = Dictionary(await outbox.pending(serverID: serverId).map { ($0.recordID, $0.starred) },
                                uniquingKeysWith: { _, latest in latest })
        // A star or unstar made since the list was requested may be missing from it; the next
        // sync catches up instead of undoing it.
        guard editsInFlight == 0, lastEditFinished < requestedAt else { return }

        let descriptor = FetchDescriptor<FavoriteRecord>(
            predicate: #Predicate<FavoriteRecord> { $0.serverId == serverId }
        )
        let existing = try backgroundContext.fetch(descriptor)
        let existingIds = Set(existing.map(\.id))

        var newIds = Set<String>()
        var added = 0
        var unchanged = 0

        func upsert(type: FavoriteType, itemId: String) {
            let compositeId = "\(type.rawValue):\(itemId)"
            guard queued[compositeId] != false else { return }
            newIds.insert(compositeId)
            if existingIds.contains(compositeId) {
                unchanged += 1
            } else {
                backgroundContext.insert(FavoriteRecord(itemType: type, itemId: itemId, starredDate: Date(), serverId: serverId))
                added += 1
            }
        }

        for song in starred.song ?? []     { upsert(type: .song,   itemId: song.id) }
        for album in starred.album ?? []   { upsert(type: .album,  itemId: album.id) }
        for artist in starred.artist ?? [] { upsert(type: .artist, itemId: artist.id) }
        for (compositeId, isStarred) in queued where isStarred && !newIds.contains(compositeId) {
            let parts = compositeId.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let type = FavoriteType(rawValue: parts[0]) else { continue }
            upsert(type: type, itemId: parts[1])
        }

        let toRemove = existing.filter { !newIds.contains($0.id) }
        toRemove.forEach { backgroundContext.delete($0) }

        try saveChanges()
        Logger.favorites.info("Favorites synced: \(added, privacy: .public) added, \(toRemove.count, privacy: .public) removed, \(unchanged, privacy: .public) unchanged")
    }
    private func beginEdit() { editsInFlight += 1 }

    private func endEdit() {
        editsInFlight -= 1
        lastEditFinished = Date()
    }

    private func saveChanges() throws {
        do { try backgroundContext.save() }
        catch { backgroundContext.rollback(); throw error }
    }

}
