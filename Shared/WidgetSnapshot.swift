import CryptoKit
import Foundation

/// The App Group shared by the app and its widget extension.
nonisolated enum AppGroup {
    static let identifier = "group.com.ecliptik.minidisc"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// Everything the widgets show, written by the app into the App Group.
///
/// The extension never touches SwiftData or the network: it reads this file and the artwork
/// thumbnails stored next to it. Titles arrive already localized by the app.
nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    struct Track: Codable, Sendable, Equatable {
        var title: String
        var artist: String
        var artworkFile: String?
        var isPlaying: Bool
    }

    struct Collection: Codable, Sendable, Equatable, Identifiable {
        enum Kind: String, Codable, Sendable { case album, playlist, artist }
        var id: String
        var kind: Kind
        var title: String
        var subtitle: String?
        var coverArtId: String?
        var artworkFile: String?

        /// Opens the collection in the app.
        var url: URL {
            var components = URLComponents()
            components.scheme = "minidisc"
            components.host = kind.rawValue
            components.path = "/" + id
            components.queryItems = [URLQueryItem(name: "name", value: title)]
                + (coverArtId.map { [URLQueryItem(name: "cover", value: $0)] } ?? [])
            return components.url ?? URL(string: "minidisc://")!
        }
    }

    struct MoodEntry: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var title: String
        var symbolName: String
        /// False until the server has a playlist for this mood.
        var isAvailable: Bool
    }

    var hasServer = false
    var nowPlaying: Track?
    var recentlyPlayed: [Collection] = []
    var pinned: [Collection] = []
    var moods: [MoodEntry] = []
}

/// Reads and writes the snapshot and its artwork in the App Group container.
nonisolated enum WidgetSnapshotStore {
    private static var snapshotURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("widget-snapshot.json")
    }

    static var artworkDirectory: URL? {
        AppGroup.containerURL?.appendingPathComponent("WidgetArtwork", isDirectory: true)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) throws {
        guard let url = snapshotURL else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    static func artworkURL(_ file: String?) -> URL? {
        guard let file else { return nil }
        return artworkDirectory?.appendingPathComponent(file)
    }

    /// A stable file name for a cover, whatever characters the server uses in its IDs.
    static func artworkFileName(coverArtId: String) -> String {
        let digest = SHA256.hash(data: Data(coverArtId.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "\(digest).jpg"
    }
}
