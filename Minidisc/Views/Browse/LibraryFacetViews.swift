import OSLog
import SwiftSonic
import SwiftUI

/// Genres, Track Artists or Composers, from the local library index.
struct LibraryFacetListView: View {
    let kind: LibraryFacetKind
    @Environment(\.appContainer) private var container
    @State private var facets: [LibraryFacet]?
    @State private var filter = ""

    private var title: LocalizedStringResource {
        switch kind {
        case .genre: "Genres"
        case .trackArtist: "Track Artists"
        case .composer: "Composers"
        }
    }

    private var visibleFacets: [LibraryFacet] {
        let all = facets ?? []
        let term = filter.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(term) }
    }

    var body: some View {
        List {
            if facets == nil {
                HStack(spacing: MinidiscSpacing.s) {
                    ProgressView()
                    Text("Loading…").foregroundStyle(.secondary)
                }
            } else if visibleFacets.isEmpty {
                EmptyStateView(systemImage: "music.note.list", title: "Nothing here yet",
                               subtitle: "Your library hasn't synced this information yet.")
                    .listRowSeparator(.hidden)
            }
            ForEach(visibleFacets) { facet in
                NavigationLink(value: facet) {
                    LabeledContent {
                        Text("\(facet.songCount) songs").monospacedDigit()
                    } label: {
                        Text(facet.name).lineLimit(1)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text(title))
        .searchable(text: $filter)
        .navigationDestination(for: LibraryFacet.self) { facet in
            if facet.kind == .trackArtist, facet.hasArtistID {
                ArtistDetailView(artistId: facet.key, artistName: facet.name, coverArtId: nil)
            } else {
                LibraryFacetSongsView(facet: facet)
            }
        }
        .task(id: container?.serverState.activeServer?.id) { await load() }
        .miniPlayerBottomMargin()
    }

    private func load() async {
        guard let container, let serverID = container.serverState.activeServer?.id else { facets = []; return }
        do {
            facets = try await LibraryFacets.load(kind, store: container.libraryIndexStore, serverID: serverID)
        } catch is CancellationError {
        } catch {
            Logger.ui.error("Library \(kind.rawValue, privacy: .public) list failed: \(error, privacy: .public)")
            facets = []
        }
    }
}

/// The songs of one genre or composer, playable as a list.
struct LibraryFacetSongsView: View {
    let facet: LibraryFacet
    @Environment(\.appContainer) private var container
    @Environment(PlaylistAddition.self) private var playlistAddition
    @State private var songs: [DisplayableSong]?

    var body: some View {
        List {
            if let songs {
                HStack(spacing: MinidiscSpacing.m) {
                    Button {
                        play(songs.shuffled())
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.minidiscCellTitle)
                            .foregroundStyle(Color.minidiscAccent)
                            .frame(width: 48, height: 48)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle")
                    PlayMenuButton(songs: songs, fillColor: AppearanceSettings.shared.accent.fillColor, labelColor: .white)
                }
                .disabled(songs.isEmpty)
                .listRowSeparator(.hidden)
                TrackCountRow(count: songs.count, totalDuration: songs.reduce(0) { $0 + $1.duration }, color: .secondary)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index + 1, showCoverArt: true, onAddToPlaylist: playlistAddition.present,
                            onTap: { play(songs, from: index) })
                }
            } else {
                ProgressView()
            }
        }
        .listStyle(.plain)
        .navigationTitle(facet.name)
        .task(id: facet) { await load() }
        .miniPlayerBottomMargin()
    }

    private func load() async {
        guard let container, let serverID = container.serverState.activeServer?.id else { songs = []; return }
        let downloaded = await container.downloadService.downloadedSongIds(serverId: serverID)
        do {
            songs = try await LibraryFacets.songs(of: facet, store: container.libraryIndexStore, serverID: serverID)
                .map { DisplayableSong(from: $0, isDownloaded: downloaded.contains($0.id)) }
        } catch is CancellationError {
        } catch {
            songs = []
        }
    }

    private func play(_ songs: [DisplayableSong], from index: Int = 0) {
        HapticFeedback.medium.trigger()
        Task { await container?.toastService.perform { try await container?.playerService.play(tracks: songs, startIndex: index) } }
    }
}
