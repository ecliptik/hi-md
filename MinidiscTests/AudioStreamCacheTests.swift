import Foundation
import SwiftData
import Testing
@testable import Minidisc

@Suite("Audio stream cache")
struct AudioStreamCacheTests {
    @Test(arguments: ["audio/aac", "audio/mp4"])
    func adtsCacheUsesAACExtensionEvenWithLegacyMIME(mimeType: String) async throws {
        let container = try ModelContainer(for: CachedTrack.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cache = AudioStreamCache(modelContainer: container)
        let source = URL.temporaryDirectory.appendingPathComponent("adts-\(UUID()).tmp")
        let bytes = Data([0xFF, 0xF1, 0x50, 0x80, 0x01, 0x3F, 0xFC, 0x00])
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let server = UUID()
        let stored = try await cache.store(fileAt: source, forSongId: "aac-track", serverId: server, mimeType: mimeType)
        defer { try? FileManager.default.removeItem(at: stored) }
        #expect(stored.pathExtension == "aac")
        #expect(try Data(contentsOf: stored) == bytes)
        #expect(await cache.cachedURL(forSongId: "aac-track", serverId: server) == stored)
    }

    private func makeTemporaryFile(size: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minidisc-cache-\(UUID().uuidString).tmp")
        try Data(repeating: 0x41, count: size).write(to: url)
        return url
    }

    @Test func fileStoreRoundTripUsesSafeGeneratedName() async throws {
        let container = try ModelContainer(
            for: Schema([CachedTrack.self, CachedLyrics.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let cache = AudioStreamCache(modelContainer: container)
        let serverID = UUID()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minidisc-cache-\(UUID().uuidString).tmp")
        let payload = Data("ID3 playable audio payload".utf8)
        try payload.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let storedURL = try await cache.store(
            fileAt: sourceURL,
            forSongId: "../server-controlled/path",
            serverId: serverID,
            mimeType: "audio/mpeg"
        )
        defer { try? FileManager.default.removeItem(at: storedURL) }

        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(storedURL.pathExtension == "mp3")
        #expect(!storedURL.lastPathComponent.contains(".."))
        #expect(try Data(contentsOf: storedURL) == payload)
        #expect(await cache.cachedURL(forSongId: "../server-controlled/path", serverId: serverID) == storedURL)

        await cache.clearAllForServer(serverID)
        #expect(await cache.cachedURL(forSongId: "../server-controlled/path", serverId: serverID) == nil)
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))
    }

    @Test func clearingAudioCachePreservesLyrics() async throws {
        let container = try ModelContainer(
            for: Schema([CachedTrack.self, CachedLyrics.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let serverID = UUID()
        await MainActor.run {
            let context = ModelContext(container)
            context.insert(CachedLyrics(
                songId: "song-with-lyrics",
                serverId: serverID,
                jsonPayload: Data("{}".utf8)
            ))
            try? context.save()
        }

        let cache = AudioStreamCache(modelContainer: container)
        await cache.clearAllForServer(serverID)

        let lyricCount = await MainActor.run {
            let context = ModelContext(container)
            return (try? context.fetchCount(FetchDescriptor<CachedLyrics>())) ?? 0
        }
        #expect(lyricCount == 1)
    }

    @Test func identicalSongIDsRemainScopedToTheirServer() async throws {
        let container = try ModelContainer(
            for: Schema([CachedTrack.self, CachedLyrics.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let cache = AudioStreamCache(modelContainer: container)
        let firstServerID = UUID()
        let secondServerID = UUID()

        let firstURL = try await cache.store(
            fileAt: makeTemporaryFile(size: 8),
            forSongId: "shared-song-id",
            serverId: firstServerID,
            mimeType: "audio/mpeg"
        )
        let secondURL = try await cache.store(
            fileAt: makeTemporaryFile(size: 12),
            forSongId: "shared-song-id",
            serverId: secondServerID,
            mimeType: "audio/mpeg"
        )

        #expect(await cache.cachedURL(forSongId: "shared-song-id", serverId: firstServerID) == firstURL)
        #expect(await cache.cachedURL(forSongId: "shared-song-id", serverId: secondServerID) == secondURL)

        await cache.clearAll()
    }

    @Test func byteBudgetEvictsLeastRecentlyUsedTrack() async throws {
        let container = try ModelContainer(
            for: Schema([CachedTrack.self, CachedLyrics.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let cache = AudioStreamCache(modelContainer: container, maxBytes: 24)
        let serverID = UUID()

        let firstSource = try makeTemporaryFile(size: 10)
        let firstURL = try await cache.store(
            fileAt: firstSource,
            forSongId: "first",
            serverId: serverID,
            mimeType: "audio/mpeg"
        )
        try await Task.sleep(for: .milliseconds(2))

        let secondSource = try makeTemporaryFile(size: 10)
        let secondURL = try await cache.store(
            fileAt: secondSource,
            forSongId: "second",
            serverId: serverID,
            mimeType: "audio/mpeg"
        )
        try await Task.sleep(for: .milliseconds(2))

        #expect(await cache.cachedURL(forSongId: "first", serverId: serverID) == firstURL)
        try await Task.sleep(for: .milliseconds(2))

        let thirdSource = try makeTemporaryFile(size: 10)
        let thirdURL = try await cache.store(
            fileAt: thirdSource,
            forSongId: "third",
            serverId: serverID,
            mimeType: "audio/mpeg"
        )

        #expect(await cache.cachedURL(forSongId: "first", serverId: serverID) == firstURL)
        #expect(await cache.cachedURL(forSongId: "second", serverId: serverID) == nil)
        #expect(await cache.cachedURL(forSongId: "third", serverId: serverID) == thirdURL)
        #expect(await cache.usedBytes == 20)
        #expect(!FileManager.default.fileExists(atPath: secondURL.path))

        await cache.clearAllForServer(serverID)
    }

    // MARK: - Quality

    private func makeCache(maxBytes: Int64 = AudioStreamCache.defaultMaxBytes) throws -> AudioStreamCache {
        let container = try ModelContainer(
            for: Schema([CachedTrack.self, CachedLyrics.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return AudioStreamCache(modelContainer: container, maxBytes: maxBytes)
    }

    @Test func aCellularTranscodeNeverReplacesAWiFiOriginal() async throws {
        let cache = try makeCache()
        let serverID = UUID()
        let original = try await cache.store(fileAt: makeTemporaryFile(size: 40), forSongId: "song", serverId: serverID,
                                             mimeType: "audio/flac", quality: .original)
        let transcodeSource = try makeTemporaryFile(size: 8)
        let kept = try await cache.store(fileAt: transcodeSource, forSongId: "song", serverId: serverID,
                                         mimeType: "audio/mpeg", quality: .lossy(kbps: 192))
        #expect(kept == original)
        #expect(!FileManager.default.fileExists(atPath: transcodeSource.path))
        #expect(await cache.cachedEntry(forSongId: "song", serverId: serverID) == CachedAudioEntry(url: original, quality: .original))
        #expect(await cache.usedBytes == 40)
        await cache.clearAll()
    }

    @Test func aBetterCopyReplacesATranscode() async throws {
        let cache = try makeCache()
        let serverID = UUID()
        let transcode = try await cache.store(fileAt: makeTemporaryFile(size: 8), forSongId: "song", serverId: serverID,
                                              mimeType: "audio/mpeg", quality: .lossy(kbps: 192))
        #expect(await cache.cachedEntry(forSongId: "song", serverId: serverID)?.quality == .lossy(kbps: 192))
        let better = try await cache.store(fileAt: makeTemporaryFile(size: 12), forSongId: "song", serverId: serverID,
                                           mimeType: "audio/mpeg", quality: .lossy(kbps: 320))
        let original = try await cache.store(fileAt: makeTemporaryFile(size: 40), forSongId: "song", serverId: serverID,
                                             mimeType: "audio/flac", quality: .original)
        #expect(better != transcode && original != better)
        #expect(!FileManager.default.fileExists(atPath: transcode.path))
        #expect(!FileManager.default.fileExists(atPath: better.path))
        #expect(await cache.cachedEntry(forSongId: "song", serverId: serverID) == CachedAudioEntry(url: original, quality: .original))
        #expect(await cache.trackCount == 1)
        await cache.clearAll()
    }

    @Test func copiesCachedBeforeQualitiesWereRecordedGiveWayOnlyToOriginals() async throws {
        let cache = try makeCache()
        let serverID = UUID()
        let legacy = try await cache.store(fileAt: makeTemporaryFile(size: 20), forSongId: "song", serverId: serverID, mimeType: "audio/mpeg")
        #expect(await cache.cachedEntry(forSongId: "song", serverId: serverID)?.quality == .unrecorded)
        #expect(try await cache.store(fileAt: makeTemporaryFile(size: 8), forSongId: "song", serverId: serverID,
                                      mimeType: "audio/mpeg", quality: .lossy(kbps: 320)) == legacy)
        let original = try await cache.store(fileAt: makeTemporaryFile(size: 30), forSongId: "song", serverId: serverID,
                                             mimeType: "audio/flac", quality: .original)
        #expect(original != legacy)
        await cache.clearAll()
    }

    @Test func evictionKeepsSongsStillAheadInTheQueue() async throws {
        let cache = try makeCache(maxBytes: 24)
        let serverID = UUID()
        let first = try await cache.store(fileAt: makeTemporaryFile(size: 10), forSongId: "first", serverId: serverID, mimeType: "audio/mpeg")
        try await Task.sleep(for: .milliseconds(2))
        let second = try await cache.store(fileAt: makeTemporaryFile(size: 10), forSongId: "second", serverId: serverID, mimeType: "audio/mpeg")
        await cache.setProtectedSongIDs(["first"], serverId: serverID)
        try await Task.sleep(for: .milliseconds(2))
        _ = try await cache.store(fileAt: makeTemporaryFile(size: 10), forSongId: "third", serverId: serverID, mimeType: "audio/mpeg")
        // The least recently used song is upcoming, so the next one goes instead.
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(await cache.cachedBytes(forSongIds: ["first", "third"], serverId: serverID) == 20)
        #expect(await cache.cachedBytes(forSongIds: ["first", "third"], serverId: UUID()) == 0)
        await cache.clearAll()
    }

    @Test func qualityIsReadFromSubsonicStreamParameters() throws {
        let original = try #require(URL(string: "https://music.example/rest/stream?id=a&estimateContentLength=true"))
        let raw = try #require(URL(string: "https://music.example/rest/stream?id=a&format=raw"))
        let mp3 = try #require(URL(string: "https://music.example/rest/stream?id=a&maxBitRate=192&format=mp3"))
        #expect(CachedAudioQuality(streamURL: original) == .original)
        #expect(CachedAudioQuality(streamURL: raw) == .original)
        #expect(CachedAudioQuality(streamURL: mp3) == .lossy(kbps: 192))
        #expect(CachedAudioQuality(subsonicFormat: "opus", maxBitRate: 128) == .lossy(kbps: 128))
    }

    @Test func qualityRoundTripsThroughTheFileName() {
        for quality in [CachedAudioQuality.original, .lossy(kbps: 192), .lossy(kbps: 0)] {
            let name = quality.taggedFileName(stem: "\(UUID())-\(UUID())", extension: "mp3")
            #expect(name.hasSuffix(".mp3"))
            #expect(CachedAudioQuality(fileName: name) == quality)
        }
        #expect(CachedAudioQuality(fileName: "\(UUID())-\(UUID()).flac") == .unrecorded)
    }

    @Test func aCopySatisfiesAStreamOfEqualOrLowerQuality() {
        #expect(CachedAudioQuality.original.satisfies(.lossy(kbps: 192)))
        #expect(CachedAudioQuality.unrecorded.satisfies(.original))
        #expect(CachedAudioQuality.lossy(kbps: 320).satisfies(.lossy(kbps: 192)))
        #expect(CachedAudioQuality.lossy(kbps: 192).satisfies(.lossy(kbps: 192)))
        #expect(!CachedAudioQuality.lossy(kbps: 192).satisfies(.lossy(kbps: 320)))
        #expect(!CachedAudioQuality.lossy(kbps: 320).satisfies(.original))
    }
}

@Suite("Media resolution with cached qualities")
@MainActor
struct QualityAwareResolutionTests {
    private func makeResolver() throws -> (MediaResolver, AudioStreamCache, MockServerService, UUID) {
        let models = try ModelContainer.minidisc(inMemory: true)
        let server = MockServerService()
        let snapshot = ServerSnapshot(from: ServerConfig(displayName: "Fixture", baseURL: "https://example.invalid", username: "alice"))
        server.state.activeServer = snapshot
        server.state.activeConnectionVersion = .init(serverID: snapshot.id, revision: 1)
        server.connection = try ServerConnection(version: server.state.activeConnectionVersion!, server: snapshot,
                                                 credentials: ServerCredentials(password: "fixture", customHeaders: [:]))
        let cache = AudioStreamCache(modelContainer: models)
        let downloads = DownloadService(serverService: server, modelContainer: models, toastService: ToastService())
        // Default stream settings: originals on Wi-Fi.
        let resolver = MediaResolver(downloadService: downloads, audioStreamCache: cache, serverService: server,
                                     serverState: server.state, streamSettings: StreamSettings(defaults: UserDefaults(suiteName: "QualityResolution.\(UUID())")!))
        return (resolver, cache, server, snapshot.id)
    }

    private func file(size: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quality-\(UUID()).tmp")
        try Data(repeating: 0x41, count: size).write(to: url)
        return url
    }

    @Test func aCellularTranscodeStreamsTheOriginalOnWiFiButPlaysOffline() async throws {
        let (resolver, cache, server, serverID) = try makeResolver()
        defer { Task { await cache.clearAll() } }
        let cached = try await cache.store(fileAt: file(size: 8), forSongId: "song", serverId: serverID,
                                           mimeType: "audio/mpeg", quality: .lossy(kbps: 192))
        guard case .stream(let url, _) = try await resolver.resolve(songId: "song", serverId: serverID) else {
            Issue.record("A Wi-Fi original must stream rather than replay the cellular transcode")
            return
        }
        #expect(CachedAudioQuality(streamURL: url) == .original)
        #expect(!(await resolver.hasLocalCopy(songId: "song", serverId: serverID, atLeast: .original)))
        #expect(await resolver.hasLocalCopy(songId: "song", serverId: serverID, atLeast: .lossy(kbps: 192)))
        #expect(await resolver.localSource(songId: "song", serverId: serverID)?.url == cached)

        server.state.isOnline = false
        guard case .cached(let offline) = try await resolver.resolve(songId: "song", serverId: serverID) else {
            Issue.record("Offline, any complete copy must play")
            return
        }
        #expect(offline == cached)
    }

    @Test func anOriginalCopyPlaysWithoutTheNetwork() async throws {
        let (resolver, cache, _, serverID) = try makeResolver()
        defer { Task { await cache.clearAll() } }
        let cached = try await cache.store(fileAt: file(size: 8), forSongId: "song", serverId: serverID,
                                           mimeType: "audio/flac", quality: .original)
        guard case .cached(let url) = try await resolver.resolve(songId: "song", serverId: serverID) else {
            Issue.record("An original copy satisfies every stream quality")
            return
        }
        #expect(url == cached)
    }
}
