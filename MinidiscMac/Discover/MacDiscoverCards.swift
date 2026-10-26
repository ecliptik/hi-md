import SwiftSonic
import SwiftUI

/// Discover's Recommended for You entry: opens the AI album suggestions.
struct MacRecommendationsCard: View {
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: MacDestination.recommendations) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.minidiscAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.minidiscAccent.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommended for You")
                        .font(.headline)
                    Text("Albums picked from your listening")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(Color.primary.opacity(isHovering ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// A Fresh Releases cover. Click shows the release and where to find it.
struct MacFreshReleaseCard: View {
    let release: AlbumRecommendation

    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: MacDestination.freshRelease(release)) {
            VStack(alignment: .leading, spacing: 4) {
                ExternalCoverView(url: release.coverArtURL) {
                    Color.secondary.opacity(0.2)
                }
                .frame(width: MacShelfMetrics.albumSide, height: MacShelfMetrics.albumSide)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                Text(release.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(release.artistName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let date = release.releaseDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: MacShelfMetrics.albumSide, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macCardHover($isHovering)
        .accessibilityElement(children: .combine)
    }
}

/// The last card of the Fresh Releases shelf: the past 90 days.
struct MacFreshReleasesSeeAllCard: View {
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: MacDestination.freshReleases) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.minidiscAccent.opacity(isHovering ? 0.14 : 0.08))
                    .frame(width: MacShelfMetrics.albumSide, height: MacShelfMetrics.albumSide)
                    .overlay {
                        Image(systemName: "chevron.forward")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.minidiscTextAccent)
                    }
                Text("See All")
                    .font(.callout.weight(.medium))
                Text("Past 90 days")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macCardHover($isHovering)
        .accessibilityElement(children: .combine)
    }
}

/// "Artist & Similar artists": click plays an Instant Mix of the artist and artists like them,
/// playing from the station.
struct MacStationCard: View {
    let station: ArtistStation
    let isStarting: Bool
    let onPlay: () -> Void

    @State private var isHovering = false

    private var title: String { String(localized: "\(station.artist.name) & Similar artists") }

    /// The iPhone's three gradients, chosen by the artist so a station keeps its colours.
    private var palette: [Color] {
        switch station.id.utf8.reduce(0, { ($0 + Int($1)) % 3 }) {
        case 0: [Color(red: 0.26, green: 0.12, blue: 0.34), Color(red: 0.72, green: 0.30, blue: 0.38)]
        case 1: [Color(red: 0.10, green: 0.24, blue: 0.34), Color(red: 0.18, green: 0.55, blue: 0.62)]
        default: [Color(red: 0.35, green: 0.12, blue: 0.10), Color(red: 0.82, green: 0.25, blue: 0.13)]
        }
    }

    var body: some View {
        let side = MacShelfMetrics.albumSide
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                    CoverArtView(id: station.artist.coverArtId ?? station.artist.id, size: 240,
                                 placeholderSystemImage: "music.microphone")
                        .frame(width: side * 0.68, height: side * 0.68)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    if isStarting {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else if isHovering {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.55), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(8)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(isStarting ? "Preparing…" : "Radio Station")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: side, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .macCardHover($isHovering)
        .contextMenu {
            Button("Play", systemImage: "play", action: onPlay)
                .disabled(isStarting)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isStarting ? Text("Preparing…") : Text("Radio Station"))
        .accessibilityHint("Play an artist station")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPlay() }
    }
}

/// Rediscover Your Library: a new Smart Shuffle mix, with covers from recent listening.
struct MacSmartShuffleCard: View {
    let coverIDs: [String]
    let isStarting: Bool
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Smart Shuffle", systemImage: "shuffle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Rediscover Your Library")
                        .font(.title2.bold())
                    Text("A new mix, every time")
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 8) {
                        if isStarting { ProgressView().controlSize(.small).tint(.white) }
                        Label(isStarting ? LocalizedStringResource("Preparing…") : LocalizedStringResource("Shuffle"),
                              systemImage: "play.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.white.opacity(isHovering ? 0.26 : 0.18), in: Capsule())
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MacShuffleArtwork(coverIDs: coverIDs)
                    .frame(width: 130, height: 132)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.48, green: 0.06, blue: 0.18),
                                                 Color(red: 0.80, green: 0.17, blue: 0.08)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Smart Shuffle")
        .accessibilityHint("Play a new mix from your library")
        .accessibilityValue(isStarting ? Text("Preparing…") : Text(""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPlay() }
    }
}

private struct MacShuffleArtwork: View {
    let coverIDs: [String]

    var body: some View {
        ZStack {
            if coverIDs.isEmpty {
                Image(systemName: "shuffle")
                    .font(.system(size: 56, weight: .bold))
                    .rotationEffect(.degrees(-12))
                    .transition(.opacity)
            } else {
                ForEach(Array(coverIDs.prefix(3).enumerated()), id: \.element) { index, id in
                    CoverArtView(id: id, size: 180)
                        .frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        .rotationEffect(.degrees(Double(index - 1) * 12))
                        .offset(x: CGFloat(index - 1) * 18, y: CGFloat(index - 1) * 20)
                        .transition(.opacity)
                }
            }
        }
        .animation(CoverArtView.arrival, value: coverIDs)
    }
}

/// A mood playlist: its gradient and symbol. Click opens the playlist; the play button on hover
/// plays it, playing from the mood.
struct MacMoodCard: View {
    let mood: MoodPlaylist

    @Environment(MacPlayback.self) private var playback
    @State private var isHovering = false

    var body: some View {
        let side = MacShelfMetrics.albumSide
        let title = String(localized: mood.mood.title)
        NavigationLink(value: MacDestination.playlist(id: mood.id)) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    PlaylistGradientView(spec: mood.mood.gradientSpec)
                    LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.30)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: mood.mood.symbolName)
                        .font(.system(size: side * 0.3, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .drawingGroup()
                .overlay(alignment: .bottomLeading) {
                    if isHovering {
                        MacHoverPlayButton { playback.playPlaylist(id: mood.id) }
                            .padding(8)
                            .transition(.opacity)
                    }
                }
                .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .frame(width: side, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macCardHover($isHovering)
        .contextMenu {
            Button("Play", systemImage: "play") { playback.playPlaylist(id: mood.id) }
            Button("Shuffle", systemImage: "shuffle") { playback.playPlaylist(id: mood.id, shuffled: true) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint("Opens the playlist")
    }
}

/// A Wrapped card: a finished year opens its playlist; this year and its months open the
/// listening recap.
struct MacWrappedCard: View {
    let item: WrappedCarouselItem

    @Environment(MacPlayback.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var year: Int {
        switch item {
        case .yearly(let playlist): playlist.year
        case .currentYear(let year): year
        case .month(let year, _): year
        }
    }

    private var destination: MacDestination {
        switch item {
        case .yearly(let playlist): .playlist(id: playlist.id)
        case .currentYear(let year): .wrappedRecap(.year(year))
        case .month(let year, let month): .wrappedRecap(.month(year: year, month: month))
        }
    }

    private var title: String {
        switch item {
        case .yearly, .currentYear: String(year)
        case .month(let year, let month):
            Calendar.current.date(from: DateComponents(year: year, month: month))?
                .formatted(.dateTime.month(.wide)) ?? String(month)
        }
    }

    private var subtitle: String {
        switch item {
        case .yearly, .currentYear: String(localized: "Wrapped")
        case .month(let year, _): String(year)
        }
    }

    var body: some View {
        let side = MacShelfMetrics.albumSide
        NavigationLink(value: destination) {
            MeshGradientBackground(palette: WrappedYearPalette.colors(for: year), animated: !reduceMotion)
                .frame(width: side, height: side)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title)
                            .font(.system(size: isMonth ? 24 : 40, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(verbatim: subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                            .lineLimit(1)
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .drawingGroup()
                .overlay(alignment: .topTrailing) {
                    if isHovering, case .yearly(let playlist) = item {
                        MacHoverPlayButton { playback.playPlaylist(id: playlist.id) }
                            .padding(8)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macCardHover($isHovering)
        .contextMenu {
            if case .yearly(let playlist) = item {
                Button("Play", systemImage: "play") { playback.playPlaylist(id: playlist.id) }
                Button("Shuffle", systemImage: "shuffle") { playback.playPlaylist(id: playlist.id, shuffled: true) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title), \(subtitle)"))
        .accessibilityAddTraits(.isButton)
    }

    private var isMonth: Bool {
        if case .month = item { true } else { false }
    }
}

/// An internet radio station. Click plays it.
struct MacRadioCard: View {
    let station: InternetRadioStation

    @Environment(MacPlayback.self) private var playback
    @State private var isHovering = false

    var body: some View {
        let side = MacShelfMetrics.albumSide
        Button { playback.playRadio(station) } label: {
            VStack(alignment: .leading, spacing: 4) {
                MacRadioArtwork(station: station, side: side)
                    .overlay(alignment: .bottomLeading) {
                        if isHovering {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.55), in: Circle())
                                .padding(8)
                                .transition(.opacity)
                        }
                    }
                Text(station.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .frame(width: side, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macCardHover($isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Play \(station.name)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { playback.playRadio(station) }
    }
}

/// A station's cover, or the radio gradient when it has none.
struct MacRadioArtwork: View {
    let station: InternetRadioStation
    let side: CGFloat

    var body: some View {
        Group {
            if let coverArt = station.coverArt, !coverArt.isEmpty {
                ZStack {
                    Color.black
                    CoverArtView(id: coverArt, size: Int(side * 2))
                }
            } else {
                LinearGradient(colors: [Color(red: 0.161, green: 0.475, blue: 1.0),
                                        Color(red: 0.000, green: 0.588, blue: 0.533)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: side * 0.3))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side > 80 ? 10 : 6))
        .accessibilityHidden(true)
    }
}
