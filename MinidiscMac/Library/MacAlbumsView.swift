import SwiftSonic
import SwiftUI

/// Library > Albums: every album as a grid of covers, sorted from the toolbar.
struct MacAlbumsView: View {
    let container: AppContainer
    @State private var viewModel: AlbumListViewModel?
    @AppStorage("minidisc.mac.albumSort") private var sort = LibrarySortOrder<AlbumSortField>(.name)

    var body: some View {
        let albums = viewModel.map { sort.sorted($0.albums) } ?? []
        MacLoadingState(isLoading: viewModel?.isLoading ?? true, isEmpty: albums.isEmpty, error: viewModel?.error,
                        emptyTitle: "No Albums", emptySystemImage: "square.stack", retry: { await viewModel?.load() }) {
            ScrollView {
                MacAlbumGrid(albums: albums)
                    .padding(20)
            }
        }
        .navigationTitle("Albums")
        .toolbar {
            ToolbarItem {
                MacSortMenu(order: $sort)
            }
        }
        .task(id: container.serverState.accessSnapshot) {
            let model = viewModel ?? AlbumListViewModel(libraryService: container.libraryService)
            viewModel = model
            await model.load()
        }
    }
}

/// Library > Recently Added: the newest albums on the server.
struct MacRecentlyAddedView: View {
    let container: AppContainer
    @State private var albums: [AlbumID3] = []
    @State private var isLoading = true
    @State private var error: UserFacingError?
    @AppStorage("minidisc.mac.recentlyAddedSort") private var sort = LibrarySortOrder<AlbumSortField>(.recentlyAdded)

    var body: some View {
        let albums = sort.sorted(self.albums)
        MacLoadingState(isLoading: isLoading, isEmpty: albums.isEmpty, error: error,
                        emptyTitle: "No Albums", emptySystemImage: "clock", retry: load) {
            ScrollView {
                MacAlbumGrid(albums: albums)
                    .padding(20)
            }
        }
        .navigationTitle("Recently Added")
        .toolbar {
            ToolbarItem {
                MacSortMenu(order: $sort)
            }
        }
        .task(id: container.serverState.accessSnapshot) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            albums = try await container.libraryService.recentlyAddedAlbums(size: 100)
            error = nil
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            self.error = UserFacingError.from(error)
        }
    }
}
