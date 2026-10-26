import Observation
import SwiftUI

/// The sidebar's sections and the user's playlists.
enum MacSidebarItem: Hashable {
    case search
    case discover
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
    var selection: MacSidebarItem? = .albums {
        didSet { if selection != oldValue { path = [] } }
    }
    var path: [MacDestination] = []
    var searchText = ""
    var inspector: MacInspectorPane?

    var isInspectorPresented: Bool {
        get { inspector != nil }
        set { if !newValue { inspector = nil } }
    }

    /// Shows a pane, or hides the inspector when that pane is already showing.
    func toggleInspector(_ pane: MacInspectorPane) {
        inspector = inspector == pane ? nil : pane
    }

    /// Opens a page above the current section, replacing it if it is already on top.
    func show(_ destination: MacDestination) {
        if selection == nil { selection = .albums }
        guard path.last != destination else { return }
        path.append(destination)
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
