import SwiftUI
import SwiftData
import SwiftSonic

struct ArtistListView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistListViewModel?
    @AppStorage("minidisc.artistSort") private var artistSort: ArtistSort = .name
    @AppStorage("minidisc.artistListGrid") private var gridLayout = false

    private let gridColumns = [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: MinidiscSpacing.l)]

    var body: some View {
        Group {
            if let vm = viewModel {
                browseContent(vm)
            } else {
                LoadingStateView()
            }
        }
        .minidiscContentWidth()
        .navigationTitle("Artists")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ArtistSortMenu(sort: $artistSort)
                    .tint(.primary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(
                    gridLayout ? "List view" : "Grid view",
                    systemImage: gridLayout ? "list.bullet" : "square.grid.2x2"
                ) {
                    gridLayout.toggle()
                }
                .tint(.primary)
                .accessibilityIdentifier("browse.artists.layout")
            }
        }
        .task(id: loadID) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = ArtistListViewModel(libraryService: svc) }
            if container?.serverState.isOnline == true { await viewModel?.load() }
        }
    }

    @State private var derivation = DerivedValueCache<DerivationKey, Derivation>()

    private struct DerivationKey: Equatable {
        let artists: [ArtistID3]
        let sort: ArtistSort
    }

    private struct Derivation {
        let sorted: [ArtistID3]
        let index: [AlphabetScrollEntry]
    }

    private func displayedArtists(_ vm: ArtistListViewModel) -> [ArtistID3] {
        container?.serverState.isOnline == false ? container?.offlineLibrary.snapshot.artists ?? [] : vm.indexes.flatMap(\.artist)
    }

    /// Sorting a large library is far costlier than the body that needs the result, so the sorted
    /// rows and the alphabet index are recomputed only when the artists or the sort change.
    private func derived(_ artists: [ArtistID3]) -> Derivation {
        let key = DerivationKey(artists: artists, sort: artistSort)
        return derivation.value(for: key) {
            let sorted = key.sort.sorted(key.artists)
            let byName = key.sort == .name ? sorted : ArtistSort.name.sorted(key.artists)
            return Derivation(
                sorted: sorted,
                index: byName.map { AlphabetScrollEntry(id: $0.id, name: $0.sortName ?? $0.name) }
            )
        }
    }

    @ViewBuilder
    private func browseContent(_ vm: ArtistListViewModel) -> some View {
        let artists = displayedArtists(vm)
        if container?.serverState.isOnline != false && vm.isLoading && artists.isEmpty {
            LoadingStateView()
        } else if container?.serverState.isOnline == false && artists.isEmpty {
            OfflineBrowsingEmptyView()
        } else if let error = vm.error, artists.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Artists",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if artists.isEmpty {
            EmptyStateView(
                systemImage: "music.mic",
                title: "No Artists",
                subtitle: "Your library appears to be empty."
            )
        } else if gridLayout {
            artistsGrid(vm, artists: artists)
        } else {
            flatList(vm, artists: artists)
        }
    }

    private func flatList(_ vm: ArtistListViewModel, artists: [ArtistID3]) -> some View {
        let derived = derived(artists)
        return AlphabetIndexedContent(entries: derived.index, prepareJump: { artistSort = .name }) {
            List(derived.sorted) { artist in
                NavigationLink(value: HomeDestination.artist(artist)) {
                    ArtistRow(artist: artist)
                }
                .id(artist.id)
                .accessibilityIdentifier("browse.artist.\(artist.id)")
            }
            .listStyle(.plain)
            .refreshable { await refresh(vm) }
        }
    }

    private func artistsGrid(_ vm: ArtistListViewModel, artists: [ArtistID3]) -> some View {
        let derived = derived(artists)
        return AlphabetIndexedContent(entries: derived.index, prepareJump: { artistSort = .name }) {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: MinidiscSpacing.l) {
                    ForEach(derived.sorted) { artist in
                        NavigationLink(value: HomeDestination.artist(artist)) {
                            ArtistGridCard(artist: artist)
                        }
                        .buttonStyle(.plain)
                        .id(artist.id)
                        .accessibilityIdentifier("browse.artist.\(artist.id)")
                    }
                }
                .padding(MinidiscSpacing.l)
            }
            .refreshable { await refresh(vm) }
        }
    }

    private var loadID: ServerAccessSnapshot? {
        container?.serverState.accessSnapshot
    }

    private func refresh(_ viewModel: ArtistListViewModel) async {
        if container?.serverState.isOnline == true {
            _ = try? await container?.libraryCatalog.refreshArtists()
        }
        if container?.serverState.isOnline == true { await viewModel.load() }
        else { await container?.offlineLibrary.refresh() }
    }
}

// MARK: - Offline Browse

struct OfflineArtistAlbumsView: View {
    let artist: OfflineArtistSummary

    var body: some View {
        List {
            ForEach(artist.albums) { album in
                NavigationLink(value: HomeDestination.offlineAlbum(album)) {
                    AlbumRow(
                        albumId: album.albumId,
                        name: album.albumName,
                        artist: album.artistName,
                        year: nil,
                        coverArtId: album.coverArtId
                    )
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayModeInline()
        .minidiscContentWidth()
    }
}
