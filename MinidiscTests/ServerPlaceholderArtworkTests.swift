import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Minidisc

/// Drawn look-alikes of Navidrome's stand-in images (the real ones aren't bundled), plus ordinary
/// covers that must not be mistaken for them.
@Suite("Server placeholder artwork")
struct ServerPlaceholderArtworkTests {
    @Test(arguments: [300, 600, 1000])
    func recognisesTheAlbumRecord(side: Int) {
        #expect(ServerPlaceholderArtwork.matches(Self.record(side: side, background: nil)))
    }

    @Test func recognisesTheRecordWhateverItsCornersBecameWhenEncoded() {
        #expect(ServerPlaceholderArtwork.matches(Self.record(side: 600, background: (0, 0, 0))))
        #expect(ServerPlaceholderArtwork.matches(Self.record(side: 600, background: (255, 255, 255))))
    }

    @Test func recognisesTheArtistStar() {
        #expect(ServerPlaceholderArtwork.matches(Self.star(side: 300)))
    }

    @Test func recognisesEncodedBytes() throws {
        let data = try #require(UIImage(cgImage: Self.record(side: 600, background: (0, 0, 0))).jpegData(compressionQuality: 0.8))
        #expect(ServerPlaceholderArtwork.matches(imageData: data))
    }

    @Test func ignoresOrdinaryCovers() {
        #expect(!ServerPlaceholderArtwork.matches(Self.flat(side: 600, rgb: (4, 92, 212))))       // all blue, no label
        #expect(!ServerPlaceholderArtwork.matches(Self.flat(side: 600, rgb: (235, 235, 235))))    // plain grey
        #expect(!ServerPlaceholderArtwork.matches(Self.record(side: 600, background: nil, ring: (200, 40, 40)))) // a red record
        #expect(!ServerPlaceholderArtwork.matches(Self.record(side: 600, background: nil).cropping(
            to: CGRect(x: 0, y: 0, width: 600, height: 300))!))                                    // not square
    }

    @Test func ignoresTheAppsOwnLogo() throws {
        let logo = try #require(UIImage(named: "MinidiscLogo"))
        #expect(!ServerPlaceholderArtwork.matches(logo))
    }

    // MARK: - Drawing

    private static func context(side: Int) -> CGContext {
        CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func color(_ rgb: (Int, Int, Int)) -> CGColor {
        CGColor(srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1)
    }

    /// A blue record with a dark grey label, on transparent or solid corners.
    static func record(side: Int, background: (Int, Int, Int)?, ring: (Int, Int, Int) = (4, 92, 212)) -> CGImage {
        let ctx = context(side: side), s = CGFloat(side)
        if let background {
            ctx.setFillColor(color(background))
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        }
        ctx.setFillColor(color(ring))
        ctx.fillEllipse(in: CGRect(x: s * 0.03, y: s * 0.03, width: s * 0.94, height: s * 0.94))
        ctx.setFillColor(color((45, 44, 40)))
        ctx.fillEllipse(in: CGRect(x: s * 0.33, y: s * 0.33, width: s * 0.34, height: s * 0.34))
        ctx.setFillColor(color((10, 10, 10)))
        ctx.fillEllipse(in: CGRect(x: s * 0.48, y: s * 0.48, width: s * 0.04, height: s * 0.04))
        return ctx.makeImage()!
    }

    /// A white five-pointed star on light grey.
    static func star(side: Int) -> CGImage {
        let ctx = context(side: side), s = CGFloat(side)
        ctx.setFillColor(color((235, 235, 235)))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        let centre = CGPoint(x: s / 2, y: s / 2)
        let points = (0..<10).map { i -> CGPoint in
            let radius = (i.isMultiple(of: 2) ? 0.32 : 0.14) * s
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            return CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
        }
        ctx.addLines(between: points)
        ctx.closePath()
        ctx.setFillColor(color((255, 255, 255)))
        ctx.fillPath()
        return ctx.makeImage()!
    }

    static func flat(side: Int, rgb: (Int, Int, Int)) -> CGImage {
        let ctx = context(side: side)
        ctx.setFillColor(color(rgb))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }
}

@Suite("Server placeholder artwork in the cache")
@MainActor
struct ServerPlaceholderCacheTests {
    @Test func standInIsNotCachedOrPersistedAndIsNotFetchedAgainForAWhile() async throws {
        let data = try #require(UIImage(cgImage: ServerPlaceholderArtworkTests.record(side: 600, background: (0, 0, 0)))
            .jpegData(compressionQuality: 0.9))
        let counter = FetchCounter()
        let metadata = URL.temporaryDirectory.appendingPathComponent("ServerPlaceholderCacheTests.\(UUID())")
        defer { try? FileManager.default.removeItem(at: metadata) }
        let cache = ArtworkImageCache(
            revalidationStore: CoverRevalidationStore(fileURL: metadata),
            coverArtURLProvider: { _, _ in URL(string: "https://example.invalid/cover")! },
            persistCoverOperation: { _, _ in await counter.persisted() },
            dataLoader: { request in
                await counter.fetched()
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                               headerFields: ["Cache-Control": "public, max-age=31536000"])!
                return (data, response)
            },
            imageDecoder: { data, _ in PlatformImage(data: data) }
        )

        #expect(await cache.load(coverArtId: "al-missing") == nil)
        #expect(cache.hasNoArtwork("al-missing"))
        #expect(cache.cachedImage(for: "al-missing") == nil)
        #expect(await counter.persists == 0)

        // Within the recheck window the server isn't asked again.
        #expect(await cache.load(coverArtId: "al-missing") == nil)
        #expect(await counter.fetches == 1)
    }

    @Test func noStoreStandInIsShownAsMissingButAskedForAgain() async {
        let counter = FetchCounter()
        let metadata = URL.temporaryDirectory.appendingPathComponent("ServerPlaceholderCacheTests.\(UUID())")
        defer { try? FileManager.default.removeItem(at: metadata) }
        let cache = ArtworkImageCache(
            revalidationStore: CoverRevalidationStore(fileURL: metadata),
            coverArtURLProvider: { _, _ in URL(string: "https://example.invalid/cover")! },
            persistCoverOperation: { _, _ in },
            dataLoader: { request in
                await counter.fetched()
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                               headerFields: ["Cache-Control": "no-store"])!
                return (Data([1]), response)
            },
            imageDecoder: { _, _ in UIImage() }
        )
        #expect(await cache.load(coverArtId: "al-resolving") == nil)
        #expect(cache.hasNoArtwork("al-resolving"))
        #expect(await cache.load(coverArtId: "al-resolving") == nil)
        #expect(await counter.fetches == 2)
    }
}

private actor FetchCounter {
    private(set) var fetches = 0
    private(set) var persists = 0
    func fetched() { fetches += 1 }
    func persisted() { persists += 1 }
}
