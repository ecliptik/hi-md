import SwiftSonic
import SwiftUI

/// Discover, as on the iPhone and in the same order: Recommended for You, Fresh Releases (with
/// ListenBrainz connected), Stations for You, Smart Shuffle, Moods, Wrapped and Internet Radio.
/// Offline, only what can play from this Mac: Smart Shuffle of the downloads, and the saved mood
/// and Wrapped playlists.
struct MacDiscoverView: View {
    let container: AppContainer

    @Environment(MacInterface.self) private var interface
    @Environment(MacNavigator.self) private var navigator
    @Environment(MacPlayback.self) private var playback

    private var isOnline: Bool { container.serverState.isOnline }

    var body: some View {
        let model = interface.discover(for: container)
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Discover")
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model?.refresh(force: true) } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model == nil || !isOnline || model?.listening.isLoading == true)
            }
        }
        .task(id: container.serverState.accessSnapshot) { await model?.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscMoodPlaylistsChanged)) { _ in
            Task { await model?.reloadMoods() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscPlaylistsChanged)) { _ in
            Task { await model?.reloadMoods() }
        }
    }

    private func content(_ model: MacDiscoverModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                if isOnline {
                    MacRecommendationsCard()
                        .padding(.horizontal, MacShelfMetrics.margin)
                    if model.showsFreshReleases {
                        freshReleases(model)
                    }
                    stations(model)
                }
                if model.showsSmartShuffle {
                    MacSmartShuffleCard(coverIDs: model.smartShuffleCoverIDs, isStarting: model.isStartingShuffle) {
                        Task { await model.playSmartShuffle(with: playback) }
                    }
                    .padding(.horizontal, MacShelfMetrics.margin)
                }
                if !model.visibleMoods.isEmpty {
                    MacShelf(title: String(localized: "Moods")) {
                        ForEach(model.visibleMoods, id: \.mood) { mood in
                            MacMoodCard(mood: mood)
                        }
                    }
                }
                wrapped(model)
                if isOnline {
                    radio(model)
                }
            }
            .padding(.vertical, 20)
            // Sections arrive one request at a time; fade them in rather than jumping.
            .animation(.easeInOut(duration: 0.3), value: sectionLayout(model))
        }
    }

    /// Which sections are showing, so one arriving or leaving animates the page.
    private func sectionLayout(_ model: MacDiscoverModel) -> [Bool] {
        [
            model.showsFreshReleases,
            model.listening.stations.isEmpty,
            model.listening.isLoadingFirstStations,
            model.smartShuffleCoverIDs.isEmpty,
            model.visibleMoods.isEmpty,
            model.radioStations.isEmpty,
        ]
    }

    private func freshReleases(_ model: MacDiscoverModel) -> some View {
        MacShelf(title: String(localized: "Fresh Releases"), onOpen: { navigator.show(.freshReleases) }) {
            ForEach(model.listening.freshReleases, id: \.self) { release in
                MacFreshReleaseCard(release: release)
            }
            MacFreshReleasesSeeAllCard()
        }
    }

    @ViewBuilder
    private func stations(_ model: MacDiscoverModel) -> some View {
        let title = String(localized: "Stations for You")
        if model.listening.isLoadingFirstStations {
            // Stations come from listening history, which loads after the faster sections. Holding
            // their place keeps everything below from being pushed down when they arrive.
            MacShelfPlaceholder(title: title)
                .transition(.opacity)
        } else if !model.listening.stations.isEmpty {
            MacShelf(title: title) {
                ForEach(model.listening.stations) { station in
                    MacStationCard(station: station, isStarting: model.startingStationID == station.id) {
                        Task { await model.playStation(station, with: playback) }
                    }
                }
            }
        }
    }

    private func wrapped(_ model: MacDiscoverModel) -> some View {
        MacShelf(title: String(localized: "Wrapped"), onOpen: { navigator.show(.wrapped) }) {
            ForEach(Array(WrappedCarouselItem.shelfItems(yearly: model.wrappedYearly).prefix(MacShelfMetrics.previewLimit))) { item in
                MacWrappedCard(item: item)
            }
        }
    }

    @ViewBuilder
    private func radio(_ model: MacDiscoverModel) -> some View {
        if model.radioStations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MacShelfHeading(title: String(localized: "Internet Radio"), onOpen: { navigator.show(.radio) })
                Button { navigator.show(.radio) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(Color.minidiscAccent)
                            .accessibilityHidden(true)
                        Text("Browse Stations")
                            .font(.headline)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                    .background(Color.minidiscAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MacShelfMetrics.margin)
        } else {
            MacShelf(title: String(localized: "Internet Radio"), onOpen: { navigator.show(.radio) }) {
                ForEach(model.radioStations.prefix(MacShelfMetrics.previewLimit), id: \.id) { station in
                    MacRadioCard(station: station)
                }
            }
        }
    }
}
