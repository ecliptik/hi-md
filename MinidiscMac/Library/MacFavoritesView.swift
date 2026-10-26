import SwiftSonic
import SwiftUI

/// Library > Favourites: the songs, albums and artists starred on the server.
struct MacFavoritesView: View {
    let container: AppContainer

    enum Kind: String, CaseIterable, Identifiable {
        case songs, albums, artists
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .songs: "Songs"
            case .albums: "Albums"
            case .artists: "Artists"
            }
        }
    }

    @Environment(MacPlayback.self) private var playback
    @State private var viewModel: FavoritesViewModel?
    @AppStorage("minidisc.mac.favoritesKind") private var kind: Kind = .songs

    var body: some View {
        let model = viewModel
        let songs = (model?.songs ?? []).map { DisplayableSong(from: $0) }
        let isEmpty = switch kind {
        case .songs: songs.isEmpty
        case .albums: model?.albums.isEmpty ?? true
        case .artists: model?.artists.isEmpty ?? true
        }
        MacLoadingState(isLoading: model?.isLoading ?? true, isEmpty: isEmpty, error: model?.error,
                        emptyTitle: "No Favorites", emptySystemImage: "heart", retry: { await model?.load() }) {
            switch kind {
            case .songs:
                MacSongTable(songs: songs)
            case .albums:
                ScrollView {
                    MacAlbumGrid(albums: model?.albums ?? [])
                        .padding(20)
                }
            case .artists:
                List(model?.artists ?? []) { artist in
                    NavigationLink(value: MacDestination.artist(id: artist.id, name: artist.name)) {
                        MacArtistRow(artist: artist)
                    }
                    .contextMenu { MacArtistMenu(artistID: artist.id) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Favorites")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if kind == .songs {
                ToolbarItemGroup {
                    Button("Play", systemImage: "play.fill") { playback.play(songs) }
                        .disabled(songs.isEmpty)
                    Button("Shuffle", systemImage: "shuffle") { playback.shuffle(songs) }
                        .disabled(songs.isEmpty)
                }
            }
        }
        .task(id: container.serverState.accessSnapshot) {
            let model = viewModel ?? FavoritesViewModel(libraryService: container.libraryService)
            viewModel = model
            await model.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscFavoritesChanged)) { _ in
            Task { await viewModel?.load() }
        }
    }
}
