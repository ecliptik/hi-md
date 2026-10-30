import Foundation
import OSLog

/// Stars and unstars made while the server couldn't be reached, kept on disk until they're sent.
/// An item has at most one entry: a later change replaces an earlier one, so starring and then
/// unstarring offline sends only the unstar.
actor FavoriteOutbox {
    nonisolated struct Change: Codable, Sendable, Equatable {
        let serverID: UUID
        /// A `FavoriteType` raw value.
        let itemType: String
        let itemID: String
        let starred: Bool
        let date: Date

        /// `FavoriteRecord.id`: "{type}:{id}".
        var recordID: String { "\(itemType):\(itemID)" }
    }

    private let fileURL: URL
    private var loaded: [Change]?

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("pending-favorites.json")
    }

    func record(_ change: Change) {
        var changes = all()
        changes.removeAll { $0.serverID == change.serverID && $0.recordID == change.recordID }
        changes.append(change)
        store(changes)
    }

    func pending(serverID: UUID) -> [Change] {
        all().filter { $0.serverID == serverID }
    }

    /// Drops sent changes, keeping any made to the same items since they were read.
    func remove(_ sent: [Change]) {
        let sentChanges = Set(sent.map { "\($0.serverID.uuidString)|\($0.recordID)|\($0.date.timeIntervalSinceReferenceDate)" })
        store(all().filter { !sentChanges.contains("\($0.serverID.uuidString)|\($0.recordID)|\($0.date.timeIntervalSinceReferenceDate)") })
    }

    /// Forgets a queued change once a newer one for the item has reached the server.
    func discard(recordID: String, serverID: UUID) {
        let changes = all()
        let kept = changes.filter { !($0.serverID == serverID && $0.recordID == recordID) }
        if kept.count != changes.count { store(kept) }
    }

    private func all() -> [Change] {
        if let loaded { return loaded }
        let changes = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([Change].self, from: $0) } ?? []
        loaded = changes
        return changes
    }

    private func store(_ changes: [Change]) {
        loaded = changes
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(changes).write(to: fileURL, options: .atomic)
        } catch {
            Logger.favorites.error("Couldn't save queued favourites: \(error, privacy: .public)")
        }
    }
}
