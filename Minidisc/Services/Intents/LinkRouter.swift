import Foundation
import Observation

/// Holds a `minidisc://` link until the main view can show it.
///
/// Widgets, Spotlight and Shortcuts can open an item while the app is still launching, before
/// `MainTabView` exists, so the link waits here instead of being posted and lost. It also waits
/// while no server is active, since albums, artists and playlists live on the server.
@MainActor
@Observable
final class LinkRouter {
    private(set) var pending: URL?

    func open(_ url: URL) {
        pending = url
    }

    func open(_ reference: MusicIntentID, name: String) {
        guard let url = Self.url(for: reference, name: name) else { return }
        open(url)
    }

    /// Returns the waiting link and clears it.
    func take() -> URL? {
        defer { pending = nil }
        return pending
    }

    /// Returns the waiting link and clears it if there is a server to open it on. Otherwise the
    /// link stays queued, and a newer link replaces it.
    func take(hasActiveServer: Bool) -> URL? {
        guard hasActiveServer else { return nil }
        return take()
    }

    nonisolated static func url(for reference: MusicIntentID, name: String) -> URL? {
        let host: String
        switch reference.kind {
        case .album: host = "album"
        case .artist: host = "artist"
        case .playlist: host = "playlist"
        case .song: return nil
        }
        var components = URLComponents()
        components.scheme = "minidisc"
        components.host = host
        components.path = "/" + reference.resourceID
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url
    }
}
