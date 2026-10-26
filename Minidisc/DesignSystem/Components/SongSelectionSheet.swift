import SwiftUI

struct SongSelectionRequest: Identifiable {
    let id = UUID()
    let songs: [DisplayableSong]
}

/// A fixed collection snapshot keeps a refresh from changing what a multi-selection means.
/// Filtering never clears the selection; commit follows the collection's displayed order.
struct SongSelectionSheet: View {
    let request: SongSelectionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []
    @State private var query = ""
    @State private var addition: PlaylistAdditionRequest?
    /// A selection can hold the whole Songs tab, so the list is derived once per request and query
    /// rather than three times per body (every tap re-runs the body).
    @State private var collection = DerivedValueCache<UUID, SongSelectionCollection>()
    @State private var filtered = DerivedValueCache<FilterKey, SongSelectionCollection.Filtered>()

    private struct FilterKey: Equatable {
        let request: UUID
        let query: String
    }

    private var songs: [DisplayableSong] {
        collection.value(for: request.id) { SongSelectionCollection(request.songs) }.songs
    }

    private var visible: SongSelectionCollection.Filtered {
        let query = LibrarySearchRanking.normalized(query)
        return filtered.value(for: FilterKey(request: request.id, query: query)) {
            collection.value(for: request.id) { SongSelectionCollection(request.songs) }.filtered(by: query)
        }
    }

    var body: some View {
        let visible = visible
        let visibleSongs = visible.songs
        NavigationStack {
            List {
                Section {
                    Button {
                        if selectedIDs.isSuperset(of: visible.ids) { selectedIDs.subtract(visible.ids) }
                        else { selectedIDs.formUnion(visible.ids) }
                    } label: {
                        Text(selectedIDs.isSuperset(of: visible.ids)
                             ? LocalizedStringResource("Deselect All") : LocalizedStringResource("Select All"))
                    }
                    .disabled(visibleSongs.isEmpty)
                    .accessibilityIdentifier("songs.selection.all")
                } footer: { Text("\(selectedIDs.count) songs selected") }
                ForEach(visibleSongs) { song in
                    Button {
                        if !selectedIDs.insert(song.id).inserted { selectedIDs.remove(song.id) }
                        HapticFeedback.selection.trigger()
                    } label: {
                        SongSelectionRow(song: song, selected: selectedIDs.contains(song.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("songs.selection.\(song.id)")
                    .accessibilityAddTraits(selectedIDs.contains(song.id) ? .isSelected : [])
                }
            }
            .minidiscSheetListStyle()
            .searchable(text: $query, prompt: "Find a song")
            .navigationTitle("Select Songs")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Playlist", systemImage: "music.note.list") {
                        addition = PlaylistAdditionRequest(songs: songs.filter { selectedIDs.contains($0.id) })
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityIdentifier("songs.selection.add")
                }
            }
        }
        .sheet(item: $addition) { request in
            AddToPlaylistSheet(request: request, onAdded: { dismiss() })
        }
    }
}

/// The songs a selection sheet offers: the request's songs without repeats, and their filtered views.
/// Each song's search text is normalised the first time a query needs it, then reused.
@MainActor
final class SongSelectionCollection {
    struct Filtered {
        let songs: [DisplayableSong]
        let ids: Set<String>
    }

    let songs: [DisplayableSong]
    private var searchText: [String]?

    init(_ songs: [DisplayableSong]) {
        var seen: Set<String> = []
        self.songs = songs.filter { seen.insert($0.id).inserted }
    }

    /// The songs whose title and artist contain `query`, which must already be normalised.
    func filtered(by query: String) -> Filtered {
        guard !query.isEmpty else { return Filtered(songs: songs, ids: Set(songs.map(\.id))) }
        let text = searchText ?? songs.map { LibrarySearchRanking.normalized("\($0.title) \($0.artist ?? "")") }
        searchText = text
        let matches = zip(songs, text).filter { $0.1.contains(query) }.map(\.0)
        return Filtered(songs: matches, ids: Set(matches.map(\.id)))
    }
}

private struct SongSelectionRow: View {
    let song: DisplayableSong
    let selected: Bool

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.minidiscAccent : .secondary)
                .accessibilityHidden(true)
            CoverArtView(id: song.coverArtId ?? song.id, size: 88)
                .frame(width: 44, height: 44)
                .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.xs)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.minidiscCellTitle).lineLimit(2)
                if let artist = song.artist {
                    Text(artist).font(.minidiscCellSubtitle).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MinidiscSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
