import SwiftUI

/// Wrapped: the yearly Wrapped playlists and this year's monthly recaps, as on the iPhone, and the
/// listening stats.
struct MacWrappedView: View {
    let container: AppContainer

    @Environment(MacInterface.self) private var interface
    @State private var playlists: [WrappedYearlyPlaylist] = []
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 170), spacing: 20, alignment: .top)]

    private var visiblePlaylists: [WrappedYearlyPlaylist] {
        container.serverState.isOnline ? playlists : WrappedYearlyPlaylist.saved(in: container.offlineLibrary.snapshot.playlists)
    }

    var body: some View {
        Group {
            if isLoading, container.serverState.isOnline {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(WrappedCarouselItem.pageItems(yearly: visiblePlaylists)) { item in
                                MacWrappedCard(item: item)
                            }
                        }
                        NavigationLink(value: MacDestination.wrappedRecap(.currentMonth())) {
                            HStack(spacing: 12) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.minidiscAccent)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("View Listening Stats")
                                        .font(.headline)
                                    Text("Monthly and annual breakdowns")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.forward")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(14)
                            .frame(maxWidth: 520, alignment: .leading)
                            .background(Color.minidiscAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Wrapped")
        .task(id: container.serverState.accessSnapshot) {
            guard container.serverState.isOnline, let serverID = container.serverState.activeServer?.id.uuidString else {
                isLoading = false
                return
            }
            // Discover has usually fetched them already.
            if let cached = interface.discover(for: container)?.yearlyPlaylists, !cached.isEmpty {
                playlists = cached
                isLoading = false
            }
            playlists = await container.wrappedPlaylistService.fetchYearlyPlaylists(serverId: serverID)
            isLoading = false
        }
    }
}

/// A month's or a year's listening, from the plays recorded on this device: minutes listened,
/// then the top artists, songs and albums. The picker in the toolbar chooses the period.
struct MacWrappedRecapView: View {
    let container: AppContainer

    @State private var period: WrappedPeriod
    @State private var data: WrappedData?
    @State private var isLoading = true

    init(container: AppContainer, period: WrappedPeriod) {
        self.container = container
        _period = State(initialValue: period)
    }

    /// This year's months so far, then the whole year.
    private var periods: [WrappedPeriod] {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        var periods: [WrappedPeriod] = (1...month).map { .month(year: year, month: $0) }
        periods.append(.year(year))
        if !periods.contains(period) { periods.append(period) }
        return periods
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data, data.totalTracksPlayed > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        MacWrappedHero(data: data)
                        HStack(alignment: .top, spacing: 28) {
                            topArtists(data)
                            topTracks(data)
                        }
                        topAlbums(data)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView {
                    Label("No listens for this period.", systemImage: "waveform")
                } description: {
                    Text("Listen up — we'll keep track of your activity.")
                }
            }
        }
        .navigationTitle(Text(verbatim: label(for: period)))
        .toolbar {
            ToolbarItem {
                Picker("Period", selection: $period) {
                    ForEach(periods, id: \.self) { period in
                        Text(verbatim: label(for: period)).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .task(id: period) { await load() }
    }

    private func label(for period: WrappedPeriod) -> String {
        switch period {
        case .year(let year):
            String(year)
        case .month(let year, let month):
            Calendar.current.date(from: DateComponents(year: year, month: month))?
                .formatted(.dateTime.month(.wide).year()) ?? period.displayName
        }
    }

    private func load() async {
        guard let serverID = container.serverState.activeServer?.id.uuidString else {
            isLoading = false
            return
        }
        isLoading = true
        let result = await container.statsService.wrappedData(for: period, serverId: serverID, calendar: .current)
        guard !Task.isCancelled else { return }
        data = result
        isLoading = false
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rank(_ rank: Int) -> some View {
        Text(verbatim: "\(rank)")
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(rank <= 3 ? Color.minidiscTextAccent : .secondary)
            .frame(width: 24, alignment: .trailing)
    }

    private func topArtists(_ data: WrappedData) -> some View {
        section("Top Artists") {
            ForEach(data.topArtists.prefix(5)) { artist in
                NavigationLink(value: MacDestination.artist(id: artist.artistId, name: artist.name)) {
                    HStack(spacing: 10) {
                        rank(artist.rank)
                        CoverArtView(id: artist.artistId, size: 80, placeholderSystemImage: "music.microphone")
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(artist.name).lineLimit(1)
                            Text(verbatim: artist.playCount.plural("play", "plays"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { MacArtistMenu(artistID: artist.artistId) }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func topTracks(_ data: WrappedData) -> some View {
        section("Top Tracks") {
            ForEach(data.topTracks.prefix(5)) { track in
                HStack(spacing: 10) {
                    rank(track.rank)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title).lineLimit(1)
                        Text(track.artistName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: track.playCount.plural("play", "plays"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 36)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func topAlbums(_ data: WrappedData) -> some View {
        section("Top Albums") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20, alignment: .top)],
                      alignment: .leading, spacing: 20) {
                ForEach(data.topAlbums.prefix(6)) { album in
                    NavigationLink(value: MacDestination.album(id: album.albumId)) {
                        VStack(alignment: .leading, spacing: 4) {
                            CoverArtView(id: album.albumId, size: 360, cornerRadius: 6, placeholderSystemImage: MinidiscSymbol.album)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .topLeading) {
                                    Text(verbatim: "#\(album.rank)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.6), in: Capsule())
                                        .padding(6)
                                }
                            Text(album.title)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(album.artistName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { MacAlbumMenu(albumID: album.albumId, albumName: album.title) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The recap's banner: minutes listened over the year's colours, then plays, artists and albums.
private struct MacWrappedHero: View {
    let data: WrappedData

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let minutes = data.totalSecondsListened.wrappedHeroMinutesFormat()
        let summary = [
            data.totalTracksPlayed.plural("play", "plays"),
            data.totalUniqueArtists.plural("artist", "artists"),
            data.totalUniqueAlbums.plural("album", "albums"),
        ].joined(separator: " · ")
        MeshGradientBackground(palette: WrappedYearPalette.colors(for: data.period.calendarYear), animated: !reduceMotion)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: minutes.number)
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(verbatim: minutes.unit)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                    Text(verbatim: summary)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                        .padding(.top, 4)
                }
                .padding(24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(minutes.number) \(minutes.unit), \(summary)"))
    }
}
