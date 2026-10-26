import Foundation
import Observation
import Testing
import UIKit
@testable import Minidisc

nonisolated private let observationArtworkData = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="
)!

// Observation calls onChange synchronously from the mutation, here always on the main actor.
nonisolated private final class ChangeFlag: @unchecked Sendable {
    var changed = false
}

@MainActor
@Suite("ArtworkImageCache observation")
struct ArtworkImageCacheObservationTests {
    private func makeCache() -> ArtworkImageCache {
        ArtworkImageCache(
            revalidationStore: CoverRevalidationStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            coverArtURLProvider: { id, _ in URL(string: "https://example.com/\(id)") },
            dataLoader: { request in
                (observationArtworkData, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            imageDecoder: { data, _ in PlatformImage(data: data) }
        )
    }

    // A pushed playlist reads its initial cover in a body. Loading the track covers while
    // scrolling must not re-run that body: it rebuilt the whole track list once per cover.
    @Test("a synchronous cover read is not invalidated when other covers load")
    func syncReadIsNotInvalidatedByOtherLoads() async {
        let cache = makeCache()
        #expect(await cache.load(coverArtId: "playlist") != nil)

        let flag = ChangeFlag()
        let initial = withObservationTracking {
            cache.cachedImage(for: "playlist")
        } onChange: {
            flag.changed = true
        }
        #expect(initial != nil)

        for index in 0..<5 {
            #expect(await cache.load(coverArtId: "track-\(index)") != nil)
        }
        #expect(!flag.changed)
    }
}
