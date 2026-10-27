import CoreGraphics
import Foundation

/// The Mac MiniPlayer's three layouts, chosen from the window's size, as Plexamp's mini player
/// does: a square-ish window shows the artwork above the song; a tall one adds the transport,
/// volume and the Library, Playing Next, Related and Lyrics tabs; a wide one puts the artwork
/// beside everything else, with the same panes between the song and the controls when one is
/// open.
///
/// Every layout keeps a band along the top for the window's close, minimise and zoom buttons
/// (`topInset`, measured from the real buttons), so no content sits under them.
nonisolated enum MiniPlayerLayout: String, CaseIterable, Sendable {
    case compact
    case tall
    case wide

    /// The space around the artwork.
    static let inset: Double = 14
    /// The band kept for the traffic lights when they can't be measured: the title bar's height.
    static let titleBarBand: Double = 28
    /// What the compact layout draws under the artwork: the scrubber, the song, its details and
    /// the toolbar.
    static let compactChrome: Double = 160
    /// The tall layout adds the album line, the transport, the volume and the tab bar.
    static let tallChrome: Double = 316
    /// The least room the tall layout leaves its tab.
    static let minimumPanelHeight: Double = 180
    /// What the wide layout's right column draws besides a pane: the song, its details, the
    /// scrubber, the transport and the toolbar.
    static let wideDetailsChrome: Double = 190
    /// The least room the wide layout gives an open pane.
    static let wideMinimumPaneHeight: Double = 150
    /// The least width of the wide layout's right column, and the pane's width when a compact
    /// window grows to show one.
    static let wideDetailsMinimumWidth: Double = 240
    static let widePaneWidth: Double = 320

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

    /// The space above the content: the traffic lights' band, or the inset if that's more.
    static func topSpace(_ topInset: Double) -> Double { max(topInset, inset) }

    /// The compact window for `width`: the artwork fills the width and the details fit under it.
    static func compactHeight(forWidth width: Double, topInset: Double = titleBarBand) -> Double {
        (topSpace(topInset) + (width - 2 * inset) + compactChrome).rounded()
    }

    /// The tall window for `width`, with room for the tabs.
    static func tallHeight(forWidth width: Double) -> Double {
        max(tallMinimumHeight, (width * 2.5).rounded())
    }

    /// The artwork's side in this layout for a window of `size`.
    func artworkSide(in size: CGSize, topInset: Double = Self.titleBarBand) -> Double {
        let width = Double(size.width), height = Double(size.height)
        let inset = Self.inset, top = Self.topSpace(topInset)
        switch self {
        case .compact:
            return max(min(width - 2 * inset, height - top - Self.compactChrome), 48)
        case .tall:
            return max(min(width - 2 * inset, height - top - Self.tallChrome - Self.minimumPanelHeight), 96)
        case .wide:
            // The details keep at least 240 points beside the artwork.
            return max(min(height - top - inset, width - 3 * inset - Self.wideDetailsMinimumWidth), 64)
        }
    }

    /// The window after the chevron: compact expands to tall, tall collapses to compact, and wide
    /// expands to a tall window about as wide as its artwork.
    static func toggledSize(from size: CGSize, topInset: Double = titleBarBand) -> CGSize {
        let width = Double(size.width)
        switch layout(for: size) {
        case .compact:
            return CGSize(width: width, height: tallHeight(forWidth: width))
        case .tall:
            return CGSize(width: width, height: compactHeight(forWidth: width, topInset: topInset))
        case .wide:
            let narrow = min(max(Double(size.height), minimumWidth), 420)
            return CGSize(width: narrow, height: tallHeight(forWidth: narrow))
        }
    }

    /// The compact window a tall or wide one collapses to when its pane closes: as wide as a
    /// tall one, or about as wide as a wide one's artwork.
    static func collapsedSize(from size: CGSize, topInset: Double = titleBarBand) -> CGSize {
        switch layout(for: size) {
        case .compact:
            return size
        case .tall:
            return toggledSize(from: size, topInset: topInset)
        case .wide:
            let side = MiniPlayerLayout.wide.artworkSide(in: size, topInset: topInset)
            let width = min(max(side + 2 * inset, minimumWidth), 420).rounded()
            return CGSize(width: width, height: compactHeight(forWidth: width, topInset: topInset))
        }
    }

    /// A wide window for the compact window `size` that shows a pane beside an artwork at least
    /// as big as the compact one's, and tall enough for the pane.
    static func wideSize(fromCompact size: CGSize, topInset: Double = titleBarBand) -> CGSize {
        let side = MiniPlayerLayout.compact.artworkSide(in: size, topInset: topInset)
        let top = topSpace(topInset)
        let height = max(side + top + inset, top + inset + wideDetailsChrome + wideMinimumPaneHeight).rounded()
        let artwork = height - top - inset
        let width = min(3 * inset + artwork + widePaneWidth, height * maximumWideAspect).rounded()
        return CGSize(width: max(width, (height * wideAspect).rounded()), height: height)
    }

    /// The window a compact one grows to when a pane opens in it: tall or wide, whichever is the
    /// smaller change that fits in `available` (the room on screen), or wide, the shorter, when
    /// neither fits.
    static func grownSize(fromCompact size: CGSize, available: CGSize?, topInset: Double = titleBarBand) -> CGSize {
        let tall = CGSize(width: size.width, height: tallHeight(forWidth: Double(size.width)))
        let wide = wideSize(fromCompact: size, topInset: topInset)
        func change(_ candidate: CGSize) -> Double {
            hypot(Double(candidate.width - size.width), Double(candidate.height - size.height))
        }
        func fits(_ candidate: CGSize) -> Bool {
            guard let available else { return true }
            return candidate.width <= available.width + 0.5 && candidate.height <= available.height + 0.5
        }
        return [tall, wide].filter(fits).min { change($0) < change($1) } ?? wide
    }

    /// A wide window tall enough for an open pane, as wide as before (or wider, should the extra
    /// height stop it being wide). Nil when it already has the room.
    static func wideSizeShowingPane(from size: CGSize, topInset: Double = titleBarBand) -> CGSize? {
        let needed = (topSpace(topInset) + inset + wideDetailsChrome + wideMinimumPaneHeight).rounded()
        guard layout(for: size) == .wide, Double(size.height) < needed else { return nil }
        let width = max(Double(size.width), (needed * wideAspect).rounded())
        return CGSize(width: width, height: needed)
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

    /// Whether this layout shows a pane: tall always, wide while one is open, compact never.
    func showsPane(isOpen: Bool) -> Bool {
        switch self {
        case .compact: false
        case .tall: true
        case .wide: isOpen
        }
    }
}

/// The MiniPlayer's panes: the tall layout's tabs, and what opens beside the artwork in the wide
/// one. The songs played earlier (Plexamp's "Back To") sit above the current one in Playing Next.
nonisolated enum MiniPlayerPane: String, CaseIterable, Sendable {
    case library
    case upNext
    /// Songs like the one playing, from the server's similar songs.
    case related
    case lyrics
}

/// What a click on the toolbar's Library or Lyrics button does to the window.
nonisolated enum MiniPlayerPaneChange: Equatable, Sendable {
    /// Shows the pane in place: a tall window's tab, or a wide window's pane.
    case show
    /// Grows a compact window to a tall or wide one showing the pane.
    case grow
    /// Closes a wide window's pane, leaving the window as it is.
    case close
    /// Back to a compact window: from tall, or from a wide one that grew from compact.
    case collapse
}

/// Which pane the MiniPlayer shows, and whether the wide layout has it open. The toolbar's
/// Library and Lyrics buttons are toggles: on a compact window they grow it to show the pane, and
/// clicking the one that's showing puts the window back as it was.
nonisolated struct MiniPlayerPanelState: Equatable, Sendable {
    var pane: MiniPlayerPane = .upNext
    /// The wide layout's pane; tall always shows one and compact never does.
    var isOpen = false

    /// The pane on screen: Lyrics falls back to Playing Next for a song without lyrics.
    func shownPane(canShowLyrics: Bool) -> MiniPlayerPane {
        pane == .lyrics && !canShowLyrics ? .upNext : pane
    }

    func isShowing(_ pane: MiniPlayerPane, in layout: MiniPlayerLayout, canShowLyrics: Bool) -> Bool {
        layout.showsPane(isOpen: isOpen) && shownPane(canShowLyrics: canShowLyrics) == pane
    }

    /// A tab: shows that pane.
    mutating func select(_ pane: MiniPlayerPane) {
        self.pane = pane
        isOpen = true
    }

    /// The toolbar's button for `pane`: hides the pane when it's showing, otherwise shows it,
    /// growing a compact window. `grewFromCompact` says a wide window grew from a compact one,
    /// so hiding its pane puts it back.
    mutating func toggle(_ pane: MiniPlayerPane, in layout: MiniPlayerLayout, canShowLyrics: Bool,
                         grewFromCompact: Bool) -> MiniPlayerPaneChange {
        if isShowing(pane, in: layout, canShowLyrics: canShowLyrics) {
            // Closed either way, so dragging the compact window wide again doesn't bring it back.
            isOpen = false
            return layout == .wide && !grewFromCompact ? .close : .collapse
        }
        self.pane = pane
        isOpen = true
        return layout == .compact ? .grow : .show
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

/// Moving a song in Up Next one place with the MiniPlayer's Move Up and Move Down, in the terms
/// of the queue's move: the place it's inserted before, counted in the queue as it is now.
nonisolated enum QueueStep {
    /// Where the song at `upcomingPosition` (0 for the song after the current one) of `count`
    /// upcoming songs goes, or nil at the ends. `queueIndex(for:)` turns a position into the
    /// song's place in the queue; past the last song the place is `queueCount`.
    static func destination(movingPosition position: Int, by delta: Int, upcomingCount count: Int,
                            queueIndex: (Int) -> Int, queueCount: Int) -> Int? {
        guard (0..<count).contains(position), delta == -1 || delta == 1 else { return nil }
        let target = position + delta
        guard (0..<count).contains(target) else { return nil }
        // As with a list's move: down by one inserts before the song two places on.
        let before = delta > 0 ? position + 2 : target
        return before < count ? queueIndex(before) : queueCount
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
