import SwiftUI
import SwiftData
import SwiftSonic

struct LibraryView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \PinnedItem.sortOrder) private var allPinnedItems: [PinnedItem]
    @Query private var recentDownloadedAlbums: [DownloadedAlbum]
    @Query private var recentDownloadedPlaylists: [DownloadedPlaylist]
    init() {
        var albumDescriptor = FetchDescriptor<DownloadedAlbum>(
            sortBy: [SortDescriptor(\DownloadedAlbum.downloadedAt, order: .reverse)]
        )
        albumDescriptor.fetchLimit = 24
        _recentDownloadedAlbums = Query(albumDescriptor)

        var playlistDescriptor = FetchDescriptor<DownloadedPlaylist>(
            sortBy: [SortDescriptor(\DownloadedPlaylist.downloadedAt, order: .reverse)]
        )
        playlistDescriptor.fetchLimit = 24
        _recentDownloadedPlaylists = Query(playlistDescriptor)
    }

    @Namespace private var pinnedZoomNamespace
    @Namespace private var recentlyAddedZoomNamespace
    @Namespace private var playlistZoomNamespace
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var viewModel: HomeViewModel?
    // Local mutable copy for smooth drag-to-reorder; synced from @Query on count changes.
    @State private var localPinnedItems: [PinnedItem] = []
    @State private var dropTargetId: String?
    @State private var showCreatePlaylistSheet = false
    private let recentColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: MinidiscSpacing.m)
    ]
    private let pinnedColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var isOnline: Bool { container?.serverState.isOnline == true }

    private var recentDownloadedItems: [DownloadedItem] {
        let albumItems = recentDownloadedAlbums.map {
            DownloadedItem(
                id: "album:\($0.albumId)",
                itemId: $0.albumId,
                type: .album,
                name: $0.name,
                subtitle: $0.artist ?? "",
                coverArtId: $0.coverArtId,
                downloadedAt: $0.downloadedAt
            )
        }
        let playlistItems = recentDownloadedPlaylists.map {
            DownloadedItem(
                id: "playlist:\($0.playlistId)",
                itemId: $0.playlistId,
                type: .playlist,
                name: $0.name,
                subtitle: "",
                coverArtId: $0.coverArtId,
                downloadedAt: $0.downloadedAt
            )
        }
        return (albumItems + playlistItems)
            .filter { item in
                guard !isOnline else { return true }
                let local = container?.offlineLibrary.snapshot
                return item.type == .album ? local?.albumIDs.contains(item.itemId) == true : local?.playlistIDs.contains(item.itemId) == true
            }
            .sorted { $0.downloadedAt > $1.downloadedAt }
            .prefix(24)
            .map { $0 }
    }

    private var visiblePinnedItems: [PinnedItem] {
        guard container?.serverState.isOnline != true else { return localPinnedItems }
        return localPinnedItems.filter { isAvailableOffline($0) }
    }

    private func isAvailableOffline(_ item: PinnedItem) -> Bool {
        guard let snapshot = container?.offlineLibrary.snapshot else { return false }
        switch PinnedItemType(rawValue: item.itemType) {
        case .album: return snapshot.albumIDs.contains(item.itemId)
        case .playlist: return snapshot.playlistIDs.contains(item.itemId)
        case .none: return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MinidiscSpacing.xl) {
                if !visiblePinnedItems.isEmpty {
                    pinnedSection
                }
                if !isOnline && container?.offlineLibrary.snapshot.songs.isEmpty != false
                    && container?.localMusic.snapshot.tracks.contains(where: \.isAvailable) != true {
                    OfflineBrowsingEmptyView()
                }
                librarySection
                recentlySection
            }
            .padding(.horizontal, MinidiscSpacing.l)
            .padding(.top, MinidiscSpacing.m)
            .padding(.bottom, MinidiscSpacing.xl)
        }
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Playlist", systemImage: "text.badge.plus") {
                    showCreatePlaylistSheet = true
                }
                .tint(.primary)
                .disabled(!isOnline)
            }
        }
        .fullScreenCover(isPresented: $showCreatePlaylistSheet) {
            CreatePlaylistSheet()
        }
        .navigationDestination(for: HomeDestination.self) { destination in
            switch destination {
            case .libraryAlbums:
                AlbumsListView()
            case .libraryArtists:
                ArtistListView()
            case .librarySongs:
                SongsListView()
            case .libraryPlaylists:
                PlaylistListView(zoomNamespace: playlistZoomNamespace)
            case .libraryFavorites:
                FavoritesView()
            case .libraryDownloads:
                DownloadedView()
            case .album(let album):
                AlbumDetailView(
                    album: album,
                    zoomSourceId: album.id,
                    zoomNamespace: recentlyAddedZoomNamespace,
                    coverArtId: album.coverArt,
                    initialDominantColor: colorExtractor.dominantColor(for: album.coverArt ?? album.id, image: nil),
                    initialCoverImage: artworkImageCache.cachedImage(for: album.coverArt ?? album.id)
                )
            case .artist(let artist):
                ArtistDetailView(artist: artist)
            case .playlist(let playlist):
                PlaylistDetailView(
                    playlist: playlist,
                    coverArtId: playlist.coverArt ?? playlist.id,
                    initialCoverImage: artworkImageCache.cachedImage(for: playlist.coverArt ?? playlist.id),
                    zoomSourceId: playlist.id,
                    zoomNamespace: playlistZoomNamespace
                )
            case .downloadedAlbum(let display):
                AlbumDetailView(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId, mode: .downloadedOnly)
            case .albumById(let id, let name, _, let coverArtId):
                AlbumDetailView(
                    albumId: id,
                    albumName: name,
                    zoomSourceId: id,
                    zoomNamespace: pinnedZoomNamespace,
                    coverArtId: coverArtId,
                    initialCoverImage: artworkImageCache.cachedImage(for: coverArtId ?? id)
                )
            case .playlistById(let id, let name, let coverArtId):
                PlaylistDetailView(
                    playlistId: id,
                    name: name,
                    coverArtId: coverArtId,
                    initialCoverImage: artworkImageCache.cachedImage(for: coverArtId ?? id),
                    zoomSourceId: id,
                    zoomNamespace: pinnedZoomNamespace
                )
            case .artistById(let id, let name, let coverArtId):
                ArtistDetailView(artist: ArtistID3(id: id, name: name, coverArt: coverArtId))
            case .artistBestOf(let id, let name, let coverArtId):
                ArtistBestOfView(artistId: id, artistName: name, coverArtId: coverArtId)
            case .recentlyAdded(let coverArtId):
                RecentlyAddedView(coverArtId: coverArtId)
            case .offlineArtist(let artist):
                OfflineArtistAlbumsView(artist: artist)
            case .offlineAlbum(let album):
                AlbumDetailView(albumId: album.albumId, albumName: album.albumName, coverArtId: album.coverArtId)
            }
        }
        .onAppear { localPinnedItems = allPinnedItems }
        .onChange(of: allPinnedItems.count) { _, _ in localPinnedItems = allPinnedItems }
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = HomeViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
    }

    // MARK: - Pinned section

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            Text("Pinned")
                .font(.minidiscShelfTitle)
            LazyVGrid(columns: pinnedColumns, spacing: MinidiscSpacing.m) {
                ForEach(visiblePinnedItems) { item in
                    HomePinnedCard(item: item, namespace: pinnedZoomNamespace)
                        .scaleEffect(dropTargetId == item.id ? 1.05 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: dropTargetId)
                        .draggable(item.id)
                        .dropDestination(for: String.self) { droppedIds, _ in
                            guard let sourceId = droppedIds.first,
                                  sourceId != item.id,
                                  let sourceIdx = localPinnedItems.firstIndex(where: { $0.id == sourceId }),
                                  let destIdx = localPinnedItems.firstIndex(where: { $0.id == item.id })
                            else { return false }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                localPinnedItems.move(
                                    fromOffsets: IndexSet(integer: sourceIdx),
                                    toOffset: destIdx > sourceIdx ? destIdx + 1 : destIdx
                                )
                            }
                            container?.pinService.reorder(items: localPinnedItems)
                            return true
                        } isTargeted: { targeted in
                            dropTargetId = targeted ? item.id : nil
                        }
                }
            }
        }
    }

    // MARK: - Library section

    /// Two columns, or one at accessibility text sizes so tile titles don't wrap a letter at a time.
    private var tileColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: MinidiscSpacing.m), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    /// The tile grid from the mockups, then Shuffle Tracks and Shuffle Albums.
    private var librarySection: some View {
        let local = container?.offlineLibrary.snapshot ?? OfflineBrowsingSnapshot()
        let shuffleLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: MinidiscSpacing.m)) : AnyLayout(HStackLayout(spacing: MinidiscSpacing.m))
        return VStack(spacing: MinidiscSpacing.m) {
            LazyVGrid(columns: tileColumns, spacing: MinidiscSpacing.m) {
                if isOnline || !local.albums.isEmpty {
                    NavigationLink(value: HomeDestination.libraryAlbums) { LibraryTile(title: "Albums", systemImage: "square.stack.fill") }
                }
                if isOnline || !local.artists.isEmpty {
                    NavigationLink(value: HomeDestination.libraryArtists) { LibraryTile(title: "Album Artists", systemImage: "person.crop.square.fill") }
                }
                if isOnline || !local.songs.isEmpty {
                    NavigationLink(value: HomeDestination.librarySongs) { LibraryTile(title: "Tracks", systemImage: "music.note") }
                }
                NavigationLink { LibraryFacetListView(kind: .trackArtist) } label: {
                    LibraryTile(title: "Track Artists", systemImage: "music.mic")
                }
                NavigationLink { LibraryFacetListView(kind: .genre) } label: {
                    LibraryTile(title: "Genres", systemImage: "guitars.fill")
                }
                NavigationLink { LibraryFacetListView(kind: .composer) } label: {
                    LibraryTile(title: "Composers", systemImage: "music.quarternote.3")
                }
                if isOnline || !local.favorites.songs.isEmpty || !local.favorites.albums.isEmpty || !local.favorites.artists.isEmpty {
                    NavigationLink(value: HomeDestination.libraryFavorites) { LibraryTile(title: "Favorites", systemImage: "heart.fill") }
                }
                if isOnline || local.songs.contains(where: \.isDownloaded) {
                    NavigationLink(value: HomeDestination.libraryDownloads) { LibraryTile(title: "Downloads", systemImage: "arrow.down.circle.fill") }
                }
                if container?.localMusic.snapshot.folders.isEmpty == false {
                    NavigationLink { LocalMusicView() } label: {
                        LibraryTile(title: LocalizedStringResource("Local Files", table: "LocalMusic"), systemImage: "folder.fill")
                    }
                }
                if container?.lidarrSettings.isConnected == true {
                    NavigationLink { LidarrLibraryView() } label: { LibraryTile(title: "Lidarr", systemImage: "opticaldisc.fill") }
                }
            }
            .buttonStyle(.plain)

            shuffleLayout {
                Button { Task { await shuffleTracks() } } label: {
                    LibraryTile(title: "Tracks", systemImage: "shuffle", isShuffle: true)
                }
                .accessibilityLabel("Shuffle Tracks")
                Button { Task { await shuffleAlbums() } } label: {
                    LibraryTile(title: "Albums", systemImage: "shuffle", isShuffle: true)
                }
                .accessibilityLabel("Shuffle Albums")
            }
            .buttonStyle(.plain)
        }
    }

    /// Random songs from the server, or from downloads when offline.
    private func shuffleTracks() async {
        guard let container else { return }
        HapticFeedback.medium.trigger()
        await container.toastService.perform {
            let songs: [DisplayableSong]
            if container.serverState.isOnline {
                songs = try await container.libraryService.randomSongs(size: 200).map { DisplayableSong(from: $0) }
            } else {
                songs = Array(container.offlineLibrary.snapshot.songs.filter(\.isDownloaded).shuffled().prefix(200))
            }
            guard !songs.isEmpty else { throw MusicIntentError.empty }
            try await container.playerService.play(tracks: songs, startIndex: 0)
        }
    }

    /// Ten random albums, each played in order.
    private func shuffleAlbums() async {
        guard let container, let server = container.serverState.activeServer else { return }
        HapticFeedback.medium.trigger()
        await container.toastService.perform {
            let scope = MusicIntentID.scope(baseURL: server.baseURL, username: server.username)
            let albumIDs: [String] = container.serverState.isOnline
                ? try await container.libraryIndexStore.albums(serverID: server.id).map(\.id)
                : container.offlineLibrary.snapshot.albums.map(\.id)
            let service = MusicIntentService(container: container)
            var songs: [DisplayableSong] = []
            for id in albumIDs.shuffled().prefix(10) {
                let reference = MusicIntentID(scope: scope, kind: .album, resourceID: id)
                songs += (try? await service.songs(id: reference.rawValue)) ?? []
            }
            guard !songs.isEmpty else { throw MusicIntentError.empty }
            try await container.playerService.play(tracks: songs, startIndex: 0)
        }
    }

    // MARK: - Recently section (online = Recently Added, offline = Recently Downloaded)

    @ViewBuilder
    private var recentlySection: some View {
        if isOnline {
            if let vm = viewModel, !vm.recentAlbums.isEmpty || vm.isLoading {
                VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                    Text("Recently Added")
                        .font(.minidiscShelfTitle)
                    if vm.isLoading && vm.recentAlbums.isEmpty {
                        LazyVGrid(columns: recentColumns, spacing: MinidiscSpacing.m) {
                            ForEach(0..<6, id: \.self) { _ in SkeletonAlbumCard() }
                        }
                    } else {
                        LazyVGrid(columns: recentColumns, spacing: MinidiscSpacing.m) {
                            ForEach(vm.recentAlbums) { album in
                                NavigationLink(value: HomeDestination.album(album)) {
                                    HomeAlbumCell(album: album, namespace: recentlyAddedZoomNamespace)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        } else if !recentDownloadedItems.isEmpty {
            VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                Text("Recently Downloaded")
                    .font(.minidiscShelfTitle)
                if recentDownloadedItems.isEmpty {
                    EmptyStateView(
                        systemImage: "arrow.down.circle",
                        title: "No downloads yet",
                        subtitle: "Albums and playlists you download will appear here"
                    )
                } else {
                    LazyVGrid(columns: recentColumns, spacing: MinidiscSpacing.m) {
                        ForEach(recentDownloadedItems) { item in
                            let dest: HomeDestination = item.type == .album
                                ? .albumById(id: item.itemId, name: item.name, subtitle: item.subtitle, coverArtId: item.coverArtId)
                                : .playlistById(id: item.itemId, name: item.name, coverArtId: item.coverArtId)
                            HomeDownloadedItemCard(item: item, destination: dest)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - LibraryTile

/// A rounded tile with an accent symbol on the left and its title on the right.
private struct LibraryTile: View {
    let title: LocalizedStringResource
    let systemImage: String
    var isShuffle = false

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.minidiscAccent)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, MinidiscSpacing.l)
        .frame(maxWidth: .infinity, minHeight: isShuffle ? 56 : 76)
        .background(isShuffle ? Color.minidiscAccent.opacity(0.18) : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - HomePinnedCard

private struct HomePinnedCard: View {
    let item: PinnedItem
    let namespace: Namespace.ID
    @Environment(\.appContainer) private var container
    @Environment(\.modelContext) private var modelContext
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @State private var coverImage: PlatformImage?

    private var homeNavDestination: HomeDestination {
        switch PinnedItemType(rawValue: item.itemType) {
        case .album:
            .albumById(id: item.itemId, name: item.displayName, subtitle: item.displaySubtitle, coverArtId: item.coverArtId)
        case .playlist:
            .playlistById(id: item.itemId, name: item.displayName, coverArtId: item.coverArtId)
        case .none:
            .albumById(id: item.itemId, name: item.displayName, subtitle: item.displaySubtitle, coverArtId: item.coverArtId)
        }
    }

    var body: some View {
        NavigationLink(value: homeNavDestination) {
            VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                GeometryReader { geo in
                    if PinnedItemType(rawValue: item.itemType) == .playlist {
                        PlaylistCoverThumbnail(playlistId: item.itemId, serverId: item.serverId, coverArtId: item.coverArtId ?? item.itemId, title: item.displayName, size: geo.size.width)
                    } else {
                        CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(geo.size.width * 2))
                            .frame(width: geo.size.width, height: geo.size.width)
                            .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.standard)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .minidiscMatchedTransitionSource(id: item.itemId, in: namespace)
                CoverCardMetadata(
                    title: item.displayName,
                    subtitle: item.displaySubtitle.isEmpty ? nil : item.displaySubtitle
                )
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            Task { coverImage = await artworkImageCache.load(coverArtId: item.coverArtId ?? item.itemId) }
        }
        .lazyCollectionContextMenu(
            itemType: PinnedItemType(rawValue: item.itemType) ?? .album,
            itemId: item.itemId,
            displayName: item.displayName,
            displaySubtitle: item.displaySubtitle,
            coverArtId: item.coverArtId,
            coverImage: coverImage,
            favoriteType: item.itemType == PinnedItemType.album.rawValue ? .album : nil
        ) {
            let itemId = item.itemId
            if let container, !container.serverState.isOnline {
                let local = container.offlineLibrary.snapshot
                switch PinnedItemType(rawValue: item.itemType) {
                case .album: return local.albumSongs(itemId)
                case .playlist: return local.playlistSongs[itemId] ?? []
                case .none: return []
                }
            }
            switch PinnedItemType(rawValue: item.itemType) {
            case .album:
                if container?.serverState.isOnline == true,
                   let detail = try? await container?.libraryService.album(id: itemId) {
                    return detail.song?.map { DisplayableSong(from: $0) } ?? []
                }
                let tracks = (try? modelContext.fetch(
                    FetchDescriptor<DownloadedTrack>(
                        predicate: #Predicate { $0.albumId == itemId }
                    )
                )) ?? []
                return tracks
                    .sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                    .map { DisplayableSong(from: $0) }
            case .playlist:
                if container?.serverState.isOnline == true,
                   let detail = try? await container?.libraryService.playlist(id: itemId) {
                    return (detail.entry ?? []).map { DisplayableSong(from: $0) }
                }
                let playlists = (try? modelContext.fetch(
                    FetchDescriptor<DownloadedPlaylist>(
                        predicate: #Predicate { $0.playlistId == itemId }
                    )
                )) ?? []
                let songIds = playlists.first?.songIds ?? []
                let allTracks = (try? modelContext.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
                let trackBySongId = Dictionary(
                    allTracks.map { ($0.songId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                return songIds.compactMap { trackBySongId[$0] }.map { DisplayableSong(from: $0) }
            case .none:
                return []
            }
        }
    }
}

// MARK: - HomeDownloadedItemCard

private struct HomeDownloadedItemCard: View {
    let item: DownloadedItem
    let destination: HomeDestination
    @Environment(\.modelContext) private var modelContext
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?

    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                GeometryReader { geo in
                    if item.type == .playlist {
                        PlaylistCoverThumbnail(playlistId: item.itemId, serverId: nil, coverArtId: item.coverArtId ?? item.itemId, title: item.name, size: geo.size.width)
                    } else {
                        CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(geo.size.width * 2))
                            .frame(width: geo.size.width, height: geo.size.width)
                            .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.standard)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                CoverCardMetadata(
                    title: item.name,
                    subtitle: item.subtitle.isEmpty ? nil : item.subtitle
                )
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            Task { coverImage = await artworkImageCache.load(coverArtId: item.coverArtId ?? item.itemId) }
        }
        .lazyCollectionContextMenu(
            itemType: item.type == .album ? .album : .playlist,
            itemId: item.itemId,
            displayName: item.name,
            displaySubtitle: item.subtitle,
            coverArtId: item.coverArtId,
            coverImage: coverImage,
            favoriteType: item.type == .album ? .album : nil
        ) {
            switch item.type {
            case .album:
                let aid = item.itemId
                let tracks = (try? modelContext.fetch(
                    FetchDescriptor<DownloadedTrack>(
                        predicate: #Predicate { $0.albumId == aid }
                    )
                )) ?? []
                return tracks
                    .sorted { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
                    .map { DisplayableSong(from: $0) }
            case .playlist:
                let pid = item.itemId
                let playlists = (try? modelContext.fetch(
                    FetchDescriptor<DownloadedPlaylist>(
                        predicate: #Predicate { $0.playlistId == pid }
                    )
                )) ?? []
                let songIds = playlists.first?.songIds ?? []
                let allTracks = (try? modelContext.fetch(FetchDescriptor<DownloadedTrack>())) ?? []
                let trackBySongId = Dictionary(
                    allTracks.map { ($0.songId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                return songIds.compactMap { trackBySongId[$0] }.map { DisplayableSong(from: $0) }
            }
        }
    }
}

// MARK: - DownloadedItem

private nonisolated struct DownloadedItem: Identifiable, Sendable {
    nonisolated enum ItemType: Sendable {
        case album
        case playlist
    }
    let id: String
    let itemId: String
    let type: ItemType
    let name: String
    let subtitle: String
    let coverArtId: String?
    let downloadedAt: Date
}

// MARK: - HomeAlbumCell

private struct HomeAlbumCell: View {
    let album: AlbumID3
    let namespace: Namespace.ID

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
            GeometryReader { geo in
                CoverArtView(id: album.coverArt ?? album.id, size: Int(geo.size.width * 2))
                    .frame(width: geo.size.width, height: geo.size.width)
                    .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.standard)
            }
            .aspectRatio(1, contentMode: .fit)
            .minidiscMatchedTransitionSource(id: album.id, in: namespace)
            CoverCardMetadata(title: album.name, subtitle: album.artist)
        }
        .task(id: album.id) {
            coverImage = await artworkImageCache.load(coverArtId: album.coverArt ?? album.id)
        }
        .lazyCollectionContextMenu(
            itemType: .album,
            itemId: album.id,
            displayName: album.name,
            displaySubtitle: album.artist ?? "",
            coverArtId: album.coverArt,
            coverImage: coverImage,
            favoriteType: .album
        ) {
            let detail = try await container?.libraryService.album(id: album.id)
            return (detail?.song ?? []).map { DisplayableSong(from: $0) }
        }
    }
}
