import Foundation
import SwiftSonic

/// Genre names arrive exactly as files are tagged, so one genre often has several spellings:
/// "Trip-Hop" and "Trip Hop", "J-Pop" and "JPop", "Drum & Bass" and "drum and bass". These helpers
/// treat spellings that differ only in capitals, spaces, punctuation or the word "and" as one
/// genre. Different words stay different: "Game" and "Games" are two genres.
nonisolated enum GenreName {
    /// One genre and every spelling of it the server reported.
    struct Merged: Sendable, Hashable, Identifiable {
        /// The spelling with the most songs, shown for the whole group.
        let name: String
        /// Every spelling, most songs first, to ask the server for each in turn.
        let variants: [String]
        let songCount: Int
        let albumCount: Int

        var id: String { GenreName.key(name) }
    }

    /// The spelling-insensitive identity of a genre: its letters and digits, lowercased, without
    /// the word "and".
    static func key(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0 != "and" }
            .joined()
    }

    /// Groups the server's genres by `key`, keeping the order of the first spelling of each.
    /// A name with no letters or digits at all stays on its own.
    static func merge(_ genres: [Genre]) -> [Merged] {
        var order: [String] = []
        var groups: [String: [Genre]] = [:]
        for genre in genres {
            let key = key(genre.value)
            let groupKey = key.isEmpty ? "\u{0}" + genre.value : key
            if groups[groupKey] == nil { order.append(groupKey) }
            groups[groupKey, default: []].append(genre)
        }
        return order.compactMap { groupKey in
            guard let members = groups[groupKey] else { return nil }
            let ranked = members.sorted { lhs, rhs in
                lhs.songCount != rhs.songCount ? lhs.songCount > rhs.songCount : lhs.value < rhs.value
            }
            return Merged(name: ranked[0].value, variants: ranked.map(\.value),
                          songCount: members.reduce(0) { $0 + $1.songCount },
                          albumCount: members.reduce(0) { $0 + $1.albumCount })
        }
    }
}
