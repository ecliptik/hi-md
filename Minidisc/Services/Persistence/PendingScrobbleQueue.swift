import Foundation
import OSLog

/// A completed play the server has not acknowledged yet.
nonisolated struct PendingScrobble: Codable, Sendable, Equatable {
    let songId: String
    let serverId: UUID
    let playedAt: Date
}

/// Durable queue of plays reported while the server was unreachable, for example while listening
/// to downloads away from a Tailscale network. Entries are sent oldest first with their original
/// play time once the server answers again.
actor PendingScrobbleQueue {
    /// Bounds the file if the server stays unreachable for a very long time; the oldest plays go first.
    static let capacity = 5_000

    private let fileURL: URL
    private var entries: [PendingScrobble]

    init(fileURL: URL = URL.applicationSupportDirectory.appendingPathComponent("app.minidisc/pending-scrobbles.json")) {
        self.fileURL = fileURL
        entries = Self.load(from: fileURL)
    }

    var count: Int { entries.count }

    func enqueue(_ scrobble: PendingScrobble) {
        entries.append(scrobble)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        persist()
    }

    /// Oldest first, for one server only: plays never move to a different library.
    func pending(serverId: UUID) -> [PendingScrobble] {
        entries.filter { $0.serverId == serverId }
    }

    func remove(_ scrobble: PendingScrobble) {
        guard let index = entries.firstIndex(of: scrobble) else { return }
        entries.remove(at: index)
        persist()
    }

    func removeAll(serverId: UUID) {
        entries.removeAll { $0.serverId == serverId }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            Logger.library.error("Could not save pending scrobbles: \(error, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [PendingScrobble] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            let decoded = try JSONStoreRecovery.decodeArray(PendingScrobble.self, from: data)
            if decoded.dropped > 0 { JSONStoreRecovery.quarantine(url, logger: Logger.library) }
            return decoded.elements
        } catch {
            JSONStoreRecovery.quarantine(url, logger: Logger.library)
            return []
        }
    }
}
