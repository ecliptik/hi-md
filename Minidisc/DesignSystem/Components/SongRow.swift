import SwiftUI

nonisolated enum SongRowTrailingAccessory: Sendable, Equatable {
    case duration
    case menu
}

/// Standard track cell for album and playlist detail screens.
///
/// - `showCoverArt`: show a 44pt thumbnail (useful in playlist context where tracks
///   may come from different albums). Default `false` for album tracks.
struct SongRow: View {
    let song: DisplayableSong
    let index: Int
    var showCoverArt: Bool = false
    var showArtist: Bool = true
    var secondaryText: String? = nil
    var coverArtSize: CGFloat = 44
    var coverArtCornerRadius: CGFloat = MinidiscCornerRadius.standard
    var primaryContentSpacing: CGFloat = MinidiscSpacing.s
    var isFavorite: Bool = false
    var titleColor: Color = .primary
    var secondaryColor: Color = .secondary
    var trailingAccessory: SongRowTrailingAccessory = .duration
    /// Numbers tracks as disc.track ("2.4"), for albums with more than one disc.
    var showsDiscNumber: Bool = false
    var menuAccessibilityIdentifier: String = ""
    let onDownload: (() -> Void)?
    let onRemoveDownload: (() -> Void)?
    var isDownloading: Bool = false
    var onRemoveFromPlaylist: (() -> Void)? = nil
    var onAddToPlaylist: ((DisplayableSong) -> Void)? = nil
    var onGoToAlbum: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @Environment(\.appContainer) private var container
    @Environment(\.minidiscPlayingAccent) private var playingAccent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var menuSymbolSize: CGFloat = 17
    @State private var shareRequest: DisplayableSong?
    @State private var preparedShare: PreparedTrackShare?
    @State private var trackInformation: DisplayableSong?

    init(song: DisplayableSong, index: Int, showCoverArt: Bool = false, showArtist: Bool = true, secondaryText: String? = nil, coverArtSize: CGFloat = 44, coverArtCornerRadius: CGFloat = MinidiscCornerRadius.standard, primaryContentSpacing: CGFloat = MinidiscSpacing.s, isFavorite: Bool = false, titleColor: Color = .primary, secondaryColor: Color = .secondary, trailingAccessory: SongRowTrailingAccessory = .duration, menuAccessibilityIdentifier: String = "", onDownload: (() -> Void)? = nil, onRemoveDownload: (() -> Void)? = nil, isDownloading: Bool = false, onRemoveFromPlaylist: (() -> Void)? = nil, onAddToPlaylist: ((DisplayableSong) -> Void)? = nil, onGoToAlbum: (() -> Void)? = nil, onTap: (() -> Void)? = nil, showsDiscNumber: Bool = false) {
        self.showsDiscNumber = showsDiscNumber
        self.song = song
        self.index = index
        self.showCoverArt = showCoverArt
        self.showArtist = showArtist
        self.secondaryText = secondaryText
        self.coverArtSize = coverArtSize
        self.coverArtCornerRadius = coverArtCornerRadius
        self.primaryContentSpacing = primaryContentSpacing
        self.isFavorite = isFavorite
        self.titleColor = titleColor
        self.secondaryColor = secondaryColor
        self.trailingAccessory = trailingAccessory
        self.menuAccessibilityIdentifier = menuAccessibilityIdentifier
        self.onDownload = onDownload
        self.onRemoveDownload = onRemoveDownload
        self.isDownloading = isDownloading
        self.onRemoveFromPlaylist = onRemoveFromPlaylist
        self.onAddToPlaylist = onAddToPlaylist
        self.onGoToAlbum = onGoToAlbum
        self.onTap = onTap
    }

    private var numberLabel: String {
        let track = song.trackNumber ?? index
        guard showsDiscNumber, let disc = song.discNumber else { return "\(track)" }
        return "\(disc).\(track)"
    }

    private var textLineLimit: Int {
        trailingAccessory == .menu && dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }

    private var isCurrentTrack: Bool { container?.playerState.currentTrack?.id == song.id }
    private var isPlaying: Bool { container?.playerState.playbackState == .playing }
    private var actions: SongActions {
        SongActions(
            song: song,
            isFavorite: isFavorite,
            isDownloading: isDownloading,
            onDownload: onDownload,
            onRemoveDownload: onRemoveDownload,
            onRemoveFromPlaylist: onRemoveFromPlaylist,
            onAddToPlaylist: onAddToPlaylist,
            onShare: { shareRequest = song },
            // Rows that show artwork aren't inside their album, so they can go to it; rows that
            // show the artist name can go to the artist.
            onGoToAlbum: onGoToAlbum ?? (showCoverArt && !song.isLocalFile ? { [song] in postNavigateToAlbum(track: song) } : nil),
            onGoToArtist: showArtist ? { [song] in postNavigateToArtist(track: song) } : nil,
            onGetInfo: { trackInformation = song }
        )
    }

    var body: some View {
        HStack(spacing: MinidiscSpacing.s) {
            if let onTap {
                Button(action: onTap) {
                    primaryContent
                }
                .buttonStyle(.plain)
            } else {
                primaryContent
            }

            trailingContent
        }
        .padding(.vertical, trailingAccessory == .menu ? 0 : MinidiscSpacing.s)
        .contentShape(Rectangle())
        .task(id: shareRequest?.id) {
            await prepareRequestedShare()
        }
        .sheet(item: $preparedShare) { share in
            shareSheet(for: share)
        }
        .sheet(item: $trackInformation) { track in
            TrackInformationSheet(track: track)
        }
        // No artwork preview: iOS lifts the row itself, as Music does, leaving room for the menu.
        .contextMenu {
            actions
        }
        .modifier(SongQuickActions(song: song, onAddToPlaylist: onAddToPlaylist))
    }

    private var primaryContent: some View {
        HStack(spacing: primaryContentSpacing) {
            if showCoverArt {
                CoverArtCard(
                    id: song.coverArtId ?? song.id,
                    size: coverArtSize,
                    cornerRadius: coverArtCornerRadius
                )
                    .overlay {
                        if isCurrentTrack {
                            // White bars over a 50% scrim keep 4:1 on a white cover; accent bars
                            // over the 45% scrim were 1.4:1.
                            ZStack {
                                Color.black.opacity(0.5)
                                NowPlayingBarsIndicator(isPlaying: isPlaying)
                                    .environment(\.minidiscPlayingAccent, .white)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: coverArtCornerRadius))
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isFavorite {
                            // A dark disc under the heart, so it shows on any cover (it vanished on
                            // gold artwork): the accent's dark text shade keeps 4.2:1 or more on it.
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.minidiscTextAccent)
                                .padding(2)
                                .background(Color.black.opacity(0.7), in: Circle())
                                .environment(\.colorScheme, .dark)
                                .padding(2)
                        }
                    }
            } else {
                ZStack {
                    if isCurrentTrack {
                        NowPlayingBarsIndicator(isPlaying: isPlaying)
                    } else {
                        Text(verbatim: numberLabel)
                            .font(.minidiscCellSubtitle)
                            .foregroundStyle(secondaryColor)
                    }
                }
                .frame(width: showsDiscNumber ? 36 : 28, height: 44, alignment: .center)
                .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(song.title)
                        .font(.minidiscBody)
                        .foregroundStyle(isCurrentTrack ? playingAccent : titleColor)
                        .lineLimit(textLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                    // After the title, as in Music, so the track number keeps its place. Rows
                    // with artwork mark the cover instead.
                    if isFavorite, !showCoverArt {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(playingAccent)
                            .layoutPriority(1)
                    }
                }
                if let secondaryText = secondaryText ?? (showArtist ? song.artist : nil) {
                    Text(secondaryText)
                        .font(.minidiscCellSubtitle)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(textLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.title)
        .accessibilityValue(spokenDetails)
        .accessibilityAddTraits(isCurrentTrack ? [.isButton, .isSelected] : .isButton)
    }

    /// Everything the row shows beyond the title, in the order a listener needs it.
    private var spokenDetails: String {
        var parts: [String] = []
        if let secondaryText = secondaryText ?? (showArtist ? song.artist : nil) { parts.append(secondaryText) }
        if isCurrentTrack { parts.append(isPlaying ? String(localized: "Now playing") : String(localized: "Paused")) }
        if isFavorite { parts.append(String(localized: "Favorite")) }
        return parts.joined(separator: ", ")
    }

    private var trailingContent: some View {
        HStack(spacing: MinidiscSpacing.s) {
            if song.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.minidiscCaption)
                    .foregroundStyle(secondaryColor)
            } else if isDownloading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
            switch trailingAccessory {
            case .duration:
                if song.duration > 0 {
                    Text(Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.minidiscCaption)
                        .foregroundStyle(secondaryColor)
                        .monospacedDigit()
                }
            case .menu:
                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: min(menuSymbolSize, 22), weight: .semibold))
                        .foregroundStyle(secondaryColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tint(secondaryColor)
                .menuOrder(.fixed)
                .accessibilityLabel("More options")
                .accessibilityIdentifier(menuAccessibilityIdentifier)
            }
        }
    }

    private func prepareRequestedShare() async {
        guard let track = shareRequest else { return }
        let share = await container?.trackSharingService.prepareShare(
            for: track,
            serverIsReachable: container?.serverState.isOnline == true
        )
        guard !Task.isCancelled, shareRequest?.id == track.id else { return }
        shareRequest = nil
        preparedShare = share
    }

    @ViewBuilder
    private func shareSheet(for share: PreparedTrackShare) -> some View {
        switch share {
        case .publicLink(let url):
            SystemShareSheet(item: url)
        case .metadata(let text):
            SystemShareSheet(item: text)
        }
    }
}

private struct SongActions: View {
    let song: DisplayableSong
    let isFavorite: Bool
    let isDownloading: Bool
    let onDownload: (() -> Void)?
    let onRemoveDownload: (() -> Void)?
    let onRemoveFromPlaylist: (() -> Void)?
    let onAddToPlaylist: ((DisplayableSong) -> Void)?
    let onShare: () -> Void
    let onGoToAlbum: (() -> Void)?
    let onGoToArtist: (() -> Void)?
    let onGetInfo: (() -> Void)?

    @Environment(\.appContainer) private var container
    @Environment(PlaylistAddition.self) private var playlistAddition: PlaylistAddition?

    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        Group {
            if !song.isLocalFile {
                ControlGroup {
                    if song.isDownloaded {
                        Button("Downloaded", systemImage: "arrow.down.circle.fill") { }
                            .disabled(true)
                    } else if isDownloading {
                        Button("Downloading…", systemImage: "arrow.down.circle.fill") { }
                            .disabled(true)
                    } else {
                        Button("Download", systemImage: "arrow.down.circle.fill") {
                            onDownload?()
                        }
                        .disabled(onDownload == nil)
                    }

                    Button("Share", systemImage: "square.and.arrow.up.fill", action: onShare)

                    if isFavorite {
                        Button("Undo", systemImage: "heart.slash.fill") {
                            toggleFavorite()
                        }
                        .disabled(!isOnline)
                    } else {
                        Button("Favorite", systemImage: "heart.fill") {
                            toggleFavorite()
                        }
                        .disabled(!isOnline)
                    }
                }

                Section {
                    Button {
                        if let onAddToPlaylist { onAddToPlaylist(song) }
                        else { playlistAddition?.present(song) }
                    } label: {
                        Label("Add to Playlist...", systemImage: "music.note.list")
                    }
                    .disabled(!isOnline || (onAddToPlaylist == nil && playlistAddition == nil))
                }
            }

            Section {
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
            }

            if onGoToAlbum != nil || onGoToArtist != nil || onGetInfo != nil {
                Section {
                    if let onGoToAlbum,
                       song.albumId != nil,
                       let albumName = song.albumName,
                       !albumName.isEmpty {
                        Button(action: onGoToAlbum) {
                            Label("Go to Album", symbol: MinidiscSymbol.goToAlbum)
                            Text(albumName)
                        }
                        .disabled(!isOnline)
                    }

                    if let onGoToArtist,
                       !song.isLocalFile,
                       song.artistId != nil,
                       let artist = song.artist,
                       !artist.isEmpty {
                        Button(action: onGoToArtist) {
                            Label("Go to Artist", systemImage: "music.mic")
                            Text(artist)
                        }
                        .disabled(!isOnline)
                    }

                    if let onGetInfo {
                        Button("Get Info", systemImage: "info.circle.fill", action: onGetInfo)
                    }
                }
            }

            if !song.isLocalFile {
                Section {
                    Button {
                        startInstantMix(from: .song(id: song.id), using: container, startingWith: song,
                                        context: songMixContext(song))
                    } label: {
                        Label("Instant Mix", systemImage: instantMixSymbol)
                    }
                }
            }

            if onRemoveFromPlaylist != nil || (song.isDownloaded && onRemoveDownload != nil) {
                Section {
                    if let onRemoveFromPlaylist {
                        Button(role: .destructive, action: onRemoveFromPlaylist) {
                            Label("Remove from Playlist", systemImage: "minus.circle")
                        }
                    }

                    if song.isDownloaded, let onRemoveDownload {
                        Button(role: .destructive, action: onRemoveDownload) {
                            Label("Remove Download", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .tint(.primary)
    }

    private func toggleFavorite() {
        HapticFeedback.light.trigger()
        Task {
            if isFavorite {
                try? await container?.favoritesService.unstar(itemType: .song, itemId: song.id)
            } else {
                try? await container?.favoritesService.star(itemType: .song, itemId: song.id)
            }
        }
    }
}
