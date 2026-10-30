import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

/// Answers with a fixed plan and picks, and records what it was shown.
private final class ScriptedPlaylistModel: AIPlaylistModel, @unchecked Sendable {
    var plansWithArtists = true
    var candidateLimit = 50
    var plan = AIPlaylistPlan()
    var choice: (([String]) -> AIPlaylistChoice) = { lines in
        AIPlaylistChoice(title: "Picks", summary: "", picks: Array(1...lines.count))
    }
    var failure: (any Error)?
    private(set) var plannedLibrary: AIPlaylistLibrarySummary?
    private(set) var shownCandidates: [String] = []

    func plan(_ request: String, library: AIPlaylistLibrarySummary) async throws -> AIPlaylistPlan {
        plannedLibrary = library
        return plan
    }

    func choose(_ request: String, candidates: [String], count: Int) async throws -> AIPlaylistChoice {
        if let failure { throw failure }
        shownCandidates = candidates
        return choice(candidates)
    }

    func ideas(_ profile: AIListeningProfile, genres: [String], count: Int) async throws -> [AIPlaylistIdea] { [] }
}

/// Grouped by artist: Portishead 0–5, Massive Attack 6–11, Tricky 12–14, Perfume 15–20, Rancid 21–26.
private func library() throws -> [Song] {
    let artists: [(id: String, artist: String, genre: String, count: Int)] = [
        ("pa", "Portishead", "Trip-Hop", 6), ("ma", "Massive Attack", "Trip Hop", 6), ("tr", "Tricky", "trip-hop", 3),
        ("jp", "Perfume", "JPop", 6), ("pu", "Rancid", "punk", 6),
    ]
    return try artists.flatMap { entry in
        try (1...entry.count).map { try song(id: "\(entry.id)\($0)", title: "\(entry.artist) \($0)", artist: entry.artist, genre: entry.genre) }
    }
}

@Suite("AI playlists")
struct AIPlaylistMakerTests {
    @Test func thePlannerSeesEachGenreOnceAndTheLibrarysArtists() async throws {
        let model = ScriptedPlaylistModel()
        model.plan.genres = ["Trip-Hop"]
        let songs = try library()
        let maker = AIPlaylistMaker(model: model, library: { songs })
        _ = try await maker.make("rainy day trip-hop", seed: 1)
        let summary = try #require(model.plannedLibrary)
        #expect(summary.genres.filter { GenreName.key($0) == "triphop" }.count == 1)
        #expect(Set(summary.artists) == ["Portishead", "Massive Attack", "Tricky", "Perfume", "Rancid"])
    }

    @Test func candidatesComeFromBothSpellingsOfAPlannedGenreOnly() async throws {
        let model = ScriptedPlaylistModel()
        model.plan.genres = ["trip hop"]
        let songs = try library()
        let maker = AIPlaylistMaker(model: model, library: { songs })
        let draft = try await maker.make("trip-hop", seed: 7)
        #expect(model.shownCandidates.count == 15)
        #expect(draft.songs.count == 9, "three songs from each of the three trip-hop artists")
        #expect(draft.songs.allSatisfy { ["Portishead", "Massive Attack", "Tricky"].contains($0.artist ?? "") })
    }

    @Test func plannedArtistsComeFirstAndUnknownNamesAreDropped() async throws {
        let model = ScriptedPlaylistModel()
        model.plan.artists = ["massive attack", "Burial"]
        model.plan.genres = ["punk", "Synthwave", "trip-hop"]
        let songs = try library()
        let maker = AIPlaylistMaker(model: model, library: { songs })
        let draft = try await maker.make("night bus", seed: 3)
        #expect(model.shownCandidates.count == 21)
        #expect(model.shownCandidates.prefix(6).allSatisfy { $0.contains("Massive Attack") })
        #expect(draft.songs.prefix(3).allSatisfy { $0.artist == "Massive Attack" })
        #expect(!draft.songs.contains { $0.artist == "Perfume" })
    }

    @Test func picksKeepTheModelsOrderAndSkipBadNumbersRepeatsAndArtistOverflow() throws {
        let pool = try library().filter { $0.artist == "Portishead" || $0.artist == "Perfume" }
        let picked = AIPlaylistMaker.picks([2, 99, 2, 1, 3, 4, 7, 0, 8], from: pool, limit: 10, perArtist: 3)
        #expect(picked.map(\.id) == [pool[1].id, pool[0].id, pool[2].id, pool[6].id, pool[7].id])
    }

    @Test func tooFewMatchesIsAnErrorNotAPadOfRandomSongs() async throws {
        let model = ScriptedPlaylistModel()
        model.plan.artists = ["Rancid"]
        model.plan.years = 1990...1999
        let songs = try library()
        let maker = AIPlaylistMaker(model: model, library: { songs })
        await #expect(throws: AIPlaylistError.notEnoughMatches) { try await maker.make("90s ska punk") }
    }

    @Test func cloudRepliesAreReadThroughProseAndFences() throws {
        let plan = try AIPlaylistParser.plan("Sure!\n```json\n{\"genres\":[\"Trip Hop\"],\"artists\":[],\"fromYear\":1990,\"toYear\":0,\"mood\":\"Chill\"}\n```")
        #expect(plan.genres == ["Trip Hop"])
        #expect(plan.years == 1990...1990)
        #expect(plan.mood == .chill)
        let choice = try AIPlaylistParser.choice(#"{"title":"Rain","summary":"Soft.","picks":[3,1]}"#)
        #expect(choice.picks == [3, 1])
        #expect(AIPlaylistMaker.cleanTitle("“Rainy Day”") == "Rainy Day")
    }
}

@Suite("AI mood playlists")
struct AIMoodTrackProviderTests {
    private struct FixedProvider: MoodTrackProvider {
        let ids: [String]
        var kind: MoodSourceKind { .tags }
        func prepare() async {}
        func trackIds(for mood: Mood, limit: Int) async throws -> [String] { Array(ids.prefix(limit)) }
    }

    @Test func theModelChoosesFromTheWiderPool() async throws {
        let songs = try library()
        let model = ScriptedPlaylistModel()
        model.choice = { _ in AIPlaylistChoice(title: "", summary: "", picks: Array((13...24).reversed())) }
        let provider = AIMoodTrackProvider(base: FixedProvider(ids: songs.map(\.id)), model: model,
                                           songs: { ids in songs.filter { ids.contains($0.id) } })
        let ids = try await provider.trackIds(for: .chill, limit: 8)
        #expect(ids.count == 8)
        #expect(ids.first == songs[23].id)
        #expect(model.shownCandidates.count == 24)
    }

    @Test func aFailingModelKeepsThePoolsRanking() async throws {
        let songs = try library()
        let model = ScriptedPlaylistModel()
        model.failure = AIRecommendationError.badResponse
        let provider = AIMoodTrackProvider(base: FixedProvider(ids: songs.map(\.id)), model: model,
                                           songs: { ids in songs.filter { ids.contains($0.id) } })
        #expect(try await provider.trackIds(for: .chill, limit: 5) == Array(songs.prefix(5).map(\.id)))
    }
}
