import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

/// Cached copies against the streams the thresholds ask for: a copy is used only when it is at
/// least as good as the request (the original, or a conversion at the chosen bitrate).
@Suite("Media resolution with thresholds and cached qualities")
@MainActor
struct ThresholdResolutionTests {
    private let flac = StreamSourceTraits(suffix: "flac", bitRate: 900)

    private func makeResolver() throws -> (MediaResolver, AudioStreamCache, StreamSettings, UUID) {
        let models = try ModelContainer.minidisc(inMemory: true)
        let server = MockServerService()
        let snapshot = ServerSnapshot(from: ServerConfig(displayName: "Fixture", baseURL: "https://example.invalid", username: "alice"))
        server.state.activeServer = snapshot
        server.state.activeConnectionVersion = .init(serverID: snapshot.id, revision: 1)
        server.connection = try ServerConnection(version: server.state.activeConnectionVersion!, server: snapshot,
                                                 credentials: ServerCredentials(password: "fixture", customHeaders: [:]))
        let cache = AudioStreamCache(modelContainer: models)
        let downloads = DownloadService(serverService: server, modelContainer: models, toastService: ToastService())
        let settings = StreamSettings(defaults: UserDefaults(suiteName: "ThresholdResolution.\(UUID())")!, downmix: DownmixParameters())
        let resolver = MediaResolver(downloadService: downloads, audioStreamCache: cache, serverService: server,
                                     serverState: server.state, streamSettings: settings)
        return (resolver, cache, settings, snapshot.id)
    }

    private func file() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("threshold-\(UUID()).tmp")
        try Data(repeating: 0x41, count: 8).write(to: url)
        return url
    }

    @Test("Conversion requests read as their bitrate, originals as the original")
    func requestQualities() {
        let client = SwiftSonicTestClient.make()
        let opus = MediaResolver.streamURL(client: client, songId: "s", request: .converted(to: .opus, at: .kbps128))!
        let raw = MediaResolver.streamURL(client: client, songId: "s", request: .original)!
        #expect(CachedAudioQuality(streamURL: opus) == .lossy(kbps: 128))
        #expect(CachedAudioQuality(streamURL: raw) == .original)
    }

    @Test("On cellular a cached conversion at the conversion bitrate plays; on Wi-Fi the original streams")
    func cellularConversionCopy() async throws {
        let (resolver, cache, settings, serverID) = try makeResolver()
        defer { Task { await cache.clearAll() } }
        settings.cellularThreshold = .kbps320
        settings.conversionBitrate = .kbps128
        let cached = try await cache.store(fileAt: file(), forSongId: "song", serverId: serverID,
                                           mimeType: "audio/ogg", quality: .lossy(kbps: 128))

        settings.networkPathDidChange(isCellular: true)
        guard case .cached(let url) = try await resolver.resolve(songId: "song", serverId: serverID, traits: flac) else {
            Issue.record("A copy at the conversion bitrate satisfies the cellular request")
            return
        }
        #expect(url == cached)

        // A higher conversion bitrate is a better stream than the copy, so it streams again.
        settings.conversionBitrate = .kbps192
        guard case .stream(let higher, _) = try await resolver.resolve(songId: "song", serverId: serverID, traits: flac) else {
            Issue.record("A 128 kbps copy must not stand in for a 192 kbps conversion")
            return
        }
        #expect(CachedAudioQuality(streamURL: higher) == .lossy(kbps: 192))

        settings.networkPathDidChange(isCellular: false)
        guard case .stream(let original, _) = try await resolver.resolve(songId: "song", serverId: serverID, traits: flac) else {
            Issue.record("On Wi-Fi at Maximum the original must stream")
            return
        }
        #expect(CachedAudioQuality(streamURL: original) == .original)
    }

    @Test("A song under the threshold asks for its original, which a conversion can't stand in for")
    func originalUnderThreshold() async throws {
        let (resolver, cache, settings, serverID) = try makeResolver()
        defer { Task { await cache.clearAll() } }
        settings.cellularThreshold = .kbps320
        settings.networkPathDidChange(isCellular: true)
        _ = try await cache.store(fileAt: file(), forSongId: "song", serverId: serverID,
                                  mimeType: "audio/ogg", quality: .lossy(kbps: 128))
        let mp3 = StreamSourceTraits(suffix: "mp3", bitRate: 256)
        guard case .stream(let url, _) = try await resolver.resolve(songId: "song", serverId: serverID, traits: mp3) else {
            Issue.record("A 256 kbps MP3 under a 320 kbps threshold streams as itself")
            return
        }
        #expect(CachedAudioQuality(streamURL: url) == .original)
    }
}

private enum SwiftSonicTestClient {
    static func make() -> SwiftSonicClient {
        SwiftSonicClient(configuration: ServerConfiguration(serverURL: URL(string: "https://music.example.com")!, username: "u", password: "p"))
    }
}
