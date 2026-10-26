import SwiftUI
import SwiftSonic

struct WrappedYearlyListView: View {
    @Environment(\.appContainer) private var container
    @State private var playlists: [WrappedYearlyPlaylist] = []
    @State private var isLoading = true

    private var visiblePlaylists: [WrappedYearlyPlaylist] {
        guard container?.serverState.isOnline == false else { return playlists }
        return WrappedYearlyPlaylist.saved(in: container?.offlineLibrary.snapshot.playlists ?? [])
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var hasCurrentYearPlaylist: Bool {
        visiblePlaylists.contains { $0.year == currentYear }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MinidiscSpacing.l) {
                if isLoading && container?.serverState.isOnline != false {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, MinidiscSpacing.xxxxl)
                } else if playlists.isEmpty && hasCurrentYearPlaylist {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: MinidiscSpacing.s)],
                        spacing: MinidiscSpacing.s
                    ) {
                        ForEach(WrappedCarouselItem.pageItems(yearly: visiblePlaylists)) { item in
                            switch item {
                            case .currentYear(let year):
                                WrappedRecapMonthCard(period: .year(year))
                            case .yearly(let playlist):
                                WrappedYearlyCard(playlist: playlist)
                            case .month(let year, let month):
                                WrappedRecapMonthCard(period: .month(year: year, month: month))
                            }
                        }
                    }

                    NavigationLink {
                        WrappedView()
                    } label: {
                        HStack(spacing: MinidiscSpacing.s) {
                            Image(systemName: "chart.bar.fill")
                                .font(.title2)
                                .foregroundStyle(Color.minidiscAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Listening Stats")
                                    .font(.minidiscCellTitle)
                                    .foregroundStyle(.primary)
                                Text("Monthly and annual breakdowns")
                                    .font(.minidiscCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(MinidiscSpacing.m)
                        .background(Color.minidiscAccent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(MinidiscSpacing.l)
        }
        .minidiscContentWidth()
        .navigationTitle("Wrapped")
        .task(id: container?.serverState.accessSnapshot) {
            guard let container,
                  let serverId = container.serverState.activeServer?.id.uuidString else {
                isLoading = false
                return
            }
            guard container.serverState.isOnline else { isLoading = false; return }
            playlists = await container.wrappedPlaylistService.fetchYearlyPlaylists(serverId: serverId)
            isLoading = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: MinidiscSpacing.s) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(Color.minidiscAccent.opacity(0.5))
            Text("No Wrapped playlists yet.")
                .font(.minidiscCellTitle)
            Text("Your Wrapped \(currentYear) will be available on December 28.")
                .font(.minidiscCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MinidiscSpacing.xxxxl)
    }
}
