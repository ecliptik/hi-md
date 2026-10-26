import CoreGraphics
import Foundation

/// The Mac MiniPlayer's three layouts, chosen from the window's size, as Plexamp's mini player
/// does: a square-ish window shows the artwork above the song; a tall one adds the transport,
/// volume and the History, Playing Next, Related and Lyrics tabs; a wide one puts the artwork
/// beside everything else.
nonisolated enum MiniPlayerLayout: String, CaseIterable, Sendable {
    case compact
    case tall
    case wide

    /// The space around the artwork.
    static let inset: Double = 14
    /// What the compact layout draws under the artwork: the scrubber, the song, its details and
    /// the toolbar.
    static let compactChrome: Double = 160
    /// The tall layout adds the album line, the transport, the volume and the tab bar.
    static let tallChrome: Double = 316
    /// The least room the tall layout leaves its tab.
    static let minimumPanelHeight: Double = 180

    static let defaultWidth: Double = 300
    static let minimumWidth: Double = 260
    static let minimumHeight: Double = 220
    static let tallMinimumHeight: Double = 560
    /// Width over height from which the window is wide.
    static let wideAspect: Double = 1.4
    /// Height over width from which the window is tall.
    static let tallAspect: Double = 1.8

    static func layout(for size: CGSize) -> MiniPlayerLayout {
        guard size.width > 0, size.height > 0 else { return .compact }
        if size.width >= size.height * wideAspect { return .wide }
        if size.height >= size.width * tallAspect, size.height >= tallMinimumHeight { return .tall }
        return .compact
    }

    /// The compact window for `width`: the artwork fills the width and the details fit under it.
    static func compactHeight(forWidth width: Double) -> Double {
        (inset + (width - 2 * inset) + compactChrome).rounded()
    }

    /// The tall window for `width`, with room for the tabs.
    static func tallHeight(forWidth width: Double) -> Double {
        max(tallMinimumHeight, (width * 2.5).rounded())
    }

    /// The artwork's side in this layout for a window of `size`.
    func artworkSide(in size: CGSize) -> Double {
        let width = Double(size.width), height = Double(size.height)
        let inset = Self.inset
        switch self {
        case .compact:
            return max(min(width - 2 * inset, height - inset - Self.compactChrome), 48)
        case .tall:
            return max(min(width - 2 * inset, height - inset - Self.tallChrome - Self.minimumPanelHeight), 96)
        case .wide:
            // The details keep at least 240 points beside the artwork.
            return max(min(height - 2 * inset, width - 3 * inset - 240), 64)
        }
    }

    /// The window after the chevron: compact expands to tall, tall collapses to compact, and wide
    /// expands to a tall window about as wide as its artwork.
    static func toggledSize(from size: CGSize) -> CGSize {
        let width = Double(size.width)
        switch layout(for: size) {
        case .compact:
            return CGSize(width: width, height: tallHeight(forWidth: width))
        case .tall:
            return CGSize(width: width, height: compactHeight(forWidth: width))
        case .wide:
            let narrow = min(max(Double(size.height), minimumWidth), 420)
            return CGSize(width: narrow, height: tallHeight(forWidth: narrow))
        }
    }

    /// The widest a wide window gets for its height (3:1), and the tallest a tall one gets for
    /// its width, so the window can't be dragged into a strip the layouts can't fill.
    static let maximumWideAspect: Double = 3
    static let maximumTallAspect: Double = 3.2

    /// The window's largest content size while it's `size`, refreshed as it resizes: dragging
    /// one edge can't take the shape past the limits.
    static func maximumContentSize(for size: CGSize) -> CGSize {
        CGSize(width: max(Double(size.height) * maximumWideAspect, minimumWidth),
               height: max(Double(size.width) * maximumTallAspect, minimumHeight))
    }

    /// `size` brought inside those limits, for a window that was saved or zoomed outside them.
    static func clamped(_ size: CGSize) -> CGSize {
        var width = max(Double(size.width), minimumWidth)
        var height = max(Double(size.height), minimumHeight)
        if width > height * maximumWideAspect { width = height * maximumWideAspect }
        if height > width * maximumTallAspect { height = width * maximumTallAspect }
        return CGSize(width: width, height: height)
    }

    /// Whether the chevron expands (compact, wide) or collapses (tall).
    var expands: Bool { self != .tall }
}

/// The tall MiniPlayer's tabs.
nonisolated enum MiniPlayerTab: String, CaseIterable, Sendable {
    /// The songs played earlier in the queue (Plexamp's "Back To").
    case history
    case upNext
    /// Songs like the one playing, from the server's similar songs.
    case related
}

/// Which tab the tall MiniPlayer shows, and whether lyrics are on. Lyrics are a toggle: clicking
/// them again turns them off and brings back the tab that was showing. In the compact and wide
/// layouts the lyrics take the artwork's place.
nonisolated struct MiniPlayerPanelState: Equatable, Sendable {
    var tab: MiniPlayerTab = .upNext
    var showsLyrics = false

    func isShowingLyrics(canShowLyrics: Bool) -> Bool { showsLyrics && canShowLyrics }

    func isSelected(_ tab: MiniPlayerTab, canShowLyrics: Bool) -> Bool {
        !isShowingLyrics(canShowLyrics: canShowLyrics) && self.tab == tab
    }

    /// Choosing a tab turns lyrics off.
    mutating func select(_ tab: MiniPlayerTab) {
        self.tab = tab
        showsLyrics = false
    }

    mutating func toggleLyrics() {
        showsLyrics.toggle()
    }
}

/// A song played earlier in the queue, with its place, so clicking it can jump back to it.
nonisolated struct QueueHistoryEntry: Equatable, Sendable, Identifiable {
    let index: Int
    let song: DisplayableSong

    var id: Int { index }
}

nonisolated enum QueueHistory {
    /// The songs before the current one, the most recent first, at most `limit` of them.
    static func earlier(in queue: [DisplayableSong], currentIndex: Int, limit: Int = 100) -> [QueueHistoryEntry] {
        guard currentIndex > 0, !queue.isEmpty else { return [] }
        let end = min(currentIndex, queue.count)
        let start = max(end - limit, 0)
        return (start..<end).reversed().map { QueueHistoryEntry(index: $0, song: queue[$0]) }
    }
}

nonisolated enum RelatedSongs {
    /// The server's similar songs without the one playing and without repeats.
    static func filtered(_ songs: [DisplayableSong], excluding currentID: String?) -> [DisplayableSong] {
        var seen = Set<String>()
        if let currentID { seen.insert(currentID) }
        return songs.filter { seen.insert($0.id).inserted }
    }

    /// Each More asks for this many more, up to the cap.
    static let pageSize = 20
    static let maximumCount = 100
}

/// The MiniPlayer's format label: what is actually playing, not only the file on the server.
/// A local copy is labelled from its own container; a stream from what it asks the server for.
nonisolated enum NowPlayingFormat {
    static func label(originalSuffix: String?, originalBitRate: Int?, localFileExtension: String?,
                      streamRequest: StreamRequest?) -> String? {
        let original = originalSuffix?.lowercased()
        if let local = localFileExtension?.lowercased(), local != "bin", !local.isEmpty {
            // The same container as the original is the original itself.
            return local == original ? codecName(local, bitRate: originalBitRate) : codecName(local, bitRate: nil)
        }
        if let streamRequest, !streamRequest.isOriginal {
            return codecName(streamRequest.format, bitRate: nil)
        }
        return codecName(original, bitRate: originalBitRate)
    }

    /// A codec's usual name from a file extension or Subsonic format. MPEG-4 audio above
    /// 500 kbps is taken for ALAC, below it for AAC.
    static func codecName(_ suffix: String?, bitRate: Int?) -> String? {
        guard let suffix = suffix?.lowercased().trimmingCharacters(in: .whitespaces), !suffix.isEmpty,
              suffix != "raw", suffix != "bin" else { return nil }
        switch suffix {
        case "opus": return "Opus"
        case "ogg", "oga": return "Vorbis"
        case "m4a", "mp4", "m4b": return (bitRate ?? 0) > 500 ? "ALAC" : "AAC"
        case "aif", "aiff": return "AIFF"
        case "dsf", "dff": return "DSD"
        case "wv": return "WavPack"
        default: return suffix.uppercased()
        }
    }
}
