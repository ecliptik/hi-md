import SwiftSonic
import SwiftUI

/// A placeholder main window that proves the shared stack on the Mac: a sidebar, an album list
/// loaded from the server, and a player bar. The real Mac interface replaces it.
struct MacRootView: View {
    let container: AppContainer

    enum Section: Hashable {
        case albums
        case artists
    }

    @State private var section: Section? = .albums

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $section) {
                    SwiftUI.Section("Library") {
                        Label("Albums", systemImage: "square.stack").tag(Section.albums)
                        Label("Artists", systemImage: "music.microphone").tag(Section.artists)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            } detail: {
                if container.serverState.activeServer == nil {
                    ContentUnavailableView(
                        "No Server",
                        systemImage: "server.rack",
                        description: Text("No server configured. Please add a server in Settings.")
                    )
                } else {
                    switch section {
                    case .artists:
                        MacArtistList(container: container)
                    case .albums, nil:
                        MacAlbumList(container: container)
                    }
                }
            }
            Divider()
            MacPlayerBar(container: container)
        }
        .frame(minWidth: 720, minHeight: 440)
    }
}

/// Albums from the shared library catalog. Double-click an album to play it.
private struct MacAlbumList: View {
    let container: AppContainer
    @State private var viewModel: AlbumListViewModel?
    @State private var selection: AlbumID3.ID?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.albums.isEmpty, viewModel.isLoading {
                    ProgressView()
                } else if viewModel.albums.isEmpty, let error = viewModel.error {
                    ContentUnavailableView(
                        "Unable to Load Albums",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                } else {
                    List(viewModel.albums, selection: $selection) { album in
                        MacAlbumRow(album: album)
                    }
                    .contextMenu(forSelectionType: AlbumID3.ID.self) { ids in
                        if let id = ids.first {
                            Button("Play") { play(albumID: id) }
                        }
                    } primaryAction: { ids in
                        if let id = ids.first { play(albumID: id) }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Albums")
        .task(id: container.serverState.accessSnapshot) {
            let model = viewModel ?? AlbumListViewModel(libraryService: container.libraryService)
            viewModel = model
            await model.load()
        }
    }

    /// Loads the album's songs through the shared album view model, then plays them in order.
    private func play(albumID: String) {
        Task {
            let album = AlbumDetailViewModel(
                albumId: albumID,
                libraryService: container.libraryService,
                downloadService: container.downloadService,
                toastService: container.toastService,
                serverState: container.serverState,
                offlineFavorites: container.offlineFavoritesStore
            )
            await album.load()
            let songs = album.songs
            guard !songs.isEmpty else { return }
            await container.toastService.perform {
                try await container.playerService.play(tracks: songs, startIndex: 0)
            }
        }
    }
}

private struct MacAlbumRow: View {
    let album: AlbumID3

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(id: album.coverArt ?? album.id, size: 40, cornerRadius: 4, placeholderSystemImage: "square.stack")
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .lineLimit(1)
                if let artist = album.artist {
                    Text(artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Artists from the shared library catalog, as a plain list for now.
private struct MacArtistList: View {
    let container: AppContainer
    @State private var viewModel: ArtistListViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.indexes.isEmpty, viewModel.isLoading {
                    ProgressView()
                } else if viewModel.indexes.isEmpty, let error = viewModel.error {
                    ContentUnavailableView(
                        "Unable to Load Artists",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                } else {
                    List(viewModel.indexes.flatMap(\.artist)) { artist in
                        Text(artist.name)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Artists")
        .task(id: container.serverState.accessSnapshot) {
            let model = viewModel ?? ArtistListViewModel(libraryService: container.libraryService)
            viewModel = model
            await model.load()
        }
    }
}
