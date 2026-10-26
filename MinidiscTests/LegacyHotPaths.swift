import CoreGraphics
import Foundation
import SwiftSonic
@testable import Minidisc

/// Verbatim copies of the hot paths as they stood before the 2026-10-25 performance work. The
/// equivalence tests compare the optimised code against them, and the opt-in benchmarks time them
/// as the baseline. Don't "fix" these: their value is that they are the old behaviour.
@MainActor
enum LegacyHotPaths {
    // MARK: - Search ranking (LibrarySearchMatch.swift, SearchView.swift)

    static func onlineMatches(query: String, results: SearchResult3?, playlists: [Playlist]) -> [LibrarySearchMatch] {
        guard !normalized(query).isEmpty else { return [] }
        var values: [LibrarySearchMatch] = (results?.artist ?? [])
            .filter { ($0.albumCount ?? 0) > 0 }.map(LibrarySearchMatch.artist)
        values += (results?.album ?? []).map(LibrarySearchMatch.album)
        values += (results?.song ?? []).map { .song(DisplayableSong(from: $0)) }
        values += playlists.map(LibrarySearchMatch.playlist).filter { score($0, query: query) > 0 }
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }.sorted { lhs, rhs in
            let a = score(lhs, query: query), b = score(rhs, query: query)
            if a != b { return a > b }
            let order = lhs.title.localizedStandardCompare(rhs.title)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    static func offlineMatches(_ local: OfflineBrowsingSnapshot, searchQuery: String) -> [LibrarySearchMatch] {
        let matches = local.songs.map(LibrarySearchMatch.song) + local.albums.map(LibrarySearchMatch.album)
            + local.artists.map(LibrarySearchMatch.artist) + local.playlists.map(LibrarySearchMatch.playlist)
        return matches.filter { score($0, query: searchQuery) > 0 }.sorted {
            let lhs = score($0, query: searchQuery)
            let rhs = score($1, query: searchQuery)
            return lhs == rhs ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : lhs > rhs
        }
    }

    static func score(_ match: LibrarySearchMatch, query: String) -> Int {
        let query = normalized(query)
        guard !query.isEmpty else { return 0 }
        let title = normalized(match.title)
        if title == query { return 1_000 }
        if title.hasPrefix(query) { return 800 }
        let tokens = query.split(separator: " ")
        if title.contains(query) { return 600 }
        if tokens.allSatisfy({ token in title.split(separator: " ").contains { $0.hasPrefix(token) } }) { return 500 }
        let combined = title + " " + normalized(match.detail)
        return tokens.allSatisfy { combined.contains($0) } ? 200 : 0
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Queue rows (InlineQueueList.swift)

    struct QueueRowSnapshot: Identifiable {
        struct ID: Hashable {
            let generation: UInt64
            let songID: String
            let occurrence: Int
        }
        let id: ID
        let song: DisplayableSong
        let selection: QueueTrackSelection
    }

    static func captureQueue(_ state: PlayerState) -> [QueueRowSnapshot] {
        var occurrences: [String: Int] = [:]
        return state.queue.enumerated().compactMap { index, song in
            let occurrence = occurrences[song.id, default: 0]
            occurrences[song.id] = occurrence + 1
            guard index > state.currentIndex,
                  let selection = QueueTrackSelection(playerState: state, destinationIndex: index,
                                                      destinationTrackID: song.id) else { return nil }
            return QueueRowSnapshot(id: .init(generation: state.queueGeneration, songID: song.id, occurrence: occurrence),
                                    song: song, selection: selection)
        }
    }

    // MARK: - Song selection (SongSelectionSheet.swift)

    static func selectionSongs(_ request: SongSelectionRequest) -> [DisplayableSong] {
        var seen: Set<String> = []
        return request.songs.filter { seen.insert($0.id).inserted }
    }

    static func visibleSelectionSongs(_ request: SongSelectionRequest, query: String) -> [DisplayableSong] {
        let query = normalized(query)
        return selectionSongs(request).filter {
            query.isEmpty || normalized("\($0.title) \($0.artist ?? "")").contains(query)
        }
    }

    // MARK: - Placeholder detection (ServerPlaceholderArtwork.swift)

    static func isServerPlaceholder(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0, abs(width - height) <= max(width, height) / 20,
              let pixels = samples(of: image) else { return false }
        return isAlbumPlaceholder(pixels) || isArtistPlaceholder(pixels)
    }

    private static let side = 32

    private static func isAlbumPlaceholder(_ pixels: [Pixel]) -> Bool {
        let ring = pixels.filter { (0.19..<0.35).contains($0.radius) }
        let label = pixels.filter { $0.radius < 0.12 }
        let corners = pixels.filter { $0.radius >= 0.55 }
        let blueRing = Double(ring.count { $0.isRecordBlue }) / Double(ring.count)
        let labelLuma = label.map(\.luma).reduce(0, +) / Double(label.count)
        let labelHasBlue = label.contains { $0.isRecordBlue }
        return blueRing >= 0.9 && labelLuma < 90 && !labelHasBlue && isUniform(corners)
    }

    private static func isArtistPlaceholder(_ pixels: [Pixel]) -> Bool {
        guard pixels.allSatisfy(\.isNeutral) else { return false }
        let centre = pixels.filter { $0.radius < 0.08 }
        let edge = pixels.filter { $0.radius >= 0.45 }
        let centreLuma = centre.map(\.luma).reduce(0, +) / Double(centre.count)
        let edgeLuma = edge.map(\.luma).reduce(0, +) / Double(edge.count)
        return centreLuma > 245 && (222...245).contains(edgeLuma) && isUniform(edge)
    }

    private static func isUniform(_ pixels: [Pixel]) -> Bool {
        let lumas = pixels.map(\.luma)
        let mean = lumas.reduce(0, +) / Double(lumas.count)
        let variance = lumas.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lumas.count)
        return variance.squareRoot() < 12
    }

    private struct Pixel {
        let red: Double, green: Double, blue: Double
        let radius: Double

        var luma: Double { 0.299 * red + 0.587 * green + 0.114 * blue }

        var isNeutral: Bool { max(red, green, blue) - min(red, green, blue) < 8 }

        var isRecordBlue: Bool {
            let maxValue = max(red, green, blue), minValue = min(red, green, blue)
            guard maxValue > 115, maxValue == blue, maxValue - minValue > maxValue * 0.5 else { return false }
            let hue = 240 + 60 * (red - green) / (maxValue - minValue)
            return (195...245).contains(hue)
        }
    }

    private static func samples(of image: CGImage) -> [Pixel]? {
        let bytesPerRow = side * 4
        var buffer = [UInt8](repeating: 0, count: side * bytesPerRow)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        let centre = Double(side - 1) / 2
        return (0..<(side * side)).map { index in
            let x = index % side, y = index / side, offset = index * 4
            let dx = Double(x) - centre, dy = Double(y) - centre
            return Pixel(
                red: Double(buffer[offset]), green: Double(buffer[offset + 1]), blue: Double(buffer[offset + 2]),
                radius: (dx * dx + dy * dy).squareRoot() / Double(side)
            )
        }
    }

    // MARK: - Track change (PlayerService.swift)

    /// `play(tracks:startIndex:)` deciding whether a skip started a new queue.
    static func isNewQueue(tracks: [DisplayableSong], state: PlayerState) -> Bool {
        let currentQueueIds = state.queue.map(\.id)
        return tracks.map(\.id) != currentQueueIds
    }

    /// The MainActor read at the top of `evaluateAutoExtend`, before any guard.
    static func autoExtendRead(_ state: PlayerState) -> (Int, Set<String>) {
        let remaining = state.queue.count - state.currentIndex - 1
        return (remaining, Set(state.queue.map(\.id)))
    }
}
