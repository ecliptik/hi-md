import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Minidisc

// MARK: - Stub server

/// A playlist server in memory: lists, creates, renames and deletes, and can be told to refuse
/// renames. Nothing here touches a real server.
private actor RenamingServerStub: MoodPlaylistClient, PlaylistRenaming {
    var playlists: [Playlist]
    var failingRenames: Set<String> = []
    private(set) var renames: [(id: String, name: String)] = []
    private(set) var created: [String] = []
    private var nextId = 0

    init(_ playlists: [Playlist]) { self.playlists = playlists }

    func getPlaylists(username: String?) async throws -> [Playlist] { playlists }

    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs {
        let id: String
        if let playlistId {
            id = playlistId
        } else {
            nextId += 1
            id = "created-\(nextId)"
            created.append(name ?? "")
            playlists.append(Playlist(id: id, name: name ?? "", songCount: 0, duration: 0, owner: "me"))
        }
        let stored = playlists.first { $0.id == id }?.name ?? name ?? ""
        return PlaylistWithSongs(id: id, name: stored, songCount: songIds.count, duration: 0)
    }

    func deletePlaylist(id: String) async throws { playlists.removeAll { $0.id == id } }

    func renamePlaylist(id: String, to name: String) async throws {
        if failingRenames.contains(id) { throw URLError(.cannotConnectToHost) }
        renames.append((id, name))
        if let index = playlists.firstIndex(where: { $0.id == id }) {
            playlists[index] = playlists[index].renamed(name)
        }
    }

    func setFailingRenames(_ ids: Set<String>) { failingRenames = ids }
    func add(_ playlist: Playlist) { playlists.append(playlist) }
    func names() -> [String: String] { Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0.name) }) }
}

private nonisolated final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool
    init(_ value: Bool) { _value = value }
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

private func playlist(_ id: String, _ name: String, owner: String? = "me") -> Playlist {
    Playlist(id: id, name: name, songCount: 10, duration: 100, owner: owner)
}

private func defaults() -> UserDefaults {
    UserDefaults(suiteName: "name-migration.tests.\(UUID().uuidString)")!
}

private func moodService(
    _ server: RenamingServerStub,
    preferences: MoodPreferences,
    online: Flag = Flag(true),
    covers: CoverLog? = nil
) -> MoodPlaylistService {
    var applier: (@Sendable (PlaylistGradientSpec, String, String) async -> Void)?
    if let covers {
        applier = { _, id, title in covers.record(id, title) }
    }
    return MoodPlaylistService(
        playlistClientFactory: { server },
        playlistOwner: "me",
        providerFactory: { nil },
        coverApplier: applier,
        preferences: preferences,
        isOnline: { online.value }
    )
}

private nonisolated final class CoverLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [(id: String, title: String)] = []
    var entries: [(id: String, title: String)] { lock.withLock { _entries } }
    func record(_ id: String, _ title: String) { lock.withLock { _entries.append((id, title)) } }
}

// MARK: - Recognition

@Suite("Playlist names — recognition of Hi-MD and Minidisc names")
struct PlaylistNameRecognitionTests {
    @Test("New playlists get the Hi-MD names")
    func currentNames() {
        #expect(Mood.night.playlistName == "Hi-MD · Night")
        #expect(Mood.night.legacyPlaylistName == "Minidisc · Night")
        #expect(WrappedPlaylistService.playlistName(year: 2026) == "Hi-MD Wrapped 2026")
    }

    @Test("Both prefixes are recognised for moods and Wrapped years")
    func bothPrefixes() {
        #expect(Mood.forPlaylistName("Hi-MD · Chill") == .chill)
        #expect(Mood.forPlaylistName("Minidisc · Chill") == .chill)
        #expect(Mood.forPlaylistName("Minidisc · My favourites") == nil)
        #expect(WrappedPlaylistService.wrappedYear(fromPlaylistName: "Hi-MD Wrapped 2026") == 2026)
        #expect(WrappedPlaylistService.wrappedYear(fromPlaylistName: "Minidisc Wrapped 2025") == 2025)
        #expect(WrappedPlaylistService.wrappedYear(fromPlaylistName: "Hi-MD Wrapped") == nil)
        #expect(PlaybackContext.forPlaylist(id: "a", name: "Minidisc · Focus", coverArtId: nil) == .mood(.focus, playlistId: "a"))
        #expect(PlaybackContext.forPlaylist(id: "b", name: "Hi-MD · Focus", coverArtId: nil) == .mood(.focus, playlistId: "b"))
        #expect(PlaybackContext.forPlaylist(id: "c", name: "Minidisc Wrapped 2024", coverArtId: nil) == .wrapped(year: 2024, playlistId: "c"))
        #expect(MusicIntentService.matchesPlaylist("Minidisc · Night", term: "night"))
        #expect(MusicIntentService.matchesPlaylist("Hi-MD · Night", term: "night"))
    }

    @Test("Saved offline playlists: either name counts, and the Hi-MD one wins when both exist")
    func offlineSnapshotPrefersCurrent() {
        let saved = MoodPlaylist.saved(in: [
            playlist("old-night", "Minidisc · Night"),
            playlist("old-chill", "Minidisc · Chill"),
            playlist("new-night", "Hi-MD · Night"),
            playlist("mine", "Night drives"),
        ])
        #expect(saved == [
            MoodPlaylist(mood: .chill, id: "old-chill", coverArtId: nil),
            MoodPlaylist(mood: .night, id: "new-night", coverArtId: nil),
        ])

        let years = WrappedYearlyPlaylist.saved(in: [
            playlist("w25-old", "Minidisc Wrapped 2025"),
            playlist("w25-new", "Hi-MD Wrapped 2025"),
            playlist("w24-old", "Minidisc Wrapped 2024"),
        ])
        #expect(years.map(\.id) == ["w25-new", "w24-old"])
        #expect(years.map(\.year) == [2025, 2024])
    }

    @Test("The plan renames only the user's legacy playlists whose new name is free, one per name")
    func plan() {
        let playlists = [
            playlist("b-night", "Minidisc · Night"),
            playlist("a-night", "Minidisc · Night"),
            playlist("chill", "Minidisc · Chill"),
            playlist("new-chill", "Hi-MD · Chill"),
            playlist("theirs", "Minidisc · Focus", owner: "someone-else"),
            playlist("custom", "Minidisc · My favourites"),
            playlist("wrapped", "Minidisc Wrapped 2025"),
        ]
        let renames = PlaylistNameMigration.moods.plan(playlists, owner: "me")
        #expect(renames == [.init(playlistId: "a-night", from: "Minidisc · Night", to: "Hi-MD · Night")])

        let preferring = PlaylistNameMigration.moods.plan(playlists, owner: "me", preferredIDs: ["b-night"])
        #expect(preferring.map(\.playlistId) == ["b-night"])

        let wrapped = PlaylistNameMigration.wrapped.plan(playlists, owner: "me")
        #expect(wrapped == [.init(playlistId: "wrapped", from: "Minidisc Wrapped 2025", to: "Hi-MD Wrapped 2025")])
    }
}

// MARK: - Mood playlists

@Suite("Playlist names — mood playlist migration")
struct MoodPlaylistNameMigrationTests {
    @Test("Renames the user's Minidisc mood playlists and records that it's done")
    func renamesLegacy() async throws {
        let server = RenamingServerStub([
            playlist("night", "Minidisc · Night"),
            playlist("chill", "Minidisc · Chill"),
            playlist("theirs", "Minidisc · Focus", owner: "someone-else"),
            playlist("custom", "Minidisc · My favourites"),
        ])
        let preferences = MoodPreferences(userDefaults: defaults())
        let covers = CoverLog()
        let service = moodService(server, preferences: preferences, covers: covers)

        let found = try await service.fetchPlaylists(serverId: "s1")

        #expect(Set(await server.renames.map(\.id)) == ["night", "chill"])
        let names = await server.names()
        #expect(names["night"] == "Hi-MD · Night")
        #expect(names["chill"] == "Hi-MD · Chill")
        #expect(names["theirs"] == "Minidisc · Focus")
        #expect(names["custom"] == "Minidisc · My favourites")
        #expect(Set(found.map(\.id)) == ["night", "chill"])
        #expect(preferences.hasMigratedPlaylistNames(serverId: "s1"))
        // The gradient cover carries the name, so it is drawn again with the new one.
        #expect(Set(covers.entries.map(\.title)) == ["Hi-MD · Night", "Hi-MD · Chill"])
    }

    @Test("Leaves both alone when the Hi-MD name already exists, and uses the Hi-MD one")
    func skipsWhenNewNameExists() async throws {
        let server = RenamingServerStub([
            playlist("old-night", "Minidisc · Night"),
            playlist("new-night", "Hi-MD · Night"),
        ])
        let preferences = MoodPreferences(userDefaults: defaults())
        preferences.setPlaylistId("old-night", mood: .night, serverId: "s1")
        let service = moodService(server, preferences: preferences)

        let found = try await service.fetchPlaylists(serverId: "s1")

        #expect(await server.renames.isEmpty)
        #expect(await server.names() == ["old-night": "Minidisc · Night", "new-night": "Hi-MD · Night"])
        #expect(found == [MoodPlaylist(mood: .night, id: "new-night", coverArtId: nil)])
        #expect(preferences.playlistId(mood: .night, serverId: "s1") == "new-night")
        #expect(preferences.hasMigratedPlaylistNames(serverId: "s1"))
    }

    @Test("Runs once per server")
    func oncePerServer() async throws {
        let server = RenamingServerStub([playlist("night", "Minidisc · Night")])
        let preferences = MoodPreferences(userDefaults: defaults())
        let service = moodService(server, preferences: preferences)

        _ = try await service.fetchPlaylists(serverId: "s1")
        #expect(await server.renames.count == 1)

        // A legacy name appearing later (say, from an older install) is still recognised, but
        // the migration doesn't run again for this server.
        await server.add(playlist("chill", "Minidisc · Chill"))
        let again = try await service.fetchPlaylists(serverId: "s1")
        #expect(await server.renames.count == 1)
        #expect(again.contains(MoodPlaylist(mood: .chill, id: "chill", coverArtId: nil)))

        // Another server has its own record.
        _ = try await service.fetchPlaylists(serverId: "s2")
        #expect(await server.renames.map(\.id) == ["night", "chill"])
        #expect(preferences.hasMigratedPlaylistNames(serverId: "s2"))
    }

    @Test("Does nothing while offline")
    func offlineNoOp() async throws {
        let server = RenamingServerStub([playlist("night", "Minidisc · Night")])
        let preferences = MoodPreferences(userDefaults: defaults())
        let online = Flag(false)
        let service = moodService(server, preferences: preferences, online: online)

        let found = try await service.fetchPlaylists(serverId: "s1")
        #expect(await server.renames.isEmpty)
        #expect(!preferences.hasMigratedPlaylistNames(serverId: "s1"))
        #expect(found == [MoodPlaylist(mood: .night, id: "night", coverArtId: nil)])

        online.value = true
        _ = try await service.fetchPlaylists(serverId: "s1")
        #expect(await server.renames.map(\.id) == ["night"])
        #expect(preferences.hasMigratedPlaylistNames(serverId: "s1"))
    }

    @Test("A refused rename isn't fatal and is retried next time")
    func failureRetries() async throws {
        let server = RenamingServerStub([
            playlist("night", "Minidisc · Night"),
            playlist("chill", "Minidisc · Chill"),
        ])
        await server.setFailingRenames(["night"])
        let preferences = MoodPreferences(userDefaults: defaults())
        let service = moodService(server, preferences: preferences)

        let first = try await service.fetchPlaylists(serverId: "s1")
        #expect(await server.renames.map(\.id) == ["chill"])
        #expect(!preferences.hasMigratedPlaylistNames(serverId: "s1"))
        #expect(Set(first.map(\.id)) == ["night", "chill"], "the legacy-named playlist is still used")

        await server.setFailingRenames([])
        _ = try await service.fetchPlaylists(serverId: "s1")
        #expect(await server.renames.map(\.id) == ["chill", "night"])
        #expect(await server.names() == ["night": "Hi-MD · Night", "chill": "Hi-MD · Chill"])
        #expect(preferences.hasMigratedPlaylistNames(serverId: "s1"))
    }

    @Test("The weekly sync finds a Minidisc-named playlist instead of creating a duplicate, and creates new ones with Hi-MD names")
    func syncRenamesAndCreates() async throws {
        let server = RenamingServerStub([playlist("night", "Minidisc · Night")])
        let preferences = MoodPreferences(userDefaults: defaults())
        let provider = FixedProvider()
        let service = MoodPlaylistService(
            playlistClientFactory: { server },
            playlistOwner: "me",
            providerFactory: { provider },
            preferences: preferences
        )

        _ = await service.rebuildNow(serverId: "s1")

        #expect(await server.renames.map(\.id) == ["night"])
        #expect(preferences.playlistId(mood: .night, serverId: "s1") == "night")
        #expect(Set(await server.created) == Set(Mood.allCases.filter { $0 != .night }.map(\.playlistName)))
        #expect(await server.created.allSatisfy { $0.hasPrefix("Hi-MD · ") })
    }
}

private struct FixedProvider: MoodTrackProvider {
    let kind: MoodSourceKind = .sonic
    func prepare() async {}
    func trackIds(for mood: Mood, limit: Int) async throws -> [String] { ["t1", "t2"] }
}

// MARK: - Wrapped playlists

@Suite("Playlist names — Wrapped playlist migration")
struct WrappedPlaylistNameMigrationTests {
    private func service(
        _ server: RenamingServerStub,
        preferences: WrappedPreferences,
        online: Flag = Flag(true)
    ) throws -> WrappedPlaylistService {
        let stats = StatsService(modelContainer: try ModelContainer.minidisc(inMemory: true))
        return WrappedPlaylistService(
            clientFactory: { server }, statsService: stats, preferences: preferences,
            playlistOwner: "me", isOnline: { online.value }
        )
    }

    @Test("Renames Minidisc Wrapped playlists, keeping one whose Hi-MD name exists")
    func renamesLegacy() async throws {
        let server = RenamingServerStub([
            playlist("w24", "Minidisc Wrapped 2024"),
            playlist("w25-old", "Minidisc Wrapped 2025"),
            playlist("w25-new", "Hi-MD Wrapped 2025"),
            playlist("theirs", "Minidisc Wrapped 2023", owner: "someone-else"),
        ])
        let preferences = WrappedPreferences(userDefaults: defaults())
        let wrapped = try service(server, preferences: preferences)

        let years = await wrapped.fetchYearlyPlaylists(serverId: "s1")

        #expect(await server.renames.map(\.id) == ["w24"])
        let names = await server.names()
        #expect(names["w24"] == "Hi-MD Wrapped 2024")
        #expect(names["w25-old"] == "Minidisc Wrapped 2025")
        #expect(names["theirs"] == "Minidisc Wrapped 2023")
        #expect(years.map(\.id) == ["w25-new", "w24", "theirs"])
        #expect(years.first { $0.year == 2024 }?.name == "Hi-MD Wrapped 2024")
        #expect(preferences.hasMigratedPlaylistNames(serverId: "s1"))

        _ = await wrapped.fetchYearlyPlaylists(serverId: "s1")
        #expect(await server.renames.count == 1, "runs once per server")
    }

    @Test("Offline: nothing is renamed, and the old names still show")
    func offlineNoOp() async throws {
        let server = RenamingServerStub([playlist("w25", "Minidisc Wrapped 2025")])
        let preferences = WrappedPreferences(userDefaults: defaults())
        let wrapped = try service(server, preferences: preferences, online: Flag(false))

        let years = await wrapped.fetchYearlyPlaylists(serverId: "s1")
        #expect(await server.renames.isEmpty)
        #expect(years.map(\.year) == [2025])
        #expect(!preferences.hasMigratedPlaylistNames(serverId: "s1"))
    }

    @Test("A refused rename is retried on the next listing")
    func failureRetries() async throws {
        let server = RenamingServerStub([playlist("w25", "Minidisc Wrapped 2025")])
        await server.setFailingRenames(["w25"])
        let preferences = WrappedPreferences(userDefaults: defaults())
        let wrapped = try service(server, preferences: preferences)

        #expect(await wrapped.fetchYearlyPlaylists(serverId: "s1").map(\.id) == ["w25"])
        #expect(!preferences.hasMigratedPlaylistNames(serverId: "s1"))

        await server.setFailingRenames([])
        _ = await wrapped.fetchYearlyPlaylists(serverId: "s1")
        #expect(await server.names()["w25"] == "Hi-MD Wrapped 2025")
        #expect(preferences.hasMigratedPlaylistNames(serverId: "s1"))
    }
}
