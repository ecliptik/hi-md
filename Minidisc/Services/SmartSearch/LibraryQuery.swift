import Foundation
import SwiftSonic

/// Structured filters for a natural-language library search such as
/// "mellow 90s rock I haven't played lately". The on-device model fills these in;
/// `LibraryQueryFilter` applies them to the local library index.
nonisolated struct LibraryQuery: Sendable, Equatable {
    enum Recency: Sendable, Equatable {
        case any, notPlayedLately, playedRecently
    }

    var genres: [String] = []
    var artists: [String] = []
    var years: ClosedRange<Int>?
    var mood: Mood?
    var recency: Recency = .any
    var favoritesOnly = false
    var titleWords: [String] = []

    /// True when the model found nothing to filter on, so every song would match.
    var isEmpty: Bool {
        genres.isEmpty && artists.isEmpty && years == nil && mood == nil
            && recency == .any && !favoritesOnly && titleWords.isEmpty
    }

    /// The filters as short labels, shown above the results so the interpretation is visible.
    var summary: [String] {
        var parts = genres.map(\.localizedCapitalized) + artists
        if let years {
            parts.append(years.lowerBound == years.upperBound ? "\(years.lowerBound)" : "\(years.lowerBound)–\(years.upperBound)")
        }
        if let mood { parts.append(String(localized: mood.title)) }
        switch recency {
        case .any: break
        case .notPlayedLately: parts.append(String(localized: "Not played lately"))
        case .playedRecently: parts.append(String(localized: "Played recently"))
        }
        if favoritesOnly { parts.append(String(localized: "Favorites")) }
        parts += titleWords.map { "“\($0)”" }
        return parts
    }
}

nonisolated enum LibraryQueryFilter {
    static let resultLimit = 100
    /// Keeps one album from filling the whole list.
    static let perAlbumLimit = 5
    static let lateThreshold: TimeInterval = 90 * 24 * 60 * 60
    static let recentThreshold: TimeInterval = 30 * 24 * 60 * 60

    static func matches(_ song: Song, _ query: LibraryQuery, now: Date) -> Bool {
        if query.favoritesOnly, song.starred == nil { return false }
        if let years = query.years {
            guard let year = song.year, years.contains(year) else { return false }
        }
        switch query.recency {
        case .any: break
        case .notPlayedLately:
            if let played = song.played, now.timeIntervalSince(played) < lateThreshold { return false }
        case .playedRecently:
            guard let played = song.played, now.timeIntervalSince(played) < recentThreshold else { return false }
        }
        if !query.artists.isEmpty {
            let names = [song.artist, song.displayArtist, song.displayAlbumArtist].compactMap { $0 }
                + (song.artists ?? []).map(\.name) + (song.albumArtists ?? []).map(\.name)
            guard contains(names, anyOf: query.artists) else { return false }
        }
        let songGenres = [song.genre].compactMap { $0 } + (song.genres ?? []).map(\.name)
        if !query.genres.isEmpty, !contains(songGenres, anyOf: query.genres) { return false }
        if let mood = query.mood {
            if let range = MoodTagMatcher.bpmRange(mood), let bpm = song.bpm, bpm > 0, !range.contains(bpm) { return false }
            // Without explicit genres, the mood's genres stand in for them; songs with a BPM
            // inside the mood's range qualify as well.
            if query.genres.isEmpty {
                let byGenre = contains(songGenres, anyOf: MoodTagMatcher.genres(mood))
                let byTempo = MoodTagMatcher.bpmRange(mood).map { range in song.bpm.map { range.contains($0) } ?? false } ?? false
                guard byGenre || byTempo else { return false }
            }
        }
        if !query.titleWords.isEmpty, !contains([song.title, song.album].compactMap { $0 }, anyOf: query.titleWords) {
            return false
        }
        return true
    }

    /// Favourites and often-played songs first, a few per album, capped for a playable list.
    static func rank(_ songs: [Song]) -> [Song] {
        let ordered = songs.sorted { lhs, rhs in
            if (lhs.starred != nil) != (rhs.starred != nil) { return lhs.starred != nil }
            if (lhs.playCount ?? 0) != (rhs.playCount ?? 0) { return (lhs.playCount ?? 0) > (rhs.playCount ?? 0) }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        var perAlbum: [String: Int] = [:]
        var result: [Song] = []
        for song in ordered {
            let album = song.albumId ?? song.album ?? song.id
            guard perAlbum[album, default: 0] < perAlbumLimit else { continue }
            perAlbum[album, default: 0] += 1
            result.append(song)
            if result.count == resultLimit { break }
        }
        return result
    }

    private static func contains(_ values: [String], anyOf terms: [String]) -> Bool {
        let haystack = values.map(MoodTagMatcher.normalise)
        let needles = terms.map(MoodTagMatcher.normalise).filter { !$0.isEmpty }
        return haystack.contains { value in needles.contains { value.contains($0) } }
    }
}
