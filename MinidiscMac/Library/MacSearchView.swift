import SwiftSonic
import SwiftUI

/// Search results for the toolbar's search field, grouped into artists, albums and songs.
struct MacSearchView: View {
    let container: AppContainer

    @Environment(MacNavigator.self) private var navigator
    @State private var viewModel: SearchViewModel?

    private var query: String { navigator.searchText.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass",
                                       description: Text("Type in the search field to find artists, albums and songs."))
            } else if let viewModel {
                results(viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Search")
        .task(id: query) {
            let model = viewModel ?? SearchViewModel(libraryService: container.libraryService,
                                                     serverState: container.serverState)
            viewModel = model
            await model.search(query: query)
        }
    }

    @ViewBuilder
    private func results(_ model: SearchViewModel) -> some View {
        let artists = model.searchResults?.artist ?? []
        let albums = model.searchResults?.album ?? []
        let songs = (model.searchResults?.song ?? []).map { DisplayableSong(from: $0) }
        if model.isOffline {
            ContentUnavailableView("You're Offline", systemImage: "wifi.slash",
                                   description: Text("Search needs your server. Downloaded music is in Downloads."))
        } else if let error = model.searchError {
            ContentUnavailableView("Unable to Search", systemImage: "exclamationmark.triangle",
                                   description: Text(error.displayMessage))
        } else if model.searchResults == nil || (model.isSearching && model.resultsQuery != query) {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if artists.isEmpty && albums.isEmpty && songs.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !artists.isEmpty {
                        section("Artists") {
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: 18) {
                                    ForEach(artists) { artist in
                                        artistTile(artist)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                    if !albums.isEmpty {
                        section("Albums") { MacAlbumGrid(albums: Array(albums.prefix(24))) }
                    }
                    if !songs.isEmpty {
                        section("Songs") {
                            MacSongTable(songs: songs)
                                .frame(height: CGFloat(songs.count) * 28 + 48)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func artistTile(_ artist: ArtistID3) -> some View {
        NavigationLink(value: MacDestination.artist(id: artist.id, name: artist.name)) {
            VStack(spacing: 6) {
                CoverArtView(id: artist.coverArt ?? artist.id, size: 240, placeholderSystemImage: "music.microphone")
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                Text(artist.name)
                    .font(.callout)
                    .lineLimit(1)
                    .frame(width: 120)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { MacArtistMenu(artistID: artist.id) }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }
}
