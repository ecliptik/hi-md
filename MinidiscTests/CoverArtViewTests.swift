import SwiftUI
import Testing
import UIKit
@testable import Minidisc

/// `ImageRenderer` draws a single body pass and never runs tasks, so it shows what a cover looks
/// like on the frame it mounts.
@Suite("Cover art view")
@MainActor
struct CoverArtViewTests {
    @Test("A RAM-cache hit renders on the first pass")
    func ramHitRendersImmediately() async throws {
        let cache = try await makeCache(loaded: "al-red")
        let hit = try #require(render(CoverArtView(id: "al-red", size: 88), cache: cache))
        #expect(isRed(hit))
    }

    @Test("A miss, or a row that isn't loading yet, shows the placeholder rather than a stale hit")
    func missRendersPlaceholder() async throws {
        let cache = try await makeCache(loaded: "al-red")
        let miss = try #require(render(CoverArtView(id: "al-other", size: 88), cache: cache))
        #expect(!isRed(miss))
        let deferred = try #require(render(CoverArtView(id: "al-red", size: 88, loadingEnabled: false), cache: cache))
        #expect(!isRed(deferred))
    }

    @Test("The hero tier doesn't borrow the thumbnail on the first pass")
    func tierIsRespected() async throws {
        let cache = try await makeCache(loaded: "al-red")
        let hero = try #require(render(CoverArtView(id: "al-red", size: 600), cache: cache))
        #expect(!isRed(hero))
    }

    @Test("The player's cross-fading cover draws a RAM-cache hit on the first pass, and a miss as the placeholder")
    func crossfadingCoverRendersImmediately() async throws {
        let cache = try await makeCache(loaded: "al-red")
        let hit = try #require(render(CoverArtView(id: "al-red", size: 88, crossfades: true), cache: cache))
        #expect(isRed(hit))
        let miss = try #require(render(CoverArtView(id: "al-other", size: 88, crossfades: true), cache: cache))
        #expect(!isRed(miss))
    }

    /// The Mac's Favorites crash: AppKit laid out a table cell's own hosting view before the
    /// table's environment reached it, and the cover's required cache read trapped ("No Observable
    /// object of type ArtworkImageCache found"). ImageRenderer has no app environment either.
    @Test("A cover with no cache in its environment draws its loading tile instead of trapping")
    func missingCacheDoesNotTrap() throws {
        for cover in [CoverArtView(id: "al-red", size: 88), CoverArtView(id: "al-red", size: 88, crossfades: true),
                      CoverArtView(id: "", size: 88), CoverArtView(id: "ar-1", size: 88, placeholderSystemImage: "music.microphone")] {
            let renderer = ImageRenderer(content: cover.frame(width: 44, height: 44))
            renderer.scale = 1
            let image = try #require(renderer.uiImage)
            #expect(!isRed(image))
        }
    }

    @Test("The environment's cache comes first, and no cache anywhere gives none")
    func cacheResolution() async throws {
        let cache = try await makeCache(loaded: "al-red")
        #expect(CoverArtView.cache(environment: cache, container: nil) === cache)
        #expect(CoverArtView.cache(environment: nil, container: nil) == nil)
    }

    // MARK: - Helpers

    private func makeCache(loaded id: String) async throws -> ArtworkImageCache {
        let red = solidImage(side: 240)
        let cache = ArtworkImageCache(
            revalidationStore: CoverRevalidationStore(fileURL: URL.temporaryDirectory.appendingPathComponent("CoverArtViewTests.\(UUID())")),
            coverArtURLProvider: { id, size in URL(string: "https://example.invalid/\(id)/\(size)") },
            dataLoader: { request in
                (Data([1]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                            headerFields: ["Cache-Control": "max-age=31536000"])!)
            },
            imageDecoder: { _, _ in red }
        )
        cache.persistCoversEnabled = false
        try #require(await cache.load(coverArtId: id, tier: .thumb) != nil)
        return cache
    }

    private func render(_ view: CoverArtView, cache: ArtworkImageCache) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 44, height: 44).environment(cache))
        renderer.scale = 1
        return renderer.uiImage
    }

    private func solidImage(side: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// Whether the centre pixel is the solid red test cover.
    private func isRed(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
            context.draw(cgImage, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            return true
        }
        return drawn && pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60
    }
}
