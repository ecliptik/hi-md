import SwiftSonic
import SwiftUI

/// Library > Artists: every artist in a list, sorted from the toolbar. Click opens the artist.
struct MacArtistsView: View {
    let container: AppContainer
    @State private var viewModel: ArtistListViewModel?
    @AppStorage("minidisc.mac.artistSort") private var sort = LibrarySortOrder<ArtistSortField>(.name)

    var body: some View {
        let artists = viewModel.map { sort.sorted($0.indexes.flatMap(\.artist)) } ?? []
        MacLoadingState(isLoading: viewModel?.isLoading ?? true, isEmpty: artists.isEmpty, error: viewModel?.error,
                        emptyTitle: "No Artists", emptySystemImage: "music.microphone", retry: { await viewModel?.load() }) {
            List(artists) { artist in
                NavigationLink(value: MacDestination.artist(id: artist.id, name: artist.name)) {
                    MacArtistRow(artist: artist)
                }
                .contextMenu { MacArtistMenu(artistID: artist.id) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .navigationTitle("Artists")
        .toolbar {
            ToolbarItem {
                MacSortMenu(order: $sort)
            }
        }
        .task(id: container.serverState.accessSnapshot) {
            let model = viewModel ?? ArtistListViewModel(libraryService: container.libraryService)
            viewModel = model
            await model.load()
        }
    }
}

struct MacArtistRow: View {
    let artist: ArtistID3

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(id: artist.coverArt ?? artist.id, size: 64, cornerRadius: 16, placeholderSystemImage: "music.microphone")
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            Text(artist.name)
                .lineLimit(1)
            Spacer()
            if let count = artist.albumCount {
                Text("\(count) albums")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

struct MacArtistMenu: View {
    let artistID: String

    @Environment(MacPlayback.self) private var playback

    var body: some View {
        Button("Play", systemImage: "play") { playback.playArtist(id: artistID) }
        Button("Shuffle", systemImage: "shuffle") { playback.playArtist(id: artistID, action: .shuffle) }
        Button("Add to Queue", systemImage: "text.append") { playback.playArtist(id: artistID, action: .addToQueue) }
        Divider()
        MacFavoriteMenuItem(itemType: .artist, itemID: artistID)
    }
}

/// An artist: Play and Shuffle for everything by them, their top songs, then their albums and
/// singles as covers.
struct MacArtistDetailView: View {
    let container: AppContainer
    let artistID: String
    let artistName: String

    @Environment(MacPlayback.self) private var playback
    @State private var viewModel: ArtistDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MacLoadingState(isLoading: viewModel.isLoading, isEmpty: viewModel.artist == nil, error: viewModel.error,
                                retry: { await viewModel.load() }) {
                    content(viewModel)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel?.artist?.name ?? artistName)
        .task(id: container.serverState.accessSnapshot) {
            let model = viewModel ?? ArtistDetailViewModel(
                artistId: artistID,
                artistName: artistName,
                libraryService: container.libraryService,
                downloadService: container.downloadService,
                recommendationService: container.recommendationService,
                imageResolver: container.externalArtistImageResolver,
                serverState: container.serverState,
                offlineReader: container.offlineBrowsingReader
            )
            viewModel = model
            await model.load()
            await model.loadTopSongs()
        }
    }

    private func content(_ model: ArtistDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(model)
                if !model.topSongs.isEmpty {
                    section("Top Songs") {
                        MacSongTable(songs: Array(model.topSongs.prefix(10)))
                            .frame(height: CGFloat(min(model.topSongs.count, 10)) * 28 + 48)
                    }
                }
                if !model.albumReleases.isEmpty {
                    section("Albums") { MacAlbumGrid(albums: model.albumReleases, showsArtist: false) }
                }
                if !model.singlesAndEPs.isEmpty {
                    section("Singles & EPs") { MacAlbumGrid(albums: model.singlesAndEPs, showsArtist: false) }
                }
            }
            .padding(20)
        }
    }

    private func header(_ model: ArtistDetailViewModel) -> some View {
        HStack(alignment: .center, spacing: 20) {
            CoverArtView(id: model.artist?.coverArt ?? artistID, size: 320, placeholderSystemImage: "music.microphone")
                .frame(width: 140, height: 140)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 10) {
                Text(model.artist?.name ?? artistName)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Button {
                        play(model, shuffled: false)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppearanceSettings.shared.accent.fillColor)
                    Button {
                        play(model, shuffled: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(.bordered)
                    MacFavoriteButton(itemType: .artist, itemID: artistID)
                }
                .fixedSize()
                .controlSize(.large)
            }
            Spacer(minLength: 0)
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }

    /// Offline, the artist's downloaded songs; online, everything on the server.
    private func play(_ model: ArtistDetailViewModel, shuffled: Bool) {
        if model.isOffline {
            shuffled ? playback.shuffle(model.offlineTracks) : playback.play(model.offlineTracks)
        } else {
            playback.playArtist(id: artistID, action: shuffled ? .shuffle : .play)
        }
    }
}
