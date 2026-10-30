import SwiftUI
import OSLog

// MARK: - Context menu preview views

struct CollectionContextPreview: View {
    let coverImage: PlatformImage?
    let displayName: String
    let displaySubtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.m) {
            Group {
                if let coverImage {
                    Image(platformImage: coverImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    // An album, playlist or song without a cover: the MiniDisc, as in the lists.
                    MissingCoverDisc(isLarge: true)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxWidth: 280, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !displaySubtitle.isEmpty {
                    Text(displaySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(MinidiscSpacing.l)
        .frame(width: 320)
    }
}

struct SongContextMenuModifier: ViewModifier {
    let song: DisplayableSong

    @Environment(\.appContainer) private var container

    private var isFavorite: Bool {
        container?.favoritesService.isFavorite(itemType: .song, itemId: song.id) == true
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            Group {
            Button {
                Task {
                    do {
                        try await container?.playerService.play(tracks: [song], startIndex: 0)
                    } catch {
                        Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                    }
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                Task { await container?.playerService.playNext(song) }
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                Task { await container?.playerService.addToQueue(song) }
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }

            Button {
                startInstantMix(from: .song(id: song.id), using: container, startingWith: song,
                                context: songMixContext(song))
            } label: {
                Label("Instant Mix", systemImage: instantMixSymbol)
            }

            if !song.isLocalFile, song.albumId != nil || song.artistId != nil {
                Divider()

                if song.albumId != nil, let album = song.albumName, !album.isEmpty {
                    Button {
                        postNavigateToAlbum(track: song)
                    } label: {
                        Label("Go to Album", symbol: MinidiscSymbol.goToAlbum)
                        Text(album)
                    }
                }

                if song.artistId != nil, let artist = song.artist, !artist.isEmpty {
                    Button {
                        postNavigateToArtist(track: song)
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                        Text(artist)
                    }
                }
            }

            Divider()

            Button {
                let fav = isFavorite
                Task {
                    if fav {
                        try? await container?.favoritesService.unstar(itemType: .song, itemId: song.id)
                    } else {
                        try? await container?.favoritesService.star(itemType: .song, itemId: song.id)
                    }
                }
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
            }
            .tint(.primary)
        }
    }
}

// MARK: - Collection context menu (albums and playlists)

/// Pass no songs to hide playback actions. Playlists cannot be starred through Subsonic.
struct CollectionContextMenuModifier: ViewModifier {
    let itemType: PinnedItemType
    let itemId: String
    let displayName: String
    let displaySubtitle: String
    let coverArtId: String?
    let coverImage: PlatformImage?
    let songs: [DisplayableSong]
    let favoriteType: FavoriteType?
    /// The album's artist, for Go to Artist; the subtitle is the artist's name.
    var artistId: String? = nil
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.appContainer) private var container
    @State private var showPinLimitAlert = false

    private var isPinned: Bool {
        container?.pinService.isPinned(itemType: itemType, itemId: itemId) == true
    }

    private var playbackContext: PlaybackContext {
        switch itemType {
        case .album: .album(id: itemId, name: displayName, coverArtId: coverArtId)
        case .playlist: .forPlaylist(id: itemId, name: displayName, coverArtId: coverArtId)
        }
    }

    private var isFavorite: Bool {
        guard let ft = favoriteType else { return false }
        return container?.favoritesService.isFavorite(itemType: ft, itemId: itemId) == true
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Group {
                if !songs.isEmpty {
                    Button {
                        Task {
                            do {
                                try await container?.playerService.play(tracks: songs, startIndex: 0, context: playbackContext)
                            } catch {
                                Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                            }
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }

                    Button {
                        let shuffled = songs.shuffled()
                        Task {
                            do {
                                try await container?.playerService.play(tracks: shuffled, startIndex: 0, context: playbackContext)
                            } catch {
                                Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                            }
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }

                    Button {
                        Task { await container?.playerService.playNext(songs) }
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }

                    Button {
                        Task { await container?.playerService.addToQueue(songs) }
                    } label: {
                        Label("Add to Queue", systemImage: "text.append")
                    }

                    Divider()
                }

                // Instant Mix seeds from the album itself (similarity), so only albums — not playlists.
                if itemType == .album {
                    Button {
                        startInstantMix(from: .album(id: itemId), using: container,
                                        context: .instantMix(seed: .album, id: itemId, name: displayName))
                    } label: {
                        Label("Instant Mix", systemImage: instantMixSymbol)
                    }

                    if let artistId, !displaySubtitle.isEmpty {
                        Button {
                            postNavigateToArtist(artistId: artistId, artistName: displaySubtitle, coverArtId: nil)
                        } label: {
                            Label("Go to Artist", systemImage: "music.mic")
                            Text(displaySubtitle)
                        }
                    }

                    Divider()
                }

                if isPinned {
                    Button {
                        HapticFeedback.light.trigger()
                        container?.pinService.unpin(itemType: itemType, itemId: itemId)
                    } label: {
                        Label("Unpin from Home", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        guard let serverId = container?.serverState.activeServer?.id,
                              let pin = container?.pinService else { return }
                        do {
                            try pin.pin(
                                itemType: itemType, itemId: itemId,
                                displayName: displayName, displaySubtitle: displaySubtitle,
                                coverArtId: coverArtId, serverId: serverId
                            )
                            HapticFeedback.success.trigger()
                            container?.toastService.showConfirmation("Pinned to Home")
                        } catch PinError.limitReached {
                            HapticFeedback.warning.trigger()
                            showPinLimitAlert = true
                        } catch {
                            Logger.pin.error("ItemContextMenus: pin failed — \(error)")
                        }
                    } label: {
                        Label("Pin to Home", systemImage: "pin")
                    }
                }

                if favoriteType != nil {
                    Divider()

                    Button {
                        guard let ft = favoriteType else { return }
                        let fav = isFavorite
                        Task {
                            if fav {
                                try? await container?.favoritesService.unstar(itemType: ft, itemId: itemId)
                            } else {
                                try? await container?.favoritesService.star(itemType: ft, itemId: itemId)
                            }
                        }
                    } label: {
                        Label(
                            isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: isFavorite ? "heart.slash" : "heart"
                        )
                    }
                }

                if onEdit != nil || onDelete != nil {
                    Divider()
                }

                if let onEdit {
                    Button { onEdit() } label: { Label("Edit Playlist", systemImage: "pencil") }
                }

                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: { Label("Delete Playlist", systemImage: "trash") }
                }
                }
                .tint(.primary)
            } preview: {
                CollectionContextPreview(
                    coverImage: coverImage,
                    displayName: displayName,
                    displaySubtitle: displaySubtitle
                )
            }
            .alert("Pin Limit Reached", isPresented: $showPinLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(PinError.limitReached.errorDescription ?? "")
            }
    }
}

// MARK: - Lazy collection context menu (albums without pre-loaded songs)

struct LazyCollectionContextMenuModifier: ViewModifier {
    let itemType: PinnedItemType
    let itemId: String
    let displayName: String
    let displaySubtitle: String
    let coverArtId: String?
    let coverImage: PlatformImage?
    let favoriteType: FavoriteType?
    /// The album's artist, for Go to Artist; the subtitle is the artist's name.
    var artistId: String? = nil
    let songLoader: () async throws -> [DisplayableSong]

    @Environment(\.appContainer) private var container
    @State private var showPinLimitAlert = false

    private var isPinned: Bool {
        container?.pinService.isPinned(itemType: itemType, itemId: itemId) == true
    }

    private var playbackContext: PlaybackContext {
        switch itemType {
        case .album: .album(id: itemId, name: displayName, coverArtId: coverArtId)
        case .playlist: .forPlaylist(id: itemId, name: displayName, coverArtId: coverArtId)
        }
    }

    private var isFavorite: Bool {
        guard let ft = favoriteType else { return false }
        return container?.favoritesService.isFavorite(itemType: ft, itemId: itemId) == true
    }

    private func playableSongs() async throws -> [DisplayableSong] {
        if let container, !container.serverState.isOnline {
            let local = container.offlineLibrary.snapshot
            switch itemType {
            case .album: return local.albumSongs(itemId)
            case .playlist: return local.playlistSongs[itemId] ?? []
            }
        }
        return try await songLoader()
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Group {
                Button {
                    Task {
                        guard let songs = try? await playableSongs(), !songs.isEmpty else { return }
                        do {
                            try await container?.playerService.play(tracks: songs, startIndex: 0, context: playbackContext)
                        } catch {
                            Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                        }
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button {
                    Task {
                        guard let songs = try? await playableSongs(), !songs.isEmpty else { return }
                        do {
                            try await container?.playerService.play(tracks: songs.shuffled(), startIndex: 0, context: playbackContext)
                        } catch {
                            Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                        }
                    }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }

                Button {
                    Task {
                        guard let songs = try? await playableSongs(), !songs.isEmpty else { return }
                        await container?.playerService.playNext(songs)
                    }
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    Task {
                        guard let songs = try? await playableSongs(), !songs.isEmpty else { return }
                        await container?.playerService.addToQueue(songs)
                    }
                } label: {
                    Label("Add to Queue", systemImage: "text.append")
                }

                Divider()

                // Instant Mix seeds from the album itself (similarity), so only albums — not playlists.
                if itemType == .album {
                    Button {
                        startInstantMix(from: .album(id: itemId), using: container,
                                        context: .instantMix(seed: .album, id: itemId, name: displayName))
                    } label: {
                        Label("Instant Mix", systemImage: instantMixSymbol)
                    }

                    if let artistId, !displaySubtitle.isEmpty {
                        Button {
                            postNavigateToArtist(artistId: artistId, artistName: displaySubtitle, coverArtId: nil)
                        } label: {
                            Label("Go to Artist", systemImage: "music.mic")
                            Text(displaySubtitle)
                        }
                    }

                    Divider()
                }

                if isPinned {
                    Button {
                        HapticFeedback.light.trigger()
                        container?.pinService.unpin(itemType: itemType, itemId: itemId)
                    } label: {
                        Label("Unpin from Home", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        guard let serverId = container?.serverState.activeServer?.id,
                              let pin = container?.pinService else { return }
                        do {
                            try pin.pin(
                                itemType: itemType, itemId: itemId,
                                displayName: displayName, displaySubtitle: displaySubtitle,
                                coverArtId: coverArtId, serverId: serverId
                            )
                            HapticFeedback.success.trigger()
                            container?.toastService.showConfirmation("Pinned to Home")
                        } catch PinError.limitReached {
                            HapticFeedback.warning.trigger()
                            showPinLimitAlert = true
                        } catch {
                            Logger.pin.error("ItemContextMenus: pin failed — \(error)")
                        }
                    } label: {
                        Label("Pin to Home", systemImage: "pin")
                    }
                }

                if favoriteType != nil {
                    Divider()

                    Button {
                        guard let ft = favoriteType else { return }
                        let fav = isFavorite
                        Task {
                            if fav {
                                try? await container?.favoritesService.unstar(itemType: ft, itemId: itemId)
                            } else {
                                try? await container?.favoritesService.star(itemType: ft, itemId: itemId)
                            }
                        }
                    } label: {
                        Label(
                            isFavorite ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: isFavorite ? "heart.slash" : "heart"
                        )
                    }
                }
                }
                .tint(.primary)
            } preview: {
                CollectionContextPreview(
                    coverImage: coverImage,
                    displayName: displayName,
                    displaySubtitle: displaySubtitle
                )
            }
            .alert("Pin Limit Reached", isPresented: $showPinLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(PinError.limitReached.errorDescription ?? "")
            }
    }
}

// MARK: - View extensions

extension View {
    func songContextMenu(song: DisplayableSong) -> some View {
        modifier(SongContextMenuModifier(song: song))
    }

    /// - Parameters:
    ///   - coverImage: Pre-loaded image from ArtworkImageCache. Pass nil to show a placeholder.
    ///   - songs: Pre-loaded tracks. Pass `[]` (default) on list rows to hide play actions.
    ///   - favoriteType: Pass `.album` for albums; `nil` for playlists (not supported by Subsonic).
    func collectionContextMenu(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String = "",
        coverArtId: String? = nil,
        coverImage: PlatformImage? = nil,
        songs: [DisplayableSong] = [],
        favoriteType: FavoriteType? = nil,
        artistId: String? = nil,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(CollectionContextMenuModifier(
            itemType: itemType,
            itemId: itemId,
            displayName: displayName,
            displaySubtitle: displaySubtitle,
            coverArtId: coverArtId,
            coverImage: coverImage,
            songs: songs,
            favoriteType: favoriteType,
            artistId: artistId,
            onEdit: onEdit,
            onDelete: onDelete
        ))
    }

    func lazyCollectionContextMenu(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String = "",
        coverArtId: String? = nil,
        coverImage: PlatformImage? = nil,
        favoriteType: FavoriteType? = nil,
        artistId: String? = nil,
        songLoader: @escaping () async throws -> [DisplayableSong]
    ) -> some View {
        modifier(LazyCollectionContextMenuModifier(
            itemType: itemType,
            itemId: itemId,
            displayName: displayName,
            displaySubtitle: displaySubtitle,
            coverArtId: coverArtId,
            coverImage: coverImage,
            favoriteType: favoriteType,
            artistId: artistId,
            songLoader: songLoader
        ))
    }
}
