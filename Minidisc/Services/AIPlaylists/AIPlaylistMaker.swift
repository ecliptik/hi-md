import Foundation
import OSLog
import SwiftSonic

/// A playlist the model has made, before it's saved.
nonisolated struct AIPlaylistDraft: Sendable {
    var title: String
    var summary: String
    /// What the listener asked for, kept as the playlist's description.
    var request: String
    var songs: [Song]
}

/// Makes a playlist from a request in three steps. The model plans which of the library's genres,
/// artists, years and mood fit; matching songs are gathered locally and spread across artists and
/// albums; the model then chooses and orders some of them by number. It never names a song
/// itself, so every song is one the library has.
nonisolated struct AIPlaylistMaker: Sendable {
    static let songCount = 30
    /// Songs one artist may have in a made playlist.
    static let perArtistLimit = 3
    /// Fewer than this isn't worth saving as a playlist.
    static let minimumSongs = 8
    /// How many of the library's genres and artists the planner is shown, most songs first.
    static let summaryGenres = 200
    static let summaryArtists = 400

    let model: any AIPlaylistModel
    /// Every song in the library, from the local index.
    let library: @Sendable () async throws -> [Song]

    func make(_ request: String, count: Int = songCount, seed: UInt64 = .random(in: 0...UInt64.max)) async throws -> AIPlaylistDraft {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { throw AIPlaylistError.emptyRequest }
        let songs = try await library()
        guard !songs.isEmpty else { throw AIPlaylistError.noLibrary }
        try Task.checkCancellation()

        let summary = Self.summary(of: songs, withArtists: model.plansWithArtists)
        let plan = Self.resolve(try await model.plan(request, library: summary), in: summary)
        try Task.checkCancellation()
        let pool = Self.pool(for: plan, from: songs, limit: model.candidateLimit, seed: seed)
        Logger.ui.info("AI playlist: plan \(plan.genres.count) genres, \(plan.artists.count) artists, mood \(plan.mood?.rawValue ?? "none", privacy: .public) → \(pool.count) candidates")
        guard pool.count >= Self.minimumSongs else { throw AIPlaylistError.notEnoughMatches }

        let choice = try await model.choose(request, candidates: Self.lines(pool), count: min(count, pool.count))
        try Task.checkCancellation()
        let chosen = Self.picks(choice.picks, from: pool, limit: count, perArtist: Self.perArtistLimit)
        guard chosen.count >= Self.minimumSongs else { throw AIPlaylistError.notEnoughMatches }
        let title = Self.cleanTitle(choice.title)
        return AIPlaylistDraft(title: title.isEmpty ? request : title, summary: choice.summary, request: request, songs: chosen)
    }

    // MARK: - Library summary and plan

    static func summary(of songs: [Song], withArtists: Bool) -> AIPlaylistLibrarySummary {
        var genreCounts: [String: Int] = [:]
        var artistCounts: [String: (name: String, count: Int)] = [:]
        for song in songs {
            for genre in genres(of: song) { genreCounts[genre, default: 0] += 1 }
            if withArtists, let artist = song.artist, !artist.isEmpty {
                let key = artistKey(artist)
                artistCounts[key, default: (artist, 0)].count += 1
            }
        }
        // One name per genre whatever its spellings, so the planner doesn't pick between them.
        var merged: [String: (name: String, count: Int, best: Int)] = [:]
        for (name, count) in genreCounts {
            let key = GenreName.key(name)
            guard !key.isEmpty else { continue }
            var entry = merged[key] ?? (name, 0, 0)
            entry.count += count
            if count > entry.best || (count == entry.best && name < entry.name) { entry.name = name; entry.best = count }
            merged[key] = entry
        }
        let genres = merged.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(summaryGenres).map(\.name)
        let artists = artistCounts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(summaryArtists).map(\.name)
        return AIPlaylistLibrarySummary(genres: genres, artists: artists)
    }

    /// Keeps only genres and artists the library has, under its own spelling. A model may answer
    /// with a near miss ("Trip-Hop" for "Trip Hop") or one it made up.
    static func resolve(_ plan: AIPlaylistPlan, in library: AIPlaylistLibrarySummary) -> AIPlaylistPlan {
        let genres = Dictionary(library.genres.map { (GenreName.key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let artists = Dictionary(library.artists.map { (artistKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        var resolved = plan
        resolved.genres = unique(plan.genres.compactMap { genres[GenreName.key($0)] })
        resolved.artists = unique(plan.artists.compactMap { artists[artistKey($0)] })
        return resolved
    }

    // MARK: - Candidates

    /// Songs that fit the plan, spread across artists and albums: songs by its artists first, then
    /// its genres, then songs whose tags fit its mood. With nothing to go on, the whole library.
    static func pool(for plan: AIPlaylistPlan, from songs: [Song], limit: Int, seed: UInt64) -> [Song] {
        let genreKeys = Set(plan.genres.map(GenreName.key))
        let artistKeys = Set(plan.artists.map(artistKey))
        var byArtist: [Song] = [], byGenre: [Song] = [], byMood: [Song] = [], inYears: [Song] = []
        for song in songs {
            if let years = plan.years {
                guard let year = song.year, years.contains(year) else { continue }
            }
            inYears.append(song)
            if !artistKeys.isEmpty, artistNames(of: song).contains(where: { artistKeys.contains(artistKey($0)) }) {
                byArtist.append(song)
            } else if !genreKeys.isEmpty, genres(of: song).contains(where: { genreKeys.contains(GenreName.key($0)) }) {
                byGenre.append(song)
            } else if let mood = plan.mood, (MoodTagMatcher.score(LibraryTagTrackProvider.features(of: song), for: mood) ?? 0) > 0 {
                byMood.append(song)
            }
        }
        var tiers = [byArtist, byGenre, byMood].filter { !$0.isEmpty }
        // A period alone, or nothing the plan could use: let the model choose from what's left.
        if tiers.isEmpty { tiers = [inYears] }
        var random = SeededRandom(seed: seed)
        var perArtist: [String: Int] = [:]
        var perAlbum: [String: Int] = [:]
        var pool: [Song] = []
        for tier in tiers {
            for song in spread(tier, random: &random) where pool.count < limit {
                let artist = artistKey(song.artist ?? "")
                let album = song.albumId ?? song.album ?? song.id
                guard perArtist[artist, default: 0] < 8, perAlbum[album, default: 0] < 4 else { continue }
                perArtist[artist, default: 0] += 1
                perAlbum[album, default: 0] += 1
                pool.append(song)
            }
        }
        return pool
    }

    /// Favourites and much-played songs first, then the rest in a fresh order each time, so
    /// asking again gives a different playlist.
    private static func spread(_ songs: [Song], random: inout SeededRandom) -> [Song] {
        let favourites = songs.filter { $0.starred != nil || ($0.playCount ?? 0) >= 5 }
        let others = songs.filter { $0.starred == nil && ($0.playCount ?? 0) < 5 }
        return favourites.shuffled(using: &random) + others.shuffled(using: &random)
    }

    /// One line per candidate, numbered from 1: title, artist, year and genre.
    static func lines(_ songs: [Song]) -> [String] {
        songs.enumerated().map { index, song in
            var details: [String] = []
            if let year = song.year, year > 0 { details.append(String(year)) }
            if let genre = genres(of: song).first { details.append(genre) }
            let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
            return "\(index + 1). \(song.title) — \(song.artist ?? "Unknown Artist")\(suffix)"
        }
    }

    /// The chosen candidates in the model's order, skipping numbers off the list, repeats and an
    /// artist's songs beyond `perArtist`.
    static func picks(_ numbers: [Int], from pool: [Song], limit: Int, perArtist: Int) -> [Song] {
        var seen = Set<Int>()
        var artists: [String: Int] = [:]
        var chosen: [Song] = []
        for number in numbers where chosen.count < limit {
            let index = number - 1
            guard pool.indices.contains(index), seen.insert(index).inserted else { continue }
            let song = pool[index]
            let artist = artistKey(song.artist ?? "")
            if !artist.isEmpty {
                guard artists[artist, default: 0] < perArtist else { continue }
                artists[artist, default: 0] += 1
            }
            chosen.append(song)
        }
        return chosen
    }

    // MARK: - Helpers

    static func genres(of song: Song) -> [String] {
        var genres = song.genres?.map(\.name) ?? []
        if let legacy = song.genre, !legacy.isEmpty, !genres.contains(legacy) { genres.append(legacy) }
        return genres
    }

    static func artistNames(of song: Song) -> [String] {
        ([song.artist, song.displayArtist, song.displayAlbumArtist].compactMap { $0 }
            + (song.artists ?? []).map(\.name) + (song.albumArtists ?? []).map(\.name))
            .filter { !$0.isEmpty }
    }

    static func artistKey(_ name: String) -> String {
        AIRecommendationMatcher.key(name)
    }

    static func cleanTitle(_ title: String) -> String {
        title.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'‘’ ").union(.whitespacesAndNewlines))
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}

/// A small seeded generator (SplitMix64), so tests can repeat a shuffle.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
