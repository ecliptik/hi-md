import SwiftSonic
import SwiftUI

/// An album: its cover, title, artist and year above the track list, with Play and Shuffle.
struct MacAlbumDetailView: View {
    let container: AppContainer
    let albumID: String
    var highlightedSongID: String?

    @Environment(MacPlayback.self) private var playback
    @Environment(MacNavigator.self) private var navigator
    @State private var viewModel: AlbumDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MacLoadingState(isLoading: viewModel.isLoading, isEmpty: viewModel.songs.isEmpty, error: viewModel.error,
                                emptyTitle: "No Songs", retry: { await viewModel.load() }) {
                    VStack(spacing: 0) {
                        header(viewModel)
                        MacSongTable(songs: viewModel.songs, style: .album, highlightedSongID: highlightedSongID)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel?.albumName ?? "")
        .task(id: TaskKey(albumID: albumID, access: container.serverState.accessSnapshot)) {
            let model = viewModel ?? AlbumDetailViewModel(
                albumId: albumID,
                libraryService: container.libraryService,
                downloadService: container.downloadService,
                toastService: container.toastService,
                serverState: container.serverState,
                offlineFavorites: container.offlineFavoritesStore
            )
            viewModel = model
            await model.load()
        }
    }

    private struct TaskKey: Equatable {
        let albumID: String
        let access: ServerAccessSnapshot
    }

    private func header(_ model: AlbumDetailViewModel) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            CoverArtView(id: model.coverArtId ?? albumID, size: 480, cornerRadius: 8, placeholderSystemImage: MinidiscSymbol.album)
                .frame(width: 200, height: 200)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.albumName)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let artist = model.artistName {
                    Button(artist) {
                        if let artistID = model.artistId { navigator.show(.artist(id: artistID, name: artist)) }
                    }
                    .buttonStyle(.plain)
                    .font(.title2)
                    .foregroundStyle(Color.minidiscAccent)
                    .disabled(model.artistId == nil)
                }
                Text(details(model))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                // Narrow windows drop the Play and Shuffle words so the row never clips.
                ViewThatFits(in: .horizontal) {
                    actions(model, compact: false)
                    actions(model, compact: true)
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    /// Play, Shuffle, Download, the favourite heart and More. Compact shows only their icons.
    private func actions(_ model: AlbumDetailViewModel, compact: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                playback.play(model.songs)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .labelStyle(MacHeaderLabelStyle(compact: compact))
                    .frame(minWidth: compact ? nil : 72)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppearanceSettings.shared.accent.fillColor)
            .macHeaderHelp("Play", compact: compact)

            Button {
                playback.shuffle(model.songs)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .labelStyle(MacHeaderLabelStyle(compact: compact))
                    .frame(minWidth: compact ? nil : 72)
            }
            .buttonStyle(.bordered)
            .macHeaderHelp("Shuffle", compact: compact)

            downloadButton(model, compact: compact)

            MacFavoriteButton(itemType: .album, itemID: albumID)

            Menu {
                MacAlbumMenu(albumID: albumID, artistID: model.artistId, artistName: model.artistName)
                Divider()
                MacAddToPlaylistMenu(songs: model.songs)
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .fixedSize()
    }

    @ViewBuilder
    private func downloadButton(_ model: AlbumDetailViewModel, compact: Bool) -> some View {
        if model.isDownloadingAlbum {
            Button {
                Task { await model.cancelAlbumDownload() }
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
                    .labelStyle(MacHeaderLabelStyle(compact: compact))
            }
            .buttonStyle(.bordered)
            .macHeaderHelp("Cancel Download", compact: compact)
        } else if !model.songs.allSatisfy(\.isDownloaded) {
            Button {
                Task { await model.downloadAlbum() }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .labelStyle(MacHeaderLabelStyle(compact: compact))
            }
            .buttonStyle(.bordered)
            .macHeaderHelp("Download", compact: compact)
            .disabled(model.isOffline)
        }
    }

    /// "Rock · 2019 · 12 songs, 48 min"
    private func details(_ model: AlbumDetailViewModel) -> String {
        var parts: [String] = []
        if let genre = model.genre, !genre.isEmpty { parts.append(genre) }
        if let year = model.year { parts.append(String(year)) }
        let total = model.songs.reduce(0) { $0 + $1.duration }
        let length = Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        parts.append(String(localized: "\(model.songs.count) songs, \(length)"))
        return parts.joined(separator: " · ")
    }
}
