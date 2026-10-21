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

    @Test func providerRequestsCarryKeyModelAndProfile() throws {
        var profile = AIListeningProfile()
        profile.recentAlbums = ["Radiohead – OK Computer"]
        let anthropic = try AIRecommender.anthropicRequest(profile, key: "sk-ant", model: "claude-sonnet-5-5")
        #expect(anthropic.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(anthropic.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try #require(anthropic.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("claude-sonnet-5-5") && body.contains("OK Computer"))
        let openAI = try AIRecommender.openAIRequest(profile, key: "sk-oa", model: "gpt-5")
        #expect(openAI.value(forHTTPHeaderField: "Authorization") == "Bearer sk-oa")
        #expect(String(data: openAI.httpBody ?? Data(), encoding: .utf8)?.contains("json_object") == true)
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
