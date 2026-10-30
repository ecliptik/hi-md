import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Genre spellings")
struct GenreNameTests {
    private func genres(_ list: [(String, Int)]) throws -> [Genre] {
        let items = list.map { #"{"value":"\#($0.0)","songCount":\#($0.1),"albumCount":\#(max(1, $0.1 / 10))}"# }
        return try JSONDecoder().decode([Genre].self, from: Data("[\(items.joined(separator: ","))]".utf8))
    }

    @Test func spellingsOfOneGenreShareAKey() {
        #expect(GenreName.key("Trip-Hop") == GenreName.key("Trip Hop"))
        #expect(GenreName.key("J-Pop") == GenreName.key("JPop"))
        #expect(GenreName.key("Drum & Bass") == GenreName.key("drum and bass"))
        #expect(GenreName.key("Game") != GenreName.key("Games"))
    }

    @Test func mergingKeepsTheBusiestSpellingAndAddsUpCounts() throws {
        let merged = GenreName.merge(try genres([("J-Pop", 31), ("Trip Hop", 60), ("JPop", 754), ("Trip-Hop", 19), ("Game", 46), ("Games", 12)]))
        #expect(merged.map(\.name) == ["JPop", "Trip Hop", "Game", "Games"])
        #expect(merged[0].variants == ["JPop", "J-Pop"])
        #expect(merged[0].songCount == 785)
        #expect(merged[1].variants == ["Trip Hop", "Trip-Hop"])
        #expect(merged[1].songCount == 79)
    }

    @Test func lowercaseNamesGetCapitalsAndOthersKeepTheirs() {
        #expect(GenreName.displayName("dark jazz") == "Dark Jazz")
        #expect(GenreName.displayName("electro-industrial") == "Electro-Industrial")
        #expect(GenreName.displayName("edm") == "EDM")
        #expect(GenreName.displayName("r&b") == "R&B")
        #expect(GenreName.displayName("j-pop") == "J-Pop")
        #expect(GenreName.displayName("rock and roll") == "Rock and Roll")
        #expect(GenreName.displayName("hip hop/rap") == "Hip Hop/Rap")
        #expect(GenreName.displayName("JPop") == "JPop")
        #expect(GenreName.displayName("Trip Hop") == "Trip Hop")
        #expect(GenreName.displayName("90s") == "90s")
    }

    @Test func aMergedGenreShowsItsBusiestSpellingWithCapitals() throws {
        let merged = GenreName.merge(try genres([("downtempo", 20), ("Downtempo", 3)]))
        #expect(merged.map(\.name) == ["Downtempo"])
        #expect(merged[0].variants == ["downtempo", "Downtempo"], "lookups keep the tagged spellings")
    }

    @Test func namesWithoutLettersStayApart() throws {
        let merged = GenreName.merge(try genres([("—", 2), ("?", 3)]))
        #expect(merged.count == 2)
    }
}
