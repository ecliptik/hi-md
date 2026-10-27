import CoreGraphics
import Foundation
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

/// Hostile skins and playlists: limits that keep malformed files from trapping or allocating
/// without bound.
@Suite("Winamp file limits")
struct WinampHardeningTests {
    // MARK: region.txt

    @Test func hugeRegionPointCountsAreRejectedWithoutTrapping() {
        let huge = Int.max / 2 + 1
        #expect(WinampRegions.parse("[Normal]\nNumPoints=\(huge)\nPointList=0,0, 1,0, 1,1\n").isEmpty)
        #expect(WinampRegions.parse("[Normal]\nNumPoints=\(Int.max)\nPointList=0,0\n").isEmpty)
        // A later polygon that overruns the list rejects the whole section, not just its tail.
        let overrun = "[Normal]\nNumPoints=3, \(huge)\nPointList=0,0, 5,0, 5,5, 9,9\n[WindowShade]\nNumPoints=3\nPointList=0,0, 5,0, 5,5\n"
        let regions = WinampRegions.parse(overrun)
        #expect(regions["normal"] == nil)
        #expect(regions["windowshade"]?.first?.count == 3)
    }

    // MARK: Analyser levels

    @Test("A non-finite analyser level draws an empty bar instead of trapping in Int(NaN)")
    func nonFiniteLevelsDrawEmptyBars() {
        #expect(WinampMainRenderer.level(.nan, rows: 16) == 0)
        #expect(WinampMainRenderer.level(.infinity, rows: 16) == 0)
        #expect(WinampMainRenderer.level(-.infinity, rows: 16) == 0)
        #expect(WinampMainRenderer.level(0.5, rows: 16) == 8)
        #expect(WinampMainRenderer.level(2, rows: 16) == 16)
        #expect(WinampMainRenderer.level(-1, rows: 16) == 0)
    }

    // MARK: Skin bitmaps

    @Test func onlyBitmapsWithTheBMMagicNumberAreDecoded() {
        let bmp = makeBMP(width: 4, height: 3) { _, _ in (255, 0, 0) }
        #expect(WinampSkin.image(fromBMP: bmp)?.width == 4)
        var renamed = bmp
        renamed[0] = 0x89 // a PNG's first byte
        #expect(WinampSkin.image(fromBMP: renamed) == nil)
        #expect(WinampSkin.image(fromBMP: Data()) == nil)
        #expect(WinampSkin.image(fromBMP: Data("BM".utf8)) == nil)
    }

    @Test func oversizedBitmapsAreRejectedFromTheHeader() {
        #expect(WinampSkin.image(fromBMP: makeBMP(width: 2048, height: 1) { _, _ in (0, 0, 255) })?.width == 2048)
        #expect(WinampSkin.image(fromBMP: makeBMP(width: 2049, height: 1) { _, _ in (0, 0, 255) }) == nil)
        #expect(WinampSkin.image(fromBMP: makeBMP(width: 1, height: 2049) { _, _ in (0, 0, 255) }) == nil)
        // A header-only file claiming a huge image never reaches ImageIO.
        var header = Data("BM".utf8) + Data(repeating: 0, count: 12)
        header += Data([40, 0, 0, 0, 0xFF, 0xFF, 0, 0, 1, 0, 0, 0])
        #expect(WinampSkin.bmpSize(header)?.width == 65_535)
        #expect(WinampSkin.image(fromBMP: header) == nil)
    }

    @Test func topDownBitmapsReportTheirHeight() {
        var bmp = makeBMP(width: 4, height: 3) { _, _ in (0, 255, 0) }
        // Height -3: rows stored top to bottom.
        bmp.replaceSubrange(22..<26, with: [0xFD, 0xFF, 0xFF, 0xFF])
        #expect(WinampSkin.bmpSize(bmp)?.width == 4)
        #expect(WinampSkin.bmpSize(bmp)?.height == 3)
    }

    @Test func oversizedSkinEntriesFallBack() throws {
        let fallback = try WinampSkin.bundled()
        var zip = TestZipWriter()
        // 1000×700 at 24 bits is about 2.1 MB, over the image cap.
        zip.add("main.bmp", makeBMP(width: 1000, height: 700) { _, _ in (255, 0, 0) })
        zip.add("viscolor.txt", Data(("1,2,3\n" + String(repeating: "// padding\n", count: 7_000)).utf8))
        let archive = zip.archive()
        let parsed = try ZipArchive(data: archive)
        #expect(throws: ZipArchive.ZipError.tooLarge("main.bmp")) {
            try parsed.contents(named: "main.bmp", maximumSize: WinampSkin.maximumImageEntrySize)
        }
        #expect(throws: ZipArchive.ZipError.tooLarge("viscolor.txt")) {
            try parsed.contents(named: "viscolor.txt", maximumSize: WinampSkin.maximumTextEntrySize)
        }
        let skin = try WinampSkin.load(data: archive, name: "Big", fallback: fallback)
        #expect(skin.sheets[.main] === fallback.sheets[.main])
        #expect(skin.visColors == fallback.visColors)
    }

    // MARK: Skin archives

    @Test func archivesOverTheCapAreRefused() throws {
        let oversized = Data(count: ZipArchive.maximumArchiveSize + 1)
        #expect(throws: ZipArchive.ZipError.tooLarge("archive")) { try ZipArchive(data: oversized) }

        let url = FileManager.default.temporaryDirectory.appending(path: "oversized-\(UUID().uuidString).wsz")
        try oversized.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ZipArchive.ZipError.tooLarge(url.lastPathComponent)) {
            try WinampSkin.load(contentsOf: url)
        }
        // A normal skin is far below the cap.
        var zip = TestZipWriter()
        zip.add("readme.txt", Data("hello".utf8))
        #expect(try ZipArchive(data: zip.archive()).entries.count == 1)
    }

    // MARK: M3U durations

    @Test func extInfDurationsMustBeFiniteAndAtMostAWeek() {
        for bad in ["inf", "-inf", "nan", "1e30", "9223372036854775808", "604801", "-5"] {
            let entries = M3UPlaylist.decode(text: "#EXTM3U\n#EXTINF:\(bad),Artist - Title\nsong.mp3\n")
            #expect(entries.count == 1, "\(bad)")
            #expect(entries.first?.duration == nil, "\(bad)")
            #expect(entries.first?.displayTitle == "Artist - Title", "\(bad)")
        }
        #expect(M3UPlaylist.parseDuration("604800") == 604_800)
        #expect(M3UPlaylist.parseDuration("245.4") == 245)
        #expect(M3UPlaylist.parseDuration("0") == 0)
    }

    // MARK: M3U size and resolver concurrency

    @Test func playlistsAreCappedInSizeAndEntries() {
        let lines = (0..<6_000).map { "track\($0).mp3" }.joined(separator: "\n")
        let entries = M3UPlaylist.decode(text: lines)
        #expect(entries.count == M3UPlaylist.maximumEntries)
        #expect(entries.last?.location == "track4999.mp3")
        #expect(M3UPlaylist.decode(Data(lines.utf8)).count == M3UPlaylist.maximumEntries)

        var oversized = Data("#EXTM3U\nsong.mp3\n".utf8)
        oversized.append(Data(repeating: 0x23, count: M3UPlaylist.maximumFileSize)) // '#' comment bytes
        #expect(M3UPlaylist.decode(oversized).isEmpty)
    }

    @Test func resolverRunsAtMostFourLookupsAtOnceAndKeepsOrder() async throws {
        let lookup = CountingLookup()
        let entries = (0..<20).map { M3UPlaylist.Entry(location: M3UPlaylist.songURI(id: "song-\($0)")) }
        let resolutions = try await M3UPlaylistResolver(lookup: lookup).resolve(entries)
        #expect(resolutions.map(\.song?.id) == (0..<20).map { "song-\($0)" })
        #expect(resolutions.allSatisfy { $0.match == .songID })
        #expect(lookup.peak <= M3UPlaylistResolver.maximumConcurrentLookups)
        #expect(lookup.peak > 1)
        #expect(lookup.calls == 20)
    }

    @Test func resolverSharesOneSearchPerTitle() async throws {
        let lookup = CountingLookup()
        let entries = (0..<8).map { _ in M3UPlaylist.Entry(location: "Artist/Album/01 Same Title.mp3") }
        _ = try await M3UPlaylistResolver(lookup: lookup).resolve(entries)
        #expect(lookup.searches == 1)
    }
}

/// Answers every song ID after a short delay and counts how many lookups overlap.
private nonisolated final class CountingLookup: M3USongLookup, Sendable {
    private struct Counts {
        var active = 0
        var peak = 0
        var calls = 0
        var searches = 0
    }

    private let counts = Mutex(Counts())

    var peak: Int { counts.withLock { $0.peak } }
    var calls: Int { counts.withLock { $0.calls } }
    var searches: Int { counts.withLock { $0.searches } }

    func song(id: String) async throws -> Song? {
        counts.withLock { counts in
            counts.active += 1
            counts.calls += 1
            counts.peak = max(counts.peak, counts.active)
        }
        try await Task.sleep(for: .milliseconds(20))
        counts.withLock { $0.active -= 1 }
        return Song(id: id, title: "Title \(id)", isDir: false)
    }

    func searchSongs(_ query: String) async throws -> [Song] {
        counts.withLock { $0.searches += 1 }
        try await Task.sleep(for: .milliseconds(20))
        return []
    }
}
