import Foundation
import SwiftSonic

extension StructuredLyrics {
    /// Whether the lines carry real timings the lyrics can follow, rather than the server's
    /// `synced` flag alone. Plain lyrics (LRCLIB's `plainLyrics`, Navidrome's unsynced lyrics)
    /// arrive with no start times, or with every line at zero; a single timestamped line
    /// can't be followed either. Timed means some line starts strictly later than an earlier
    /// one, so at least two lines have distinct, increasing start times.
    nonisolated var isTimed: Bool {
        LyricsTiming.isTimed(starts: line.map(\.start))
    }
}

nonisolated enum LyricsTiming {
    /// True when, among the start times present, a later line starts after an earlier one.
    static func isTimed(starts: [Int?]) -> Bool {
        var earliest: Int?
        for case let start? in starts {
            if let earliest, start > earliest { return true }
            earliest = min(earliest ?? start, start)
        }
        return false
    }

    /// Plain lyrics as stanzas: lines between blank ones joined with line breaks, a line
    /// holding several lines split, runs of blank lines collapsed, and the edges trimmed.
    static func stanzas(from values: [String]) -> [String] {
        var stanzas: [String] = []
        var current: [String] = []
        // CRLF first, or each Windows line ending would read as a blank line between stanzas.
        let lines = values.flatMap { $0.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { stanzas.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { stanzas.append(current.joined(separator: "\n")) }
        return stanzas
    }

    /// LRCLIB's plain lyrics as lines, a blank line kept between stanzas.
    static func plainLines(from text: String) -> [String] {
        stanzas(from: [text]).enumerated().flatMap { index, stanza in
            (index > 0 ? [""] : []) + stanza.components(separatedBy: "\n")
        }
    }
}
