import Foundation
import Testing
@testable import Minidisc

@Suite("AI recommendation share text")
struct AIRecommendationShareTextTests {
    private let inRainbows = AIRecommendation(artist: "Radiohead", album: "In Rainbows", year: 2007, reason: "Because you play OK Computer.")
    private let undated = AIRecommendation(artist: "Low", album: "Things We Lost in the Fire", year: nil, reason: " ")

    @Test func oneAlbumIsTitleReasonThenLinks() throws {
        let lines = AIRecommendationShareText.single(inRainbows).components(separatedBy: "\n")
        #expect(lines.count == 4)
        #expect(lines[0] == "In Rainbows — Radiohead (2007)")
        #expect(lines[1] == "Because you play OK Computer.")
        let bandcamp = try #require(AIRecommendationLinks.bandcamp(inRainbows))
        let musicBrainz = try #require(AIRecommendationLinks.musicBrainz(inRainbows))
        #expect(lines[2] == "Bandcamp: \(bandcamp.absoluteString)")
        #expect(lines[3] == "MusicBrainz: \(musicBrainz.absoluteString)")
    }

    @Test func missingYearAndBlankReasonAreLeftOut() {
        let lines = AIRecommendationShareText.single(undated).components(separatedBy: "\n")
        #expect(lines[0] == "Things We Lost in the Fire — Low")
        #expect(lines[1].hasPrefix("Bandcamp: "))
        #expect(lines.count == 3)
    }

    @Test func allAlbumsAreBulletsUnderAHeading() {
        let text = AIRecommendationShareText.all([inRainbows, undated], heading: "Album suggestions from Claude")
        let blocks = text.components(separatedBy: "\n\n")
        #expect(blocks.count == 3)
        #expect(blocks[0] == "Album suggestions from Claude")
        let first = blocks[1].components(separatedBy: "\n")
        #expect(first[0] == "• In Rainbows — Radiohead (2007)")
        #expect(first[1] == "  Because you play OK Computer.")
        #expect(first.dropFirst().allSatisfy { $0.hasPrefix("  ") })
        #expect(blocks[2].hasPrefix("• Things We Lost in the Fire — Low\n  Bandcamp: "))
    }

    @Test func linksStayOnOneLineSoNotesDetectsThem() {
        let text = AIRecommendationShareText.single(AIRecommendation(artist: "Sigur Rós", album: "( )", year: 2002, reason: "r"))
        for line in text.components(separatedBy: "\n") where line.contains("https://") {
            #expect(!line.contains(" ", after: "https://"))
        }
    }
}

private extension String {
    /// Whether `character` appears after the first occurrence of `marker`.
    func contains(_ character: Character, after marker: String) -> Bool {
        guard let range = range(of: marker) else { return false }
        return self[range.upperBound...].contains(character)
    }
}
