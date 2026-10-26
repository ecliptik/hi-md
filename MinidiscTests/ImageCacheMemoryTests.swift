import Foundation
import Testing
import UIKit
@testable import Minidisc

@Suite("Image cache memory bounds")
@MainActor
struct ImageCacheMemoryTests {
    @Test("Lidarr covers are capped by decoded size and count")
    func lidarrStoreIsBounded() {
        let store = LidarrImageStore()
        let large = PerformanceFixtures.sharedBufferImages(count: 300, side: 1000)
        for (index, image) in large.enumerated() { store.store(image, for: "large-\(index)") }
        let retained = (0..<large.count).compactMap { store.image(for: "large-\($0)") }
        #expect(retained.map(\.decodedByteCount).reduce(0, +) <= LidarrImageStore.costLimit)
        #expect(!retained.isEmpty)

        let small = LidarrImageStore()
        let thumbs = PerformanceFixtures.sharedBufferImages(count: 200, side: 100)
        for (index, image) in thumbs.enumerated() { small.store(image, for: "small-\(index)") }
        let kept = (0..<thumbs.count).compactMap { small.image(for: "small-\($0)") }
        #expect(kept.count <= LidarrImageStore.countLimit)
        #expect(!kept.isEmpty)
        small.removeAll()
        #expect(small.image(for: "small-199") == nil)
    }

    @Test("Hero covers are capped by decoded size, and the newest survives")
    func artworkCacheIsCostBounded() async {
        let cache = makeCache()
        for index in 0..<110 { await cache.load(coverArtId: "al-\(index)", tier: .hero) }
        let heroes = (0..<110).compactMap { cache.cachedImage(for: "al-\($0)", tier: .hero) }
        #expect(heroes.map(\.decodedByteCount).reduce(0, +) <= 96 * 1_048_576)
        #expect(cache.cachedImage(for: "al-109", tier: .hero) != nil)
        #expect(cache.cachedImage(for: "al-0", tier: .hero) == nil)
    }

    @Test("Heroes over the byte budget evict older heroes, not list thumbnails")
    func heroChurnKeepsThumbnails() async {
        let cache = makeCache()
        for index in 0..<60 { await cache.load(coverArtId: "al-\(index)", tier: .thumb) }
        for index in 0..<40 { await cache.load(coverArtId: "hero-\(index)", tier: .hero) }
        #expect((0..<60).allSatisfy { cache.cachedImage(for: "al-\($0)", tier: .thumb) != nil })
        #expect(cache.cachedImage(for: "hero-39", tier: .hero) != nil)
        #expect(cache.cachedImage(for: "hero-0", tier: .hero) == nil)
    }

    @Test("Thumbnails still fill the count cap, as before")
    func thumbnailsKeepTheCountCap() async {
        let cache = makeCache()
        for index in 0..<130 { await cache.load(coverArtId: "al-\(index)", tier: .thumb) }
        let thumbs = (0..<130).compactMap { cache.cachedImage(for: "al-\($0)", tier: .thumb) }
        #expect(thumbs.count == 110)
        #expect(cache.cachedImage(for: "al-19", tier: .thumb) == nil)
        #expect(cache.cachedImage(for: "al-20", tier: .thumb) != nil)
    }

    @Test("A memory warning drops the hero tier and keeps thumbnails")
    func memoryWarningTrimsHeroes() async {
        let cache = makeCache()
        for index in 0..<5 {
            await cache.load(coverArtId: "al-\(index)", tier: .hero)
            await cache.load(coverArtId: "al-\(index)", tier: .thumb)
        }
        cache.trimForMemoryWarning()
        #expect((0..<5).allSatisfy { cache.cachedImage(for: "al-\($0)", tier: .hero) == nil })
        #expect((0..<5).allSatisfy { cache.cachedImage(for: "al-\($0)", tier: .thumb) != nil })
        // The access order stays consistent: later stores still evict normally.
        for index in 5..<120 { await cache.load(coverArtId: "al-\(index)", tier: .thumb) }
        #expect((0..<120).compactMap { cache.cachedImage(for: "al-\($0)", tier: .thumb) }.count == 110)
    }

    private func makeCache() -> ArtworkImageCache {
        let hero = PerformanceFixtures.sharedBufferImages(count: 1, side: 1200)[0]
        let thumb = PerformanceFixtures.sharedBufferImages(count: 1, side: 240)[0]
        let cache = ArtworkImageCache(
            revalidationStore: CoverRevalidationStore(fileURL: URL.temporaryDirectory.appendingPathComponent("ImageCacheMemoryTests.\(UUID())")),
            coverArtURLProvider: { id, size in URL(string: "https://example.invalid/\(id)/\(size)") },
            dataLoader: { request in
                (Data([1]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                            headerFields: ["Cache-Control": "max-age=31536000"])!)
            },
            imageDecoder: { _, size in size >= 1200 ? hero : thumb }
        )
        cache.persistCoversEnabled = false
        return cache
    }
}
