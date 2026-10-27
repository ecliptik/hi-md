import Foundation
import Testing
@testable import Minidisc

@Suite("AI recommendations")
struct AIRecommendationTests {
    private let sample = AIRecommendation(artist: "Radiohead", album: "In Rainbows", year: 2007, reason: "Because you play OK Computer.")

    @Test func parsesEnvelopesArraysAndChattyAnswers() throws {
        let envelope = #"{"recommendations": [{"artist": "Radiohead", "album": "In Rainbows", "year": 2007, "reason": "r"}]}"#
        #expect(try AIRecommendationParser.parse(envelope).map(\.album) == ["In Rainbows"])
        let fenced = "Sure! Here you go:\n```json\n" + envelope + "\n```\nEnjoy."
        #expect(try AIRecommendationParser.parse(fenced).count == 1)
        let bare = #"[{"artist": "Low", "album": "Things We Lost in the Fire", "reason": "r"}, {"artist": "low", "album": "things we lost in the fire", "reason": "dup"}]"#
        #expect(try AIRecommendationParser.parse(bare).map(\.artist) == ["Low"])
        #expect(throws: AIRecommendationError.badResponse) { try AIRecommendationParser.parse("I can't help with that.") }
    }

    @Test func matchingIgnoresCaseTheEditionsAndPunctuation() {
        #expect(AIRecommendationMatcher.key("The National") == AIRecommendationMatcher.key("national"))
        #expect(AIRecommendationMatcher.key("OK Computer (Deluxe Edition)") == AIRecommendationMatcher.key("OK Computer"))
        #expect(AIRecommendationMatcher.key("Sigur Rós") == AIRecommendationMatcher.key("Sigur Ros"))
        #expect(AIRecommendationMatcher.key("AC/DC") == AIRecommendationMatcher.key("ACDC"))
    }

    @Test func searchLinksCarryArtistAndAlbum() throws {
        let bandcamp = try #require(AIRecommendationLinks.bandcamp(sample))
        #expect(bandcamp.host == "bandcamp.com")
        #expect(bandcamp.query?.contains("Radiohead") == true)
        let musicBrainz = try #require(AIRecommendationLinks.musicBrainz(sample))
        #expect(musicBrainz.absoluteString.contains("type=release"))
    }

    @Test func musicBrainzLinkOpensTheReleaseGroupOnceVerified() throws {
        var verified = sample
        verified.releaseGroupID = "b7ffd2af-418f-4be2-bdd1-22f8b48613da"
        let url = try #require(AIRecommendationLinks.musicBrainz(verified))
        #expect(url.absoluteString == "https://musicbrainz.org/release-group/b7ffd2af-418f-4be2-bdd1-22f8b48613da")
    }

    @Test func picksParseFromChattyAnswers() throws {
        let picks = try AIRecommendationParser.parsePicks(#"Here: {"picks": [{"id": "c3", "reason": "r"}, {"id": "c1"}]}"#)
        #expect(picks == [AIRecommendationPick(id: "c3", reason: "r"), AIRecommendationPick(id: "c1", reason: "")])
        #expect(throws: AIRecommendationError.badResponse) { try AIRecommendationParser.parsePicks("No.") }
    }

    @Test("A reply whose closing bracket comes before its opening one is a bad response, not a trap")
    func invertedBracketsAreBadResponses() {
        for reply in ["Sorry} please try again {", "1] see [", "} only {", "]["] {
            #expect(throws: AIRecommendationError.badResponse) { try AIRecommendationParser.parse(reply) }
            #expect(throws: AIRecommendationError.badResponse) { try AIRecommendationParser.parsePicks(reply) }
        }
        #expect(AIRecommendationParser.span(of: "x } y {", from: "{", to: "}") == nil)
        #expect(AIRecommendationParser.span(of: #"a {"k": 1} b"#, from: "{", to: "}") == #"{"k": 1}"#)
    }

    @Test func ampersandMatchesAnd() {
        #expect(AIRecommendationMatcher.key("Slanted & Enchanted") == AIRecommendationMatcher.key("Slanted and Enchanted"))
    }

    @Test func profilePromptListsOnlyWhatIsKnown() {
        var profile = AIListeningProfile()
        #expect(profile.isEmpty)
        profile.topArtists = ["Björk"]
        let prompt = profile.prompt(count: 5)
        #expect(prompt.contains("Most collected artists:\n- Björk"))
        #expect(!prompt.contains("Recently played"))
        #expect(prompt.contains("Recommend 5 albums"))
    }
}
