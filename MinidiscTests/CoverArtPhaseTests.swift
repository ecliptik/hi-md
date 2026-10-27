import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Minidisc

/// The one decision between a cover, the loading tile and the MiniDisc.
@Suite("Cover art phase")
struct CoverArtPhaseTests {
    @Test("No cover id is missing")
    func noIdIsMissing() {
        #expect(CoverArtPhase.resolve(id: nil, hasImage: false, isKnownMissing: false) == .missing)
        #expect(CoverArtPhase.resolve(id: "", hasImage: false, isKnownMissing: false) == .missing)
    }

    @Test("A cover that may still arrive is loading, not missing")
    func loadingIsNotMissing() {
        #expect(CoverArtPhase.resolve(id: "al-1", hasImage: false, isKnownMissing: false) == .loading)
    }

    @Test("A cover known to be missing is missing")
    func knownMissingIsMissing() {
        #expect(CoverArtPhase.resolve(id: "al-1", hasImage: false, isKnownMissing: true) == .missing)
    }

    @Test("An image in hand wins")
    func imageWins() {
        #expect(CoverArtPhase.resolve(id: "al-1", hasImage: true, isKnownMissing: false) == .image)
        #expect(CoverArtPhase.resolve(id: "al-1", hasImage: true, isKnownMissing: true) == .image)
    }

    @Test("Albums, songs and playlists get the disc; artists and stations keep their symbol")
    func placeholders() {
        #expect(CoverArtPlaceholder(symbol: CoverArtPlaceholder.defaultSymbol) == .disc)
        #expect(CoverArtPlaceholder(symbol: MinidiscSymbol.album) == .disc)
        #expect(CoverArtPlaceholder(symbol: MinidiscSymbol.albumFill) == .disc)
        #expect(CoverArtPlaceholder(symbol: "person.fill") == .symbol("person.fill"))
        #expect(CoverArtPlaceholder(symbol: "music.microphone") == .symbol("music.microphone"))
        #expect(CoverArtPlaceholder(symbol: "antenna.radiowaves.left.and.right") == .symbol("antenna.radiowaves.left.and.right"))
    }
}

nonisolated private let onePixelPNG = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="
)!

/// Counts requests and lets a test hold one open.
nonisolated private final class FakeCoverServer: @unchecked Sendable {
    enum Answer { case image, status(Int), transportError, garbage }

    private let lock = NSLock()
    private var answer: Answer
    private var requests = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var holds = false

    init(_ answer: Answer, holds: Bool = false) {
        self.answer = answer
        self.holds = holds
    }

    var requestCount: Int { lock.withLock { requests } }
    var isHolding: Bool { lock.withLock { gate != nil } }

    func release() {
        let gate = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            holds = false
            defer { self.gate = nil }
            return self.gate
        }
        gate?.resume()
    }

    func respond(to request: URLRequest) async throws -> (Data, URLResponse) {
        let (answer, holds) = lock.withLock { () -> (Answer, Bool) in
            requests += 1
            return (self.answer, self.holds)
        }
        if holds {
            await withCheckedContinuation { continuation in lock.withLock { gate = continuation } }
        }
        let url = request.url!
        switch answer {
        case .image:
            return (onePixelPNG, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        case .status(let code):
            return (Data(), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
        case .transportError:
            throw URLError(.notConnectedToInternet)
        case .garbage:
            return (Data([0, 1, 2, 3]), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
}

/// The cache records a cover it couldn't load, so views show the disc and lists don't ask again.
@MainActor
@Suite("Missing cover cache", .serialized)
struct MissingCoverCacheTests {
    private func makeCache(_ server: FakeCoverServer) -> ArtworkImageCache {
        let cache = ArtworkImageCache(
            revalidationStore: CoverRevalidationStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("MissingCoverCacheTests.\(UUID())")
            ),
            coverArtURLProvider: { id, size in URL(string: "https://example.invalid/\(id)/\(size)") },
            dataLoader: { request in try await server.respond(to: request) },
            imageDecoder: { data, _ in PlatformImage(data: data) }
        )
        cache.persistCoversEnabled = false
        return cache
    }

    @Test("No id is missing without a request")
    func noIdIsMissing() async {
        let server = FakeCoverServer(.image)
        let cache = makeCache(server)
        #expect(cache.phase(for: nil) == .missing)
        #expect(cache.phase(for: "") == .missing)
        #expect(await cache.load(coverArtId: nil) == nil)
        #expect(server.requestCount == 0)
    }

    @Test("A cover the server doesn't have is missing, and isn't requested again", arguments: [404, 410])
    func notFoundIsMissingAndCached(status: Int) async {
        let server = FakeCoverServer(.status(status))
        let cache = makeCache(server)
        #expect(await cache.load(coverArtId: "al-gone") == nil)
        #expect(cache.phase(for: "al-gone") == .missing)
        #expect(cache.isMissing("al-gone"))
        #expect(cache.hasNoArtwork("al-gone"))

        #expect(await cache.load(coverArtId: "al-gone") == nil)
        #expect(await cache.load(coverArtId: "al-gone", tier: .hero) == nil)
        #expect(server.requestCount == 1)
    }

    @Test("Bytes that aren't an image are a missing cover")
    func undecodableIsMissing() async {
        let server = FakeCoverServer(.garbage)
        let cache = makeCache(server)
        #expect(await cache.load(coverArtId: "al-junk") == nil)
        #expect(cache.phase(for: "al-junk") == .missing)
        #expect(await cache.load(coverArtId: "al-junk") == nil)
        #expect(server.requestCount == 1)
    }

    @Test("A failed request shows the disc and is retried later, not on every pass")
    func transportFailureIsMissingButNotTheServersAnswer() async {
        let server = FakeCoverServer(.transportError)
        let cache = makeCache(server)
        #expect(await cache.load(coverArtId: "al-offline") == nil)
        #expect(cache.phase(for: "al-offline") == .missing)
        // Not the server's answer: the Lock Screen still tries its own loader.
        #expect(!cache.hasNoArtwork("al-offline"))
        #expect(await cache.load(coverArtId: "al-offline") == nil)
        #expect(server.requestCount == 1)
    }

    @Test("A server error is retried sooner than a missing cover, but still remembered")
    func serverErrorIsMissing() async {
        let server = FakeCoverServer(.status(503))
        let cache = makeCache(server)
        #expect(await cache.load(coverArtId: "al-busy") == nil)
        #expect(cache.phase(for: "al-busy") == .missing)
        #expect(!cache.hasNoArtwork("al-busy"))
        #expect(await cache.load(coverArtId: "al-busy") == nil)
        #expect(server.requestCount == 1)
    }

    @Test("A cover still loading is not missing")
    func loadingIsNotMissing() async throws {
        let server = FakeCoverServer(.image, holds: true)
        let cache = makeCache(server)
        let load = Task { await cache.load(coverArtId: "al-slow") }
        for _ in 0..<200 where !server.isHolding { try await Task.sleep(for: .milliseconds(10)) }
        try #require(server.isHolding)
        #expect(cache.phase(for: "al-slow") == .loading)
        #expect(!cache.isMissing("al-slow"))
        server.release()
        #expect(await load.value != nil)
        #expect(cache.phase(for: "al-slow") == .image)
    }

    @Test("A cover that loads is an image, and a cancelled load isn't recorded as missing")
    func successAndCancellation() async throws {
        let server = FakeCoverServer(.image)
        let cache = makeCache(server)
        #expect(await cache.load(coverArtId: "al-ok") != nil)
        #expect(cache.phase(for: "al-ok") == .image)
        #expect(!cache.isMissing("al-ok"))

        let held = FakeCoverServer(.transportError, holds: true)
        let heldCache = makeCache(held)
        let load = Task { await heldCache.load(coverArtId: "al-cancelled") }
        for _ in 0..<200 where !held.isHolding { try await Task.sleep(for: .milliseconds(10)) }
        load.cancel()
        held.release()
        _ = await load.value
        // Let the abandoned fetch finish before checking it left nothing behind.
        for _ in 0..<50 where heldCache.completedLoads() == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!heldCache.isMissing("al-cancelled"))
        #expect(heldCache.phase(for: "al-cancelled") == .loading)
    }

    @Test("A view's own failed request is remembered once")
    func viewFailureIsRemembered() {
        let cache = makeCache(FakeCoverServer(.image))
        cache.noteLoadFailed("al-async")
        #expect(cache.phase(for: "al-async") == .missing)
        #expect(!cache.hasNoArtwork("al-async"))
        cache.noteLoadFailed("")
        #expect(!cache.isMissing(""))
    }

    @Test("Invalidating a cover (a new upload) forgets that it was missing")
    func invalidationForgets() async {
        let server = FakeCoverServer(.status(404))
        let cache = makeCache(server)
        _ = await cache.load(coverArtId: "al-new")
        #expect(cache.isMissing("al-new"))
        await cache.invalidate(for: "al-new")
        #expect(cache.phase(for: "al-new") == .loading)
    }
}

/// What a cover draws on the pass it mounts (`ImageRenderer` runs no tasks).
@MainActor
@Suite("Missing cover view")
struct MissingCoverViewTests {
    @Test("A cover known to be missing draws the disc at once; one that may still load draws the tile")
    func knownMissingDrawsTheDisc() async throws {
        let cache = ArtworkImageCache(
            revalidationStore: CoverRevalidationStore(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("MissingCoverViewTests.\(UUID())")
            ),
            coverArtURLProvider: { id, size in URL(string: "https://example.invalid/\(id)/\(size)") },
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            },
            imageDecoder: { data, _ in PlatformImage(data: data) }
        )
        cache.persistCoversEnabled = false
        _ = await cache.load(coverArtId: "al-gone")
        try #require(cache.isMissing("al-gone"))

        let missing = try #require(render(CoverArtView(id: "al-gone", size: 160), cache: cache))
        let loading = try #require(render(CoverArtView(id: "al-unknown", size: 160), cache: cache))
        let noId = try #require(render(CoverArtView(id: "", size: 160), cache: cache))
        #expect(opaqueShare(missing) > 0.5)
        #expect(opaqueShare(noId) > 0.5)
        #expect(opaqueShare(loading) < 0.05)

        // An artist keeps its symbol: no photo of a disc.
        let artist = try #require(render(CoverArtView(id: "al-gone", size: 160, placeholderSystemImage: "person.fill"), cache: cache))
        #expect(opaqueShare(artist) < opaqueShare(missing))
    }

    @Test("The disc palette is the gold of the Lock Screen's no-artwork image")
    func discPaletteIsGold() async throws {
        let colors = try #require(await FullPlayerViewModel.discColors(DominantColorExtractor()))
        #expect(!colors.isEmpty)
        let resolved = colors.map { $0.resolve(in: EnvironmentValues()) }
        let warm = resolved.filter { $0.red > $0.blue }
        #expect(warm.count * 2 >= resolved.count)
    }

    private func render(_ view: CoverArtView, cache: ArtworkImageCache) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 80, height: 80).environment(cache))
        renderer.scale = 1
        return renderer.uiImage
    }

    /// The share of pixels drawn nearly opaque: the disc photo covers most of the tile; the
    /// loading tile is a faint wash.
    private func opaqueShare(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        var opaque = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 200 { opaque += 1 }
        return Double(opaque) / Double(width * height)
    }
}
