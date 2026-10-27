import CarPlay
import Observation
import OSLog
import SwiftData
import SwiftSonic
import UIKit

/// Builds Minidisc's CarPlay templates: Home, Library, Downloads and Moods.
///
/// Lists come from local data (the library index, the Home feed cache, pins and downloads), so
/// browsing works without a connection. Playback goes through `PlayerService` like the phone UI,
/// and Now Playing is the system template fed by the app's NowPlaying session.
@MainActor
final class CarPlayController {
    private let interfaceController: CPInterfaceController
    private var container: AppContainer?
    private var observation: Task<Void, Never>?
    /// Bounds artwork work per list; the rest keep their placeholder symbol.
    private static let artworkLimit = 60

    private let homeTemplate = CPListTemplate(title: String(localized: "Home"), sections: [])
    private let libraryTemplate = CPListTemplate(title: String(localized: "Library"), sections: [])
    private let downloadsTemplate = CPListTemplate(title: String(localized: "Downloads"), sections: [])
    private let moodsTemplate = CPListTemplate(title: String(localized: "Moods"), sections: [])

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func connect() {
        homeTemplate.tabImage = UIImage(systemName: "house")
        libraryTemplate.tabImage = UIImage(systemName: "square.stack")
        downloadsTemplate.tabImage = UIImage(systemName: "arrow.down.circle")
        moodsTemplate.tabImage = UIImage(systemName: "sparkles")
        let tabs = CPTabBarTemplate(templates: [homeTemplate, libraryTemplate, downloadsTemplate, moodsTemplate])
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)

        observation = Task { [weak self] in
            guard let container = try? await MinidiscRuntime.shared.container() else { return }
            self?.container = container
            let serverState = container.serverState
            for await _ in Observations({ serverState.activeServer?.id }) {
                await self?.reload()
            }
        }
    }

    func disconnect() {
        observation?.cancel()
        observation = nil
    }

    // MARK: - Tabs

    private func reload() async {
        guard let container, let server = container.serverState.activeServer else {
            let message = String(localized: "Open Hi-MD on your iPhone to connect to your music server.")
            for template in [homeTemplate, libraryTemplate, downloadsTemplate, moodsTemplate] {
                template.emptyViewTitleVariants = [message]
                template.updateSections([])
            }
            return
        }
        let scope = MusicIntentID.scope(baseURL: server.baseURL, username: server.username)
        await reloadHome(container: container, server: server, scope: scope)
        reloadLibrary(container: container, server: server, scope: scope)
        await reloadDownloads(container: container, server: server)
        await reloadMoods(container: container, server: server)
    }

    private func reloadHome(container: AppContainer, server: ServerSnapshot, scope: String) async {
        var sections: [CPListSection] = []
        if let feed = await HomeFeedCache.shared.load(serverID: server.id), !feed.recentlyPlayed.isEmpty {
            let items = feed.recentlyPlayed.prefix(12).map {
                collectionItem(MusicIntentID(scope: scope, kind: .album, resourceID: $0.id),
                               title: $0.name, detail: $0.artist, coverArtId: $0.coverArt)
            }
            sections.append(CPListSection(items: items, header: String(localized: "Recently Played"), sectionIndexTitle: nil))
        }
        let serverID = server.id
        var pins = FetchDescriptor<PinnedItem>(predicate: #Predicate { $0.serverId == serverID },
                                               sortBy: [SortDescriptor(\.sortOrder)])
        pins.fetchLimit = 12
        let pinned: [CPListItem] = ((try? container.modelContainer.mainContext.fetch(pins)) ?? []).compactMap { pin in
            guard let kind = MusicIntentKind(rawValue: pin.itemType), kind != .song else { return nil }
            return collectionItem(MusicIntentID(scope: scope, kind: kind, resourceID: pin.itemId),
                                  title: pin.displayName, detail: pin.displaySubtitle, coverArtId: pin.coverArtId)
        }
        if !pinned.isEmpty {
            sections.append(CPListSection(items: pinned, header: String(localized: "Pinned"), sectionIndexTitle: nil))
        }
        homeTemplate.emptyViewTitleVariants = [String(localized: "Play something on your iPhone and it will appear here.")]
        homeTemplate.updateSections(sections)
        loadArtwork(for: sections.flatMap(\.items))
    }

    private func reloadLibrary(container: AppContainer, server: ServerSnapshot, scope: String) {
        let store = container.libraryIndexStore
        let serverID = server.id
        let entries: [(LocalizedStringResource, String, MusicIntentKind)] = [
            ("Playlists", "music.note.list", .playlist), ("Albums", MinidiscSymbol.album, .album), ("Artists", "music.mic", .artist)
        ]
        let items = entries.map { title, symbol, kind in
            let item = CPListItem(text: String(localized: title), detailText: nil, image: UIImage.symbol(symbol))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task { [weak self] in
                    await self?.showLibraryList(String(localized: title), kind: kind, store: store, serverID: serverID, scope: scope)
                    completion()
                }
            }
            return item
        }
        libraryTemplate.updateSections([CPListSection(items: items)])
    }

    private func reloadDownloads(container: AppContainer, server: ServerSnapshot) async {
        let ids = await container.downloadService.downloadedSongIds(serverId: server.id)
        let songs = ((try? await container.libraryIndexStore.songs(ids: ids, serverID: server.id)) ?? [])
            .map { DisplayableSong(from: $0, isDownloaded: true) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        downloadsTemplate.emptyViewTitleVariants = [String(localized: "Download albums or playlists on your iPhone to play them here without a connection.")]
        downloadsTemplate.updateSections(songs.isEmpty ? [] : songSections(songs))
    }

    private func reloadMoods(container: AppContainer, server: ServerSnapshot) async {
        var items: [CPListItem] = []
        for mood in Mood.allCases {
            let available = await container.moodPlaylistService.playlistId(for: mood, serverId: server.id.uuidString) != nil
            let item = CPListItem(text: String(localized: mood.title), detailText: nil, image: UIImage(systemName: mood.symbolName))
            item.isEnabled = available
            item.handler = { [weak self] _, completion in
                Task { [weak self] in
                    await self?.play { try await MusicIntentService(container: container).play(mood: mood) }
                    completion()
                }
            }
            items.append(item)
        }
        moodsTemplate.updateSections([CPListSection(items: items)])
    }

    // MARK: - Lists

    private func showLibraryList(_ title: String, kind: MusicIntentKind, store: LibraryIndexStore,
                                 serverID: UUID, scope: String) async {
        let limit = CPListTemplate.maximumItemCount
        let items: [CPListItem]
        switch kind {
        case .playlist:
            items = ((try? await store.playlists(serverID: serverID)) ?? []).prefix(limit).map {
                collectionItem(MusicIntentID(scope: scope, kind: .playlist, resourceID: $0.id),
                               title: $0.name, detail: nil, coverArtId: $0.coverArt)
            }
        case .album:
            items = ((try? await store.albums(serverID: serverID)) ?? []).prefix(limit).map {
                collectionItem(MusicIntentID(scope: scope, kind: .album, resourceID: $0.id),
                               title: $0.name, detail: $0.artist, coverArtId: $0.coverArt)
            }
        case .artist, .song:
            items = ((try? await store.artists(serverID: serverID)) ?? []).flatMap(\.artist).prefix(limit).map {
                collectionItem(MusicIntentID(scope: scope, kind: .artist, resourceID: $0.id),
                               title: $0.name, detail: nil, coverArtId: $0.coverArt)
            }
        }
        let template = CPListTemplate(title: title, sections: [CPListSection(items: items)])
        template.emptyViewTitleVariants = [String(localized: "Your library hasn't synced yet. Open Hi-MD on your iPhone.")]
        _ = try? await interfaceController.pushTemplate(template, animated: true)
        loadArtwork(for: items)
    }

    /// An album, playlist or artist; selecting it lists its songs.
    private func collectionItem(_ reference: MusicIntentID, title: String, detail: String?, coverArtId: String?) -> CPListItem {
        let symbol = switch reference.kind {
        case .playlist: "music.note.list"
        case .artist: "music.mic"
        case .album, .song: MinidiscSymbol.album
        }
        let item = CPListItem(text: title, detailText: detail, image: UIImage.symbol(symbol))
        item.accessoryType = .disclosureIndicator
        item.userInfo = CarPlayArtwork(coverArtId: coverArtId, showsDiscWhenMissing: reference.kind != .artist)
        item.handler = { [weak self] _, completion in
            Task { [weak self] in
                await self?.showSongs(of: reference, title: title)
                completion()
            }
        }
        return item
    }

    private func showSongs(of reference: MusicIntentID, title: String) async {
        guard let container else { return }
        let songs: [DisplayableSong]
        do {
            songs = try await MusicIntentService(container: container).songs(id: reference.rawValue)
        } catch {
            Logger.player.info("CarPlay could not load \(reference.kind.rawValue, privacy: .public): \(error, privacy: .public)")
            await showAlert(String(localized: "Couldn't load this. Check your connection or downloads."))
            return
        }
        let template = CPListTemplate(title: title, sections: songSections(songs))
        template.emptyViewTitleVariants = [String(localized: "There are no playable tracks in this selection.")]
        _ = try? await interfaceController.pushTemplate(template, animated: true)
    }

    /// A Shuffle row, then the songs; selecting one plays the list from there.
    private func songSections(_ songs: [DisplayableSong]) -> [CPListSection] {
        let shuffle = CPListItem(text: String(localized: "Shuffle"), detailText: nil, image: UIImage(systemName: "shuffle"))
        shuffle.handler = { [weak self] _, completion in
            Task { [weak self] in
                await self?.play { try await self?.container?.playerService.play(tracks: songs.shuffled(), startIndex: 0) }
                completion()
            }
        }
        let rows = songs.prefix(CPListTemplate.maximumItemCount - 1).enumerated().map { index, song in
            let item = CPListItem(text: song.title, detailText: song.artist)
            item.handler = { [weak self] _, completion in
                Task { [weak self] in
                    await self?.play { try await self?.container?.playerService.play(tracks: songs, startIndex: index) }
                    completion()
                }
            }
            return item
        }
        return [CPListSection(items: [shuffle]), CPListSection(items: rows)]
    }

    // MARK: - Playback and artwork

    private func play(_ start: @MainActor () async throws -> Void) async {
        do {
            try await start()
            guard interfaceController.topTemplate !== CPNowPlayingTemplate.shared else { return }
            _ = try await interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
        } catch is CancellationError {
        } catch {
            Logger.player.info("CarPlay playback failed: \(error, privacy: .public)")
            await showAlert(String(localized: "Couldn't play this. Check your connection or downloads."))
        }
    }

    private func showAlert(_ message: String) async {
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: String(localized: "OK"), style: .cancel) { [weak self] _ in
                self?.interfaceController.dismissTemplate(animated: true, completion: nil)
            }
        ])
        _ = try? await interfaceController.presentTemplate(alert, animated: true)
    }

    private func loadArtwork(for items: [any CPListTemplateItem]) {
        guard let cache = container?.artworkImageCache else { return }
        for case let item as CPListItem in items.prefix(Self.artworkLimit) {
            guard let artwork = item.userInfo as? CarPlayArtwork else { continue }
            Task {
                if let coverArtId = artwork.coverArtId, let image = await cache.load(coverArtId: coverArtId, tier: .thumb) {
                    item.setImage(image)
                } else if artwork.showsDiscWhenMissing, cache.phase(for: artwork.coverArtId) == .missing,
                          let disc = UIImage(named: "MinidiscLogoThumb") {
                    // An album or playlist without a cover shows the MiniDisc, as in the app.
                    item.setImage(disc)
                }
            }
        }
    }
}

/// A list item's cover, kept on the item until its artwork loads.
private struct CarPlayArtwork {
    let coverArtId: String?
    let showsDiscWhenMissing: Bool
}
