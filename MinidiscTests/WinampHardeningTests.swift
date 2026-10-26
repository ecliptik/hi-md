import CoreGraphics
import Foundation
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
}
