import SwiftUI

private enum LocalMusicSort: String, CaseIterable, Equatable {
    case name, recentlyAdded, artist, album, duration

    var title: LocalizedStringKey {
        switch self {
        case .name: "Name"
        case .recentlyAdded: "Recently Added"
        case .artist: "Artist"
        case .album: "Album"
        case .duration: "Duration"
        }
    }
}

struct LocalMusicBrowseView: View {
    let category: LocalMusicCategory
    @Environment(\.appContainer) private var container
    @AppStorage("minidisc.localAlbumGrid") private var albumGrid = false
    @AppStorage("minidisc.localArtistGrid") private var artistGrid = false
    @State private var sort: LocalMusicSort = .name
    @State private var search = ""
    @State private var derivation = DerivedValueCache<DerivationKey, Derivation>()

    private var gridLayout: Bool { category == .albums ? albumGrid : artistGrid }
    private var tracks: [LocalMusicTrack] { container?.localMusic.snapshot.tracks ?? [] }
    private var sortOptions: [LocalMusicSort] {
        switch category {
        case .albums: [.name, .recentlyAdded, .artist]
        case .artists: [.name, .recentlyAdded]
        case .songs: [.name, .recentlyAdded, .artist, .album, .duration]
        }
    }

    private struct DerivationKey: Equatable {
        let tracks: [LocalMusicTrack]
        let category: LocalMusicCategory
        let sort: LocalMusicSort
        let search: String
    }

    private struct Derivation {
        var songs: [LocalMusicTrack] = []
        var groups: [LocalMusicGroup] = []
        var alphabetEntries: [AlphabetScrollEntry] = []
    }

    /// Filtering, sorting and indexing a large library is repeated work for a body that reads the
    /// result several times, so it is redone only when the tracks, sort or search change.
    private var derived: Derivation {
        let key = DerivationKey(tracks: tracks, category: category, sort: sort, search: search)
        return derivation.value(for: key) { Self.derive(key) }
    }

    private var songs: [LocalMusicTrack] { derived.songs }
    private var groups: [LocalMusicGroup] { derived.groups }
    private var alphabetEntries: [AlphabetScrollEntry] { derived.alphabetEntries }

    private static func derive(_ key: DerivationKey) -> Derivation {
        let search = key.search
        let sort = key.sort
        var result = Derivation()
        if key.category == .songs {
            result.songs = key.tracks.filter {
                search.isEmpty || [$0.song.title, $0.song.artist ?? "", $0.song.albumName ?? ""]
                    .contains { $0.localizedStandardContains(search) }
            }.sorted {
                switch sort {
                case .recentlyAdded: return LocalMusicTrack.mostRecentFirst($0, $1)
                case .duration:
                    if $0.song.duration != $1.song.duration { return $0.song.duration > $1.song.duration }
                case .artist, .album:
                    let left = sort == .artist ? $0.song.artist ?? "" : $0.song.albumName ?? ""
                    let right = sort == .artist ? $1.song.artist ?? "" : $1.song.albumName ?? ""
                    let order = left.localizedStandardCompare(right)
                    if order != .orderedSame { return order == .orderedAscending }
                case .name: break
                }
                return $0.song.title.localizedStandardCompare($1.song.title) == .orderedAscending
            }
            let byTitle = sort == .name ? result.songs : result.songs.sorted {
                $0.song.title.localizedStandardCompare($1.song.title) == .orderedAscending
            }
            result.alphabetEntries = byTitle.map { AlphabetScrollEntry(id: $0.id, name: $0.song.title) }
        } else {
            result.groups = LocalMusicGroup.groups(in: key.tracks, category: key.category).filter {
                search.isEmpty || $0.name.localizedStandardContains(search)
                    || (key.category == .albums && $0.tracks.first?.song.artist?.localizedStandardContains(search) == true)
            }.sorted {
                if sort == .recentlyAdded, $0.addedAt != $1.addedAt { return $0.addedAt > $1.addedAt }
                if sort == .artist {
                    let order = ($0.tracks.first?.song.artist ?? "").localizedStandardCompare($1.tracks.first?.song.artist ?? "")
                    if order != .orderedSame { return order == .orderedAscending }
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            let byName = sort == .name ? result.groups : result.groups.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            result.alphabetEntries = byName.map { AlphabetScrollEntry(id: $0.scrollID, name: $0.name) }
        }
        return result
    }

    var body: some View {
        Group {
            if (category == .songs ? songs.isEmpty : groups.isEmpty) {
                if !search.isEmpty { ContentUnavailableView.search(text: search) }
                else {
                    ContentUnavailableView {
                        Label { Text(category.title) } icon: { Image(systemName: "music.note") }
                    } description: {
                        Text("No audio files found. Check your folders in Files, then refresh.", tableName: "LocalMusic")
                    }
                }
            } else {
                AlphabetIndexedContent(entries: alphabetEntries, prepareJump: { sort = .name }) {
                    if category == .songs {
                        List {
                            LocalMusicPlaybackControls(tracks: songs)
                                .listRowSeparator(.hidden)
                            LocalMusicTrackRows(tracks: songs)
                        }
                        .listStyle(.plain)
                        .refreshable { await container?.localMusic.refresh() }
                    } else if gridLayout {
                        ScrollView {
                            LocalMusicGrid(groups: groups, category: category)
                                .padding(MinidiscSpacing.l)
                        }
                        .miniPlayerBottomMargin()
                        .refreshable { await container?.localMusic.refresh() }
                    } else {
                        List(groups) { group in
                            NavigationLink {
                                LocalMusicCollectionView(group: group, category: category)
                            } label: {
                                HStack(spacing: MinidiscSpacing.m) {
                                    LocalMusicArtwork(id: group.artworkID, isArtist: category == .artists)
                                        .frame(width: 56, height: 56)
                                    CoverCardMetadata(title: group.name, subtitle: category == .albums ? group.tracks.first?.song.artist : nil)
                                }
                                .padding(.vertical, MinidiscSpacing.xs)
                            }
                            .id(group.scrollID)
                        }
                        .listStyle(.plain)
                        .refreshable { await container?.localMusic.refresh() }
                    }
                }
            }
        }
        .minidiscContentWidth()
        .navigationTitle(Text(category.title))
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(sortOptions, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down")
                }
                .tint(.primary)
            }
            if category != .songs {
                ToolbarItem(placement: .primaryAction) {
                    Button(gridLayout ? "List view" : "Grid view", systemImage: gridLayout ? "list.bullet" : "square.grid.2x2") {
                        if category == .albums { albumGrid.toggle() }
                        else { artistGrid.toggle() }
                    }
                    .tint(.primary)
                }
            }
        }
    }
}
