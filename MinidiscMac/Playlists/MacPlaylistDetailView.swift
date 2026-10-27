import SwiftSonic
import SwiftUI

/// A playlist: its cover and name above the track list. Drag rows to reorder them, press Delete to
/// remove them, or drop songs from anywhere in the window to add them.
struct MacPlaylistDetailView: View {
    let container: AppContainer
    let playlistID: String

    @Environment(MacPlayback.self) private var playback
    @Environment(MacPlaylists.self) private var playlists
    @State private var viewModel: PlaylistDetailViewModel?
    @AppStorage("minidisc.mac.playlistSort") private var sort = LibrarySortOrder<SongSortField>(.position)

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isRemovedFromServer && viewModel.songs.isEmpty {
                    ContentUnavailableView("This playlist was deleted", systemImage: "music.note.list")
                } else {
                    MacLoadingState(isLoading: viewModel.isLoading, isEmpty: viewModel.songs.isEmpty && viewModel.name.isEmpty,
                                    error: viewModel.error, retry: { await viewModel.load() }) {
                        VStack(spacing: 0) {
                            header(viewModel)
                            if viewModel.songs.isEmpty {
                                ContentUnavailableView("No Songs", systemImage: "music.note",
                                                       description: Text("Drag songs here to add them."))
                                    .dropDestination(for: MacSongDrag.self) { items, _ in
                                        add(items.map(\.song), model: viewModel)
                                        return true
                                    }
                            } else {
                                MacSongTable(songs: viewModel.songs, style: .playlist, editing: editing(viewModel), sort: $sort)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel?.name ?? playlists.playlist(id: playlistID)?.name ?? "")
        .toolbar {
            ToolbarItem {
                MacSortMenu(order: $sort)
            }
        }
        .task(id: container.serverState.accessSnapshot) {
            let model = viewModel ?? PlaylistDetailViewModel(
                playlistId: playlistID,
                libraryService: container.libraryService,
                downloadService: container.downloadService,
                playlistService: container.playlistService,
                toastService: container.toastService,
                serverState: container.serverState,
                offlineReader: container.offlineBrowsingReader
            )
            viewModel = model
            await model.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscPlaylistsChanged)) { _ in
            Task { await viewModel?.load() }
        }
    }

    /// Only the owner can change a playlist, and only while the server is reachable.
    private func canEdit(_ model: PlaylistDetailViewModel) -> Bool {
        guard container.serverState.isOnline, !model.isOffline else { return false }
        guard let owner = model.owner, let user = container.serverState.activeServer?.username else { return true }
        return owner == user
    }

    private func editing(_ model: PlaylistDetailViewModel) -> MacSongTable.PlaylistEditing? {
        guard canEdit(model) else { return nil }
        return MacSongTable.PlaylistEditing(
            playlistID: playlistID,
            // The table's rows carry their stored positions (sorted or not, a song held twice is
            // two positions), so these are the server's indexes; one request removes them all.
            remove: { positions in
                Task { await model.removeTracks(at: Array(positions)) }
            },
            move: { positions, destination in
                Task { await model.moveTracks(from: positions, to: destination) }
            },
            add: { songs in add(songs, model: model) }
        )
    }

    private func add(_ songs: [DisplayableSong], model: PlaylistDetailViewModel) {
        guard let playlist = playlists.playlist(id: playlistID) else { return }
        playlists.add(songs, to: playlist)
    }

    private func header(_ model: PlaylistDetailViewModel) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            PlaylistCoverThumbnail(playlistId: playlistID, serverId: container.serverState.activeServer?.id,
                                   coverArtId: model.coverArtId ?? playlistID, title: model.name, size: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.name)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                if let owner = model.owner {
                    Text(owner)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text(details(model))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { playback.play(await model.playbackSongs(from: sort.sorted(model.songs))) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppearanceSettings.shared.accent.fillColor)

                    Button {
                        Task { playback.shuffle(await model.playbackSongs(from: model.songs)) }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(.bordered)

                    if model.isDownloadingPlaylist {
                        Button {
                            Task { await model.cancelPlaylistDownload() }
                        } label: {
                            Label("Cancel Download", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                    } else if !model.songs.allSatisfy(\.isDownloaded) {
                        Button {
                            Task { await model.downloadPlaylist() }
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isOffline)
                    }

                    if let playlist = playlists.playlist(id: playlistID), canEdit(model) {
                        Menu {
                            Button("Rename…") { playlists.renaming = playlist }
                            Divider()
                            Button("Delete Playlist…", role: .destructive) { playlists.deleting = playlist }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                                .labelStyle(.iconOnly)
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
                .controlSize(.large)
                .disabled(model.songs.isEmpty && model.isOffline)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func details(_ model: PlaylistDetailViewModel) -> String {
        let total = model.songs.reduce(0) { $0 + $1.duration }
        let length = Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return String(localized: "\(model.songs.count) songs, \(length)")
    }
}
