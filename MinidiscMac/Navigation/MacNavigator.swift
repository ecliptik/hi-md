import Observation
import SwiftUI

/// The sidebar's sections and the user's playlists.
enum MacSidebarItem: Hashable {
    case home
    case search
    case discover
    case radio
    case albums
    case artists
    case songs
    case genres
    case recentlyAdded
    case favorites
    case downloads
    case playlist(id: String)
}

/// A page pushed onto the detail column, above the selected section.
enum MacDestination: Hashable {
    /// `highlightedSongID` selects that song in the track list, as Go to Current Song does.
    case album(id: String, highlightedSongID: String? = nil)
    case artist(id: String, name: String)
    case genre(LibraryFacet)
    case playlist(id: String)
    /// A Home shelf's full list.
    case homeShelf(HomeShelf)
    /// Recommended for You: albums suggested by the chosen AI provider.
    case recommendations
    /// Make a Playlist: a playlist the chosen AI provider makes from the library.
    case playlistMaker
    /// Fresh Releases from the past 90 days, by month.
    case freshReleases
    case freshRelease(AlbumRecommendation)
    /// The Wrapped playlists and recaps.
    case wrapped
    /// A month's or a year's listening recap.
    case wrappedRecap(WrappedPeriod)
    /// The server's internet radio stations.
    case radio
}

extension MacDestination {
    /// The same album, artist, genre or playlist, whichever song it highlights.
    func opensSamePage(as other: MacDestination) -> Bool {
        switch (self, other) {
        case (.album(let id, _), .album(let otherID, _)): id == otherID
        case (.artist(let id, _), .artist(let otherID, _)): id == otherID
        case (.genre(let genre), .genre(let otherGenre)): genre == otherGenre
        case (.playlist(let id), .playlist(let otherID)): id == otherID
        default: false
        }
    }
}

/// What the inspector on the right of the window shows.
enum MacInspectorPane: String, Hashable {
    case lyrics
    case queue
}

/// The main window's navigation: the sidebar selection, the pages above it, the search text and the
/// inspector. The app owns one, so the menus and the menu bar player can drive the window.
@Observable
@MainActor
final class MacNavigator {
    /// Home on launch, as on the iPhone.
    var selection: MacSidebarItem? = .home {
        didSet { if selection != oldValue { path = [] } }
    }
    var path: [MacDestination] = []
    var searchText = ""
    var inspector: MacInspectorPane?
    /// The large Now Playing view covering the window, opened from the player bar's artwork or
    /// View > Now Playing.
    var isNowPlayingShown = false

    /// Shows a pane, or hides the inspector when that pane is already showing.
    func toggleInspector(_ pane: MacInspectorPane) {
        inspector = inspector == pane ? nil : pane
    }

    /// Set when Now Playing should open straight into its full-screen lyrics (the inspector's
    /// full-screen button); Now Playing clears it once it has.
    var opensFullScreenLyrics = false

    func showNowPlaying(fullScreenLyrics: Bool = false) {
        opensFullScreenLyrics = fullScreenLyrics
        isNowPlayingShown = true
    }

    func closeNowPlaying() {
        isNowPlayingShown = false
        opensFullScreenLyrics = false
    }

    /// Opens a page above the current section. An album or artist already open in the stack is
    /// brought back instead of being opened twice. Now Playing closes to show it.
    func show(_ destination: MacDestination) {
        isNowPlayingShown = false
        if selection == nil { selection = .home }
        if let index = path.firstIndex(where: { $0.opensSamePage(as: destination) }) {
            path.removeSubrange(index...)
        }
        path.append(destination)
    }

    /// A click on a sidebar item always lands on that section's own page, as in the Music app:
    /// clicking the item that's already selected closes the pages above it and Now Playing.
    func clickSidebar(_ item: MacSidebarItem) {
        guard selection == item else { return }
        isNowPlayingShown = false
        path = []
    }

    func showAlbum(of song: DisplayableSong, highlighting: Bool = false) {
        guard let albumID = song.albumId else { return }
        show(.album(id: albumID, highlightedSongID: highlighting ? song.id : nil))
    }

    func showArtist(of song: DisplayableSong) {
        guard let artistID = song.artistId else { return }
        show(.artist(id: artistID, name: song.artist ?? ""))
    }
}
