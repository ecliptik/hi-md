import SwiftSonic
import SwiftUI

/// Library > Songs: every song in one table, sorted from the toolbar or by a column header.
struct MacSongsView: View {
    let container: AppContainer
    @State private var viewModel: SongsListViewModel?
    @AppStorage("minidisc.mac.songsSort") private var sort = LibrarySortOrder<SongSortField>(.title)

    var body: some View {
        let songs = viewModel?.displaySongs ?? []
        MacLoadingState(isLoading: viewModel?.isLoading ?? true, isEmpty: songs.isEmpty, error: viewModel?.error,
                        emptyTitle: "No Songs", retry: { await viewModel?.load(sort: .title) }) {
            MacSongTable(songs: songs, sort: $sort)
        }
        .toolbar {
            ToolbarItem {
                MacSortMenu(order: $sort, fields: SongSortField.withoutPosition)
            }
        }
        .overlay(alignment: .bottom) {
            if let viewModel, viewModel.isLoading, viewModel.loadedCount > 0 {
                Text("Loading \(viewModel.loadedCount) songs…")
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .navigationTitle("Songs")
        .navigationSubtitle(songs.isEmpty ? "" : String(localized: "\(songs.count) songs"))
        .task(id: container.serverState.accessSnapshot) {
            let model = viewModel ?? SongsListViewModel(libraryService: container.libraryService)
            viewModel = model
            await model.load(sort: .title)
        }
    }
}

/// Library > Genres: the genres in the library index, with their song counts.
struct MacGenresView: View {
    let container: AppContainer
    @State private var genres: [LibraryFacet]?

    var body: some View {
        MacLoadingState(isLoading: genres == nil, isEmpty: genres?.isEmpty ?? true,
                        emptyTitle: "No Genres", emptySystemImage: "guitars") {
            List(genres ?? []) { genre in
                NavigationLink(value: MacDestination.genre(genre)) {
                    LabeledContent {
                        Text("\(genre.songCount) songs").monospacedDigit()
                    } label: {
                        Label(genre.name, systemImage: "guitars")
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .navigationTitle("Genres")
        .task(id: container.serverState.activeServer?.id) {
            guard let serverID = container.serverState.activeServer?.id else { genres = []; return }
            genres = (try? await LibraryFacets.load(.genre, store: container.libraryIndexStore, serverID: serverID)) ?? []
        }
    }
}

/// The songs of one genre, from the library index so it works offline too.
struct MacGenreDetailView: View {
    let container: AppContainer
    let genre: LibraryFacet

    @Environment(MacPlayback.self) private var playback
    @State private var songs: [DisplayableSong]?
    @AppStorage("minidisc.mac.genreSongsSort") private var sort = LibrarySortOrder<SongSortField>(.title)

    var body: some View {
        MacLoadingState(isLoading: songs == nil, isEmpty: songs?.isEmpty ?? true, emptyTitle: "No Songs") {
            MacSongTable(songs: songs ?? [], sort: $sort)
        }
        .navigationTitle(genre.name)
        .toolbar {
            ToolbarItemGroup {
                Button("Play", systemImage: "play.fill") { playback.play(sort.sorted(songs ?? [])) }
                Button("Shuffle", systemImage: "shuffle") { playback.shuffle(songs ?? []) }
            }
            ToolbarItem {
                MacSortMenu(order: $sort, fields: SongSortField.withoutPosition)
            }
        }
        .task(id: genre) {
            guard let serverID = container.serverState.activeServer?.id else { songs = []; return }
            let downloaded = await container.downloadService.downloadedSongIds(serverId: serverID)
            let found = (try? await LibraryFacets.songs(of: genre, store: container.libraryIndexStore, serverID: serverID)) ?? []
            songs = found.map { DisplayableSong(from: $0, isDownloaded: downloaded.contains($0.id)) }
        }
    }
}
