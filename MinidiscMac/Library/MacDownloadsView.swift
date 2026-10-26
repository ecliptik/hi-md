import SwiftSonic
import SwiftUI

/// Downloads: transfers in progress, then the albums and playlists saved on this Mac. The toolbar's
/// Offline Mode switch keeps the app to downloaded music even while the server is reachable.
struct MacDownloadsView: View {
    let container: AppContainer

    @Environment(MacPlayback.self) private var playback
    @State private var viewModel: DownloadsViewModel?
    @State private var removal: Removal?

    private enum Removal: Identifiable {
        case album(DownloadedAlbumDisplay)
        case playlist(DownloadedPlaylistDTO)
        case all

        var id: String {
            switch self {
            case .album(let album): "album:\(album.id)"
            case .playlist(let playlist): "playlist:\(playlist.id)"
            case .all: "all"
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20, alignment: .top)]

    var body: some View {
        @Bindable var serverState = container.serverState
        let transfers = container.downloadActivity.transfers
        let albums = viewModel?.displayAlbums ?? []
        let playlists = viewModel?.downloadedPlaylists ?? []
        Group {
            if albums.isEmpty && playlists.isEmpty && transfers.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                       description: Text("Choose Download on an album, playlist or song to listen without a connection."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !transfers.isEmpty {
                            section("Transfers") {
                                VStack(spacing: 0) {
                                    ForEach(transfers, id: \.songId) { transfer in
                                        MacTransferRow(transfer: transfer)
                                        Divider()
                                    }
                                }
                            }
                        }
                        if !albums.isEmpty {
                            section("Albums") {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                    ForEach(albums) { album in
                                        albumTile(album)
                                    }
                                }
                            }
                        }
                        if !playlists.isEmpty {
                            section("Playlists") {
                                VStack(spacing: 0) {
                                    ForEach(playlists) { playlist in
                                        playlistRow(playlist)
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationSubtitle(viewModel.map { String(localized: "\($0.trackCount) songs, \($0.usedBytesFormatted)") } ?? "")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $serverState.isOfflineModeEnabled) {
                    Label("Offline Mode", systemImage: "icloud.slash")
                }
                .help("Only show and play music saved on this device, even when connected to the internet.")
                Button("Remove All Downloads…", systemImage: "trash", role: .destructive) { removal = .all }
                    .disabled(albums.isEmpty && playlists.isEmpty || viewModel?.isClearingAll == true)
            }
        }
        .task(id: container.offlineLibrary.revision) {
            let model = viewModel ?? DownloadsViewModel(modelContainer: container.modelContainer,
                                                        downloadService: container.downloadService,
                                                        serverState: container.serverState,
                                                        toastService: container.toastService)
            viewModel = model
            await model.loadData()
        }
        .confirmationDialog(removalTitle, isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
                            presenting: removal) { removal in
            Button("Remove Download", role: .destructive) { remove(removal) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The music stays in your library on the server.")
        }
    }

    private var removalTitle: LocalizedStringKey {
        switch removal {
        case .album(let album): "Remove the download of \"\(album.name)\"?"
        case .playlist(let playlist): "Remove the download of \"\(playlist.name)\"?"
        case .all, nil: "Remove all downloads from this Mac?"
        }
    }

    private func remove(_ removal: Removal) {
        guard let viewModel else { return }
        Task {
            switch removal {
            case .album(let album): await viewModel.removeAlbum(album)
            case .playlist(let playlist): await viewModel.removePlaylist(playlist)
            case .all: await viewModel.clearAll()
            }
        }
    }

    private func albumTile(_ album: DownloadedAlbumDisplay) -> some View {
        NavigationLink(value: MacDestination.album(id: album.albumId)) {
            VStack(alignment: .leading, spacing: 4) {
                CoverArtView(id: album.coverArtId ?? album.albumId, size: 440, cornerRadius: 6, placeholderSystemImage: "square.stack")
                    .aspectRatio(1, contentMode: .fit)
                Text(album.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Group {
                    if let total = album.totalTracksCount {
                        Text("\(album.downloadedTracksCount)/\(total) tracks")
                    } else {
                        Text("\(album.downloadedTracksCount) tracks")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play", systemImage: "play") { playback.playAlbum(id: album.albumId) }
            Button("Shuffle", systemImage: "shuffle") { playback.playAlbum(id: album.albumId, action: .shuffle) }
            Divider()
            Button("Remove Download", systemImage: "trash", role: .destructive) { removal = .album(album) }
        }
    }

    private func playlistRow(_ playlist: DownloadedPlaylistDTO) -> some View {
        NavigationLink(value: MacDestination.playlist(id: playlist.playlistId)) {
            HStack(spacing: 12) {
                PlaylistCoverThumbnail(playlistId: playlist.playlistId, serverId: playlist.serverId,
                                       coverArtId: playlist.playlistId, title: playlist.name, size: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(playlist.name)
                    .lineLimit(1)
                Spacer()
                Text("\(playlist.tracksCount)/\(playlist.totalTracksCount) tracks")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Download", systemImage: "trash", role: .destructive) { removal = .playlist(playlist) }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }
}

/// One song being downloaded, with its progress, Retry when it failed, and Cancel.
private struct MacTransferRow: View {
    let transfer: DownloadProgress
    @Environment(\.appContainer) private var container

    private var status: LocalizedStringResource {
        switch transfer.status {
        case .queued: "Queued"
        case .waiting: "Waiting for connection…"
        case .processing: "Finishing download…"
        case .downloading: "Downloading…"
        case .failed: "Download failed"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.title ?? String(localized: "Song"))
                    .lineLimit(1)
                if let error = transfer.error {
                    Text(error.displayMessage).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if transfer.totalBytes != nil, transfer.status == .downloading {
                ProgressView(value: transfer.progress)
                    .frame(width: 120)
                    .accessibilityLabel("Download progress")
            }
            if transfer.status == .failed {
                Button("Retry", systemImage: "arrow.clockwise") {
                    Task { await container?.toastService.perform {
                        try await container?.downloadService.retryDownload(songId: transfer.songId, serverId: transfer.serverId)
                    } }
                }
                .labelStyle(.iconOnly)
            }
            Button("Cancel Download", systemImage: "xmark.circle.fill") {
                Task { await container?.toastService.perform {
                    try await container?.downloadService.cancelDownload(songId: transfer.songId, serverId: transfer.serverId)
                } }
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
    }
}
