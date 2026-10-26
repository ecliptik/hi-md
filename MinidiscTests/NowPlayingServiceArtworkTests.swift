#if canImport(NowPlaying)
import Foundation
import NowPlaying
import Testing
import UIKit
@testable import Minidisc

nonisolated private let coverFixture = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="
)!

/// Holds every cover request until the test answers it, like a slow or unreachable server.
private actor HeldCoverRequests {
    private var pending: [(id: String, continuation: CheckedContinuation<(Data, URLResponse), Error>)] = []
    private var requested: [String] = []

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let id = request.url?.lastPathComponent ?? ""
        requested.append(id)
        return try await withCheckedThrowingContinuation { pending.append((id, $0)) }
    }

    func answer(_ id: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        let url = URL(string: "https://music.invalid/cover/\(id)")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        request.continuation.resume(returning: (coverFixture, response))
    }

    func requests() -> [String] { requested }
}

@MainActor
private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

@Suite("Now Playing artwork", .timeLimit(.minutes(1)))
@MainActor
struct NowPlayingServiceArtworkTests {
    private let player = MockPlayerService()

    private func snapshot(_ songId: String, title: String) -> NowPlayingSnapshot {
        NowPlayingSnapshot(title: title, artist: "Artist", album: "Album", duration: 200, position: 30,
                           playbackRate: 0, artworkURL: nil, artworkHeaders: [:], coverArtId: "cover-\(songId)",
                           isLiveStream: false, radioStationName: nil, songId: songId)
    }

    private func revalidationStore() -> CoverRevalidationStore {
        CoverRevalidationStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    }

    private func cache(
        requests: HeldCoverRequests,
        revalidationStore: CoverRevalidationStore? = nil,
        diskCover: @escaping @Sendable (String) async -> URL? = { _ in nil }
    ) -> ArtworkImageCache {
        ArtworkImageCache(
            revalidationStore: revalidationStore ?? self.revalidationStore(),
            coverArtURLProvider: { id, _ in URL(string: "https://music.invalid/cover/\(id)") },
            localCoverURLProvider: diskCover,
            dataLoader: { try await requests.load($0) },
            imageDecoder: { data, _ in PlatformImage(data: data) }
        )
    }

    private func content(_ presenter: NowPlayingCenterPresenter) -> MusicContent? {
        presenter.model.content as? MusicContent
    }

    @Test("The song is published while its cover is still downloading")
    func restoreDoesNotWaitForArtwork() async throws {
        let requests = HeldCoverRequests()
        let presenter = NowPlayingCenterPresenter()
        let service = NowPlayingService(playerService: player, artworkImageCache: cache(requests: requests),
                                        presenter: presenter)

        // Returns although the server has not answered the cover request.
        await service.update(with: snapshot("a", title: "Restored"))
        #expect(content(presenter)?.songTitle == "Restored")
        #expect(content(presenter)?.artwork == nil)

        #expect(await eventually { await requests.requests() == ["cover-a"] })
        await requests.answer("cover-a")
        #expect(await eventually { content(presenter)?.artwork?.id == "cover-a" })
    }

    @Test("A late cover for the previous song never lands on the next one")
    func staleArtworkIsDropped() async throws {
        let requests = HeldCoverRequests()
        let presenter = NowPlayingCenterPresenter()
        let service = NowPlayingService(playerService: player, artworkImageCache: cache(requests: requests),
                                        presenter: presenter)

        await service.update(with: snapshot("a", title: "First"))
        #expect(await eventually { await requests.requests().contains("cover-a") })
        await service.update(with: snapshot("b", title: "Second"))
        #expect(await eventually { await requests.requests().contains("cover-b") })

        await requests.answer("cover-a")
        try await Task.sleep(for: .milliseconds(100))
        #expect(content(presenter)?.songTitle == "Second")
        #expect(content(presenter)?.artwork == nil)

        await requests.answer("cover-b")
        #expect(await eventually { content(presenter)?.artwork?.id == "cover-b" })
    }

    @Test("A cover saved on disk is used without asking the server")
    func diskCoverComesFirst() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try coverFixture.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let requests = HeldCoverRequests()
        // Checked recently, so the disk hit doesn't also start a background freshness check.
        let checked = revalidationStore()
        checked.record(id: "cover-a", lastModified: "Mon, 26 Oct 2026 08:00:00 GMT")
        let presenter = NowPlayingCenterPresenter()
        let service = NowPlayingService(
            playerService: player,
            artworkImageCache: cache(requests: requests, revalidationStore: checked, diskCover: { _ in file }),
            presenter: presenter
        )

        await service.update(with: snapshot("a", title: "Offline"))
        #expect(await eventually { content(presenter)?.artwork?.id == "cover-a" })
        #expect(await requests.requests().isEmpty)
    }
}
#endif
