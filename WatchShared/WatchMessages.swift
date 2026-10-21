import Foundation

// The messages between Minidisc on the iPhone and its watch app, over WatchConnectivity. The
// phone publishes Now Playing as the application context; the watch sends commands as messages.

nonisolated enum WatchMessageKey {
    static let nowPlaying = "nowPlaying"
    static let command = "command"
}

/// What the watch shows. Encoded as JSON into the application context.
nonisolated struct WatchNowPlaying: Codable, Sendable, Equatable {
    var title: String?
    var artist: String?
    var isPlaying = false
    var isFavorite = false
    /// Local files and radio can't be favourited.
    var canFavorite = false
    var canSkip = false
    /// A small JPEG of the cover.
    var artwork: Data?
    var moods: [WatchMood] = []

    var hasTrack: Bool { title != nil }
}

nonisolated struct WatchMood: Codable, Sendable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let symbolName: String
}

nonisolated enum WatchCommand: Codable, Sendable, Equatable {
    case togglePlayPause
    case next
    case previous
    case toggleFavorite
    case playMood(String)

    var encoded: Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WatchCommand? { try? JSONDecoder().decode(WatchCommand.self, from: data) }
}

extension WatchNowPlaying {
    nonisolated var encoded: Data? { try? JSONEncoder().encode(self) }
    nonisolated static func decode(_ data: Data) -> WatchNowPlaying? { try? JSONDecoder().decode(WatchNowPlaying.self, from: data) }
}
