import Observation
import SwiftUI

/// The Mac interface's own state, owned by the app: the window's navigation and, once the shared
/// services are ready, the playback actions and the playlists. The main window, the menus and the
/// menu bar player all read the same instances.
@Observable
@MainActor
final class MacInterface {
    let navigator = MacNavigator()
    @ObservationIgnored private var playbackCache: MacPlayback?
    @ObservationIgnored private var playlistsCache: MacPlaylists?
    @ObservationIgnored private var playlistsContainer: AppContainer?

    /// Created on first use, once per container.
    func playback(for container: AppContainer) -> MacPlayback {
        if let playbackCache, playbackCache.container === container { return playbackCache }
        let playback = MacPlayback(container: container)
        playbackCache = playback
        return playback
    }

    func playlists(for container: AppContainer) -> MacPlaylists {
        if let playlistsCache, playlistsContainer === container { return playlistsCache }
        let playlists = MacPlaylists(container: container)
        playlistsCache = playlists
        playlistsContainer = container
        return playlists
    }

    @ObservationIgnored private var homeCache: MacHomeFeed?

    /// Home's feed for the active server, kept while the window shows other sections so going back
    /// to Home doesn't start over. Nil without a server.
    func homeFeed(for container: AppContainer) -> MacHomeFeed? {
        guard let serverID = container.serverState.activeServer?.id else { return nil }
        if let homeCache, homeCache.serverID == serverID, homeCache.container === container { return homeCache }
        let feed = MacHomeFeed(container: container, serverID: serverID)
        homeCache = feed
        return feed
    }

    /// The Settings > Appearance switch for the menu bar player.
    static let showsMenuBarPlayerKey = "minidisc.mac.showsMenuBarPlayer"
}
