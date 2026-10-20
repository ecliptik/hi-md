import OSLog
import SwiftUI

/// A natural-language search, pushed from Search when Apple Intelligence is available.
struct SmartSearchRequest: Hashable {
    let text: String
}

/// The row at the top of Search results that offers to interpret a longer request.
struct SmartSearchRow: View {
    let text: String

    var body: some View {
        NavigationLink(value: SmartSearchRequest(text: text)) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Minidisc")
                        .font(.body.weight(.semibold))
                    Text("“\(text)”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.minidiscAccent)
            }
        }
        .accessibilityHint("Finds songs in your library that match this description.")
    }
}

struct SmartSearchResultsView: View {
    let request: SmartSearchRequest
    @Environment(\.appContainer) private var container
    @Environment(PlaylistAddition.self) private var playlistAddition
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case loaded(SmartSearchResult)
        case failed(String)
    }

    var body: some View {
        List {
            switch phase {
            case .loading:
                HStack(spacing: MinidiscSpacing.s) {
                    ProgressView()
                    Text("Finding songs…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            case .failed(let message):
                EmptyStateView(systemImage: "sparkles", title: "No results", subtitle: LocalizedStringKey(message))
                    .listRowSeparator(.hidden)
            case .loaded(let result):
                results(result)
            }
        }
        .listStyle(.plain)
        .navigationTitle(request.text)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) { await load() }
        .minidiscContentWidth()
    }

    @ViewBuilder
    private func results(_ result: SmartSearchResult) -> some View {
        Text(result.query.summary.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .accessibilityLabel(Text("Filters: \(result.query.summary.joined(separator: ", "))"))
        if result.songs.isEmpty {
            EmptyStateView(systemImage: "music.note", title: "No matching songs",
                           subtitle: "Try fewer details, or sync your library in Settings.")
                .listRowSeparator(.hidden)
        } else {
            HStack(spacing: MinidiscSpacing.m) {
                Button { play(result.songs, startIndex: 0) } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MinidiscSpacing.s)
                }
                Button { play(result.songs.shuffled(), startIndex: 0) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MinidiscSpacing.s)
                }
            }
            .buttonStyle(.bordered)
            .tint(.minidiscAccent)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            ForEach(Array(result.songs.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, index: index + 1, showCoverArt: true, onAddToPlaylist: playlistAddition.present,
                        onTap: { play(result.songs, startIndex: index) })
            }
        }
    }

    private func load() async {
        guard let container else { return }
        phase = .loading
        let service = SmartSearchService(serverState: container.serverState, store: container.libraryIndexStore)
        do {
            phase = .loaded(try await service.search(request.text))
        } catch is CancellationError {
        } catch let error as SmartSearchError {
            phase = .failed(String(localized: error.localizedStringResource))
        } catch {
            Logger.ui.error("Smart search failed: \(error, privacy: .public)")
            phase = .failed(String(localized: "Your library index isn't ready yet. Try again after it syncs."))
        }
    }

    private func play(_ songs: [DisplayableSong], startIndex: Int) {
        HapticFeedback.medium.trigger()
        Task { await container?.toastService.perform { try await container?.playerService.play(tracks: songs, startIndex: startIndex) } }
    }
}
