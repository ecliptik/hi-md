import Foundation

/// How many upcoming songs in the queue are saved into the stream cache before they play.
nonisolated enum CacheLookahead: Hashable, Sendable, Identifiable {
    /// The next `count` songs; zero turns pre-caching off on that network.
    case songs(Int)
    /// Every upcoming song, as far as the stream cache size limit allows.
    case entireQueue

    /// The value kept in UserDefaults: the song count, or -1 for the entire queue.
    init(storedValue: Int) {
        self = storedValue < 0 ? .entireQueue : .songs(storedValue)
    }

    var storedValue: Int {
        switch self {
        case .songs(let count): max(0, count)
        case .entireQueue: -1
        }
    }

    var id: Int { storedValue }

    /// The most songs to fetch, or nil for no limit other than the cache size.
    var songLimit: Int? {
        switch self {
        case .songs(let count): max(0, count)
        case .entireQueue: nil
        }
    }

    var isOff: Bool { songLimit == 0 }
}
