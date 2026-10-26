import Foundation
import Observation
import SwiftSonic

/// Discover's shelves for one server, loaded as the iPhone's Discover loads them: the stations and
/// Smart Shuffle covers from listening history, Fresh Releases when ListenBrainz is connected, the
/// mood and Wrapped playlists, and the internet radio stations. The app keeps it, so going back to
/// Discover shows the shelves straight away.
@Observable
@MainActor
final class MacDiscoverModel {
    let container: AppContainer
    let serverID: UUID
    let listening: DiscoverViewModel
    let allFreshReleases: AllFreshReleasesViewModel

    private(set) var isListenBrainzConnected = false
    private(set) var yearlyPlaylists: [WrappedYearlyPlaylist] = []
    private(set) var radioStations: [InternetRadioStation] = []
    private(set) var moods: [MoodPlaylist] = []
    /// The station being started, which shows Preparing… until it plays.
    private(set) var startingStationID: String?
    private(set) var isStartingShuffle = false

    @ObservationIgnored private var lastRefresh: Date?
    private static let freshness: TimeInterval = 10 * 60

    init(container: AppContainer, serverID: UUID) {
        self.container = container
        self.serverID = serverID
        listening = DiscoverViewModel(libraryService: container.libraryService,
                                      recommendationService: container.recommendationService)
        allFreshReleases = AllFreshReleasesViewModel(recommendationService: container.recommendationService)
    }

    private var isOnline: Bool { container.serverState.isOnline }
    private var serverKey: String { serverID.uuidString }

    // MARK: - What the shelves show

    /// Offline, the mood playlists saved on this Mac.
    var visibleMoods: [MoodPlaylist] {
        isOnline ? moods : MoodPlaylist.saved(in: container.offlineLibrary.snapshot.playlists)
    }

    var wrappedYearly: [WrappedYearlyPlaylist] {
        isOnline ? yearlyPlaylists : WrappedYearlyPlaylist.saved(in: container.offlineLibrary.snapshot.playlists)
    }

    var smartShuffleCoverIDs: [String] {
        SmartShuffleArtwork.coverIDs(isOnline ? listening.recentlyPlayed + listening.mostPlayed
                                              : container.offlineLibrary.snapshot.albums)
    }

    /// Smart Shuffle needs the server, or songs saved on this Mac.
    var showsSmartShuffle: Bool {
        isOnline || !container.offlineLibrary.snapshot.songs.isEmpty
    }

    var showsFreshReleases: Bool {
        isListenBrainzConnected && !listening.freshReleases.isEmpty
    }

    // MARK: - Loading

    /// Loads on first view and once the shelves are ten minutes old; offline, only the saved
    /// mood playlists.
    func loadIfNeeded() async {
        guard isOnline else {
            moods = await container.moodPlaylistService.cachedPlaylists(serverId: serverKey)
            return
        }
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.freshness, !listening.stations.isEmpty {
            return
        }
        await refresh(force: false)
    }

    /// Everything at once, as pull-to-refresh does on the iPhone.
    func refresh(force: Bool) async {
        guard isOnline else { return }
        let started = Date()
        async let personal: Void = listening.load(forceRefresh: force)
        async let releases: Void = refreshFreshReleases()
        async let radio: Void = loadRadioStations(forceRefresh: force)
        async let mixes: Void = refreshServerMixes()
        _ = await (personal, releases, radio, mixes)
        if !Task.isCancelled { lastRefresh = started }
    }

    /// After the mood playlists change, e.g. from Settings.
    func reloadMoods() async {
        await loadMoodPlaylists()
    }

    private func refreshFreshReleases() async {
        let connected = await container.listenBrainzService.currentSnapshot().isEnabled
        guard !Task.isCancelled else { return }
        isListenBrainzConnected = connected
        if connected { await listening.loadFreshReleases() }
    }

    private func loadRadioStations(forceRefresh: Bool) async {
        if let stations = try? await container.radioService.listStations(forceRefresh: forceRefresh) {
            guard !Task.isCancelled else { return }
            radioStations = stations
        }
    }

    private func refreshServerMixes() async {
        let playlists = await container.wrappedPlaylistService.fetchYearlyPlaylists(serverId: serverKey)
        guard !Task.isCancelled else { return }
        yearlyPlaylists = playlists
        await refreshMoods()
    }

    /// Shows the cached mood playlists at once, runs the weekly sync if it's due, then reads them.
    private func refreshMoods() async {
        let service = container.moodPlaylistService
        if moods.isEmpty {
            let cached = await service.cachedPlaylists(serverId: serverKey)
            guard !Task.isCancelled else { return }
            if moods.isEmpty { moods = cached }
        }
        let serverID = serverKey
        _ = await BackgroundActivity.run("mood-playlists") {
            await service.runWeeklySyncIfNeeded(serverId: serverID)
        }
        await loadMoodPlaylists()
    }

    private func loadMoodPlaylists() async {
        let service = container.moodPlaylistService
        guard isOnline else {
            moods = await service.cachedPlaylists(serverId: serverKey)
            return
        }
        let found: [MoodPlaylist]
        do {
            found = try await service.fetchPlaylists(serverId: serverKey)
        } catch is CancellationError {
            return
        } catch {
            guard moods.isEmpty else { return }
            found = await service.cachedPlaylists(serverId: serverKey)
        }
        guard !Task.isCancelled else { return }
        moods = found
    }

    // MARK: - Playing

    func playStation(_ station: ArtistStation, with playback: MacPlayback) async {
        guard startingStationID == nil else { return }
        startingStationID = station.id
        defer { startingStationID = nil }
        await playback.playStation(station)
    }

    func playSmartShuffle(with playback: MacPlayback) async {
        guard !isStartingShuffle else { return }
        isStartingShuffle = true
        defer { isStartingShuffle = false }
        await playback.playSmartShuffle()
    }
}
