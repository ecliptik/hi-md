import CoreGraphics
import Foundation

/// The Mac MiniPlayer's layouts, after the Music app's MiniPlayer. The artwork always runs to the
/// window's edges, its top under the traffic lights, and the controls lie over it while the pointer
/// is there (`PlayerChromeVisibility`):
/// - compact: only the artwork, so the window is square and resizing it scales the artwork;
/// - tall: a pane (the queue, lyrics, library or related songs) under the artwork;
/// - wide: the artwork down the left, full height, and the pane beside it.
///
/// The window hugs what it shows: opening a pane from compact adds `paneHeight` under the
/// artwork (or `paneWidth` beside it when the screen has no room below), and closing it goes back
/// to the size it had (`MiniPlayerWindowSizing`).
nonisolated enum MiniPlayerLayout: String, CaseIterable, Sendable {
    case compact
    case tall
    case wide

    /// The compact window's side when it first opens.
    static let defaultSide: Double = 320
    /// The smallest compact window: room for the song, the scrubber and the transport over the
    /// artwork, and the glass buttons at the top clear of the traffic lights.
    static let minimumSide: Double = 260
    /// The largest compact window.
    static let maximumSide: Double = 720
    /// What opening a pane adds under the artwork: about seven rows of the queue and its header.
    static let paneHeight: Double = 340
    /// What opening a pane beside the artwork adds.
    static let paneWidth: Double = 340
    /// The least room a pane keeps under or beside the artwork.
    static let minimumPaneHeight: Double = 200
    static let minimumPaneWidth: Double = 280

    /// The layout for a window of `size`. Without a pane it's compact, whatever its shape; with
    /// one the pane goes beside the artwork once the window has room for it there.
    static func layout(for size: CGSize, isPaneOpen: Bool) -> MiniPlayerLayout {
        guard isPaneOpen, size.width > 0, size.height > 0 else { return .compact }
        return Double(size.width - size.height) >= minimumPaneWidth ? .wide : .tall
    }

    /// The artwork's side in a window of `size`: the whole width (tall) or height (wide), less
    /// whatever the pane needs to keep its least room.
    func artworkSide(in size: CGSize) -> Double {
        let width = Double(size.width), height = Double(size.height)
        switch self {
        case .compact: return max(min(width, height), 0)
        case .tall: return max(min(width, height - Self.minimumPaneHeight), 0)
        case .wide: return max(min(height, width - Self.minimumPaneWidth), 0)
        }
    }

    /// The room the pane gets under (tall) or beside (wide) the artwork.
    func paneSize(in size: CGSize) -> CGSize {
        let side = artworkSide(in: size)
        switch self {
        case .compact: return .zero
        case .tall: return CGSize(width: size.width, height: max(Double(size.height) - side, 0))
        case .wide: return CGSize(width: max(Double(size.width) - side, 0), height: size.height)
        }
    }

    /// The least and most the window can be in this layout. A compact window also keeps a 1:1
    /// aspect ratio, so dragging any edge scales the artwork.
    var minimumSize: CGSize {
        switch self {
        case .compact: CGSize(width: Self.minimumSide, height: Self.minimumSide)
        case .tall: CGSize(width: Self.minimumSide, height: Self.minimumSide + Self.minimumPaneHeight)
        case .wide: CGSize(width: Self.minimumSide + Self.minimumPaneWidth, height: Self.minimumSide)
        }
    }

    var maximumSize: CGSize {
        switch self {
        case .compact: CGSize(width: Self.maximumSide, height: Self.maximumSide)
        case .tall, .wide: CGSize(width: 10_000, height: 10_000)
        }
    }

    static func clampedSide(_ side: Double) -> Double {
        min(max(side, minimumSide), maximumSide)
    }

    /// A compact window with an artwork of `side` points, within the limits.
    static func compactSize(side: Double) -> CGSize {
        let side = clampedSide(side).rounded()
        return CGSize(width: side, height: side)
    }

    /// The window a compact one grows to when a pane opens: the pane under the artwork, or
    /// beside it when `available` (the room on screen below the window's top edge) is too short;
    /// with room for neither, the pane under it as tall as the screen allows.
    static func openedSize(fromCompact size: CGSize, available: CGSize?) -> CGSize {
        let side = Double(compactSize(side: compact.artworkSide(in: size)).width)
        let tall = CGSize(width: side, height: side + paneHeight)
        let wide = CGSize(width: side + paneWidth, height: side)
        guard let available else { return tall }
        func fits(_ candidate: CGSize) -> Bool {
            candidate.width <= available.width + 0.5 && candidate.height <= available.height + 0.5
        }
        if fits(tall) { return tall }
        if fits(wide) { return wide }
        return CGSize(width: side, height: max(Double(available.height).rounded(.down), side + minimumPaneHeight))
    }

    /// The compact window a pane closes to when the size before it opened isn't known (it was
    /// open at launch): as big as the artwork was.
    static func collapsedSize(from size: CGSize, isPaneOpen: Bool) -> CGSize {
        compactSize(side: layout(for: size, isPaneOpen: isPaneOpen).artworkSide(in: size))
    }

    /// `size` brought in line with the pane state, for a window restored from an earlier launch
    /// or version: square without a pane, and with one at least its layout's minimum and tall
    /// enough that the artwork spans the width.
    static func reconciled(_ size: CGSize, isPaneOpen: Bool) -> CGSize {
        let width = Double(size.width), height = Double(size.height)
        guard isPaneOpen else { return compactSize(side: min(width, height)) }
        let layout = layout(for: size, isPaneOpen: true)
        let least = layout.minimumSize
        var fitted = CGSize(width: max(width, Double(least.width)), height: max(height, Double(least.height)))
        if layout == .tall, Double(fitted.height) < Double(fitted.width) + minimumPaneHeight {
            fitted.height = fitted.width + minimumPaneHeight
        }
        return fitted
    }
}

/// The MiniPlayer's panes. The songs played earlier ("Back To") sit above the current one in the
/// queue.
nonisolated enum MiniPlayerPane: String, CaseIterable, Sendable {
    case library
    case upNext
    /// Songs like the one playing, from the server's similar songs.
    case related
    case lyrics
}

/// What a pane button or menu item does to the window.
nonisolated enum MiniPlayerPaneChange: Equatable, Sendable {
    /// Nothing to do: that pane is already showing.
    case none
    /// A pane opens in a compact window, which grows to show it.
    case open
    /// Another pane takes the open one's place; the window stays as it is.
    case switchPane
    /// The pane closes and the window goes back to compact.
    case close
}

/// Which pane the MiniPlayer shows and whether one is open. The glass capsule's Lyrics and Queue
/// are toggles: they open their pane, switch to it, or close it when it's the one showing. The
/// … menu's Library and Related Songs only open or switch.
nonisolated struct MiniPlayerPanelState: Equatable, Sendable {
    var pane: MiniPlayerPane = .upNext
    var isOpen = false

    /// The pane on screen: Lyrics falls back to the queue for a song without lyrics.
    func shownPane(canShowLyrics: Bool) -> MiniPlayerPane {
        pane == .lyrics && !canShowLyrics ? .upNext : pane
    }

    func isShowing(_ pane: MiniPlayerPane, canShowLyrics: Bool) -> Bool {
        isOpen && shownPane(canShowLyrics: canShowLyrics) == pane
    }

    /// The capsule's Lyrics or Queue.
    mutating func toggle(_ pane: MiniPlayerPane, canShowLyrics: Bool) -> MiniPlayerPaneChange {
        if isShowing(pane, canShowLyrics: canShowLyrics) {
            isOpen = false
            return .close
        }
        return show(pane, canShowLyrics: canShowLyrics)
    }

    /// The … menu's Library or Related Songs.
    mutating func show(_ pane: MiniPlayerPane, canShowLyrics: Bool) -> MiniPlayerPaneChange {
        if isShowing(pane, canShowLyrics: canShowLyrics) { return .none }
        let wasOpen = isOpen
        self.pane = pane
        isOpen = true
        return wasOpen ? .switchPane : .open
    }

    mutating func close() -> MiniPlayerPaneChange {
        guard isOpen else { return .none }
        isOpen = false
        return .close
    }
}

/// The MiniPlayer window's size as panes open and close: opening one from compact remembers the
/// compact size, and closing it goes back to exactly that size, however the window was resized
/// while the pane was open.
nonisolated struct MiniPlayerWindowSizing: Equatable, Sendable {
    /// The compact window before the pane opened.
    private(set) var compactSize: CGSize?

    /// The size for opening a pane in a compact window of `size`.
    mutating func sizeOpeningPane(from size: CGSize, available: CGSize?) -> CGSize {
        compactSize = size
        return MiniPlayerLayout.openedSize(fromCompact: size, available: available)
    }

    /// The compact size to go back to when the pane closes.
    mutating func sizeClosingPane(from size: CGSize) -> CGSize {
        defer { compactSize = nil }
        return compactSize ?? MiniPlayerLayout.collapsedSize(from: size, isPaneOpen: true)
    }
}

/// Which windows the MiniPlayer may touch, and what closing it does to the main window. The
/// MiniPlayer only ever resizes, re-levels or re-targets its own window, never one of the main
/// window group's, and closing it never moves or resizes a main window: it brings back only what
/// it put away itself, and opens a new main window only when there's none at all.
nonisolated enum MiniPlayerWindowIdentity {
    /// Whether a window with `identifier` may be adopted by the MiniPlayer's window handle: not
    /// one of the main window group's (`mainID-AppWindow-N`). Windows the system names otherwise,
    /// or not at all, are the MiniPlayer's own, since its reader only lives in its own window.
    static func mayAdopt(identifier: String?, miniPlayerID: String, mainID: String) -> Bool {
        guard let identifier, !identifier.isEmpty else { return true }
        if identifier.hasPrefix(miniPlayerID) { return true }
        return !identifier.hasPrefix(mainID)
    }

    /// A main window as the MiniPlayer sees it when it closes, by window number.
    struct MainWindow: Equatable, Sendable {
        let number: Int
        let isVisible: Bool
        let isMiniaturized: Bool
    }

    enum Reveal: Equatable, Sendable {
        /// A main window is on screen: leave every window as it is.
        case none
        /// Order these windows (the ones the MiniPlayer put away) back in, frames untouched.
        case orderFront([Int])
        /// Take this window out of the Dock.
        case deminiaturize(Int)
        /// No main window at all: open one.
        case openNew
    }

    /// What closing the MiniPlayer (or Show Hi-MD) does so the app isn't left without a window,
    /// given the main windows and the ones the MiniPlayer hid. It never picks a window it didn't
    /// hide over one that's showing, and never opens a second main window beside an existing one:
    /// a new window from a window group comes up at the default size, which looked like the main
    /// window losing its zoomed frame.
    static func reveal(mainWindows: [MainWindow], hiddenByMiniPlayer: Set<Int>) -> Reveal {
        let hidden = mainWindows.filter { hiddenByMiniPlayer.contains($0.number) && !$0.isVisible && !$0.isMiniaturized }
        if !hidden.isEmpty { return .orderFront(hidden.map(\.number)) }
        if mainWindows.contains(where: \.isVisible) { return .none }
        if let docked = mainWindows.first(where: \.isMiniaturized) { return .deminiaturize(docked.number) }
        return .openNew
    }
}

/// The MiniPlayer queue's sections, as the Music app has them: the songs the listener queued
/// under "Playing Next", then the ones Autoplay added under "Continue Playing".
nonisolated enum MiniPlayerQueueSections {
    /// Splits the upcoming songs at `autoplayStart`, the queue index where Autoplay's songs
    /// begin (nil when it added none).
    static func split<Entry>(_ upcoming: [Entry], queueIndex: (Entry) -> Int,
                             autoplayStart: Int?) -> (requested: [Entry], autoplay: [Entry]) {
        guard let autoplayStart else { return (upcoming, []) }
        let requested = upcoming.filter { queueIndex($0) < autoplayStart }
        let autoplay = upcoming.filter { queueIndex($0) >= autoplayStart }
        return (requested, autoplay)
    }

    /// The pane's heading: "Playing Next" while the listener's own songs are coming up, and
    /// "Continue Playing" once only Autoplay's are.
    static func headingIsContinuePlaying(requestedCount: Int, autoplayCount: Int) -> Bool {
        requestedCount == 0 && autoplayCount > 0
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

/// The MiniPlayer queue's rows from top to bottom: "Back To" and the songs played earlier, "Now
/// Playing" and the current song, then the listener's songs and Autoplay's under their headings.
///
/// It's one list in queue order, and each song keeps its identity (its id and which occurrence of
/// it in the queue) whichever section it's in, so clicking a song further down only moves the
/// headings and the highlight: no row is rebuilt and the rows below stay where they were. The
/// current song is the queue's, at `currentIndex`, so the list doesn't show the old song twice in
/// the moment before the player has caught up with a jump.
nonisolated enum MiniPlayerQueueRows {
    enum Heading: String, Hashable, Sendable {
        case backTo, nowPlaying, playingNext, continuePlaying
    }

    enum Role: Equatable, Sendable {
        /// Played earlier; dimmed, and clicking it goes back.
        case history
        case current
        /// Coming up, queued by the listener.
        case requested
        /// Coming up, added by Autoplay.
        case autoplay
    }

    struct Song: Equatable, Sendable {
        let index: Int
        let song: DisplayableSong
        let role: Role
        /// Its place among the upcoming songs, for Move Up and Move Down; nil for the others.
        let upcomingPosition: Int?
        /// Which occurrence of the song in the queue this is, 0 for the first.
        let occurrence: Int
    }

    enum Item: Equatable, Sendable, Identifiable {
        case heading(Heading)
        case song(Song)

        enum ID: Hashable, Sendable {
            case heading(Heading)
            /// The song's id and which of its occurrences in the queue this is.
            case song(String, occurrence: Int)
        }

        var id: ID {
            switch self {
            case .heading(let heading): .heading(heading)
            case .song(let row): .song(row.song.id, occurrence: row.occurrence)
            }
        }
    }

    /// - Parameters:
    ///   - isPlaying: something from the queue is playing; without it there's no current row.
    ///   - autoplayStart: the queue index where Autoplay's songs begin, nil when it added none.
    ///   - historyLimit: at most this many earlier songs, the most recent ones.
    static func items(queue: [DisplayableSong], currentIndex: Int, isPlaying: Bool, autoplayStart: Int?,
                      historyLimit: Int = 100) -> [Item] {
        let counts = occurrences(queue)
        var items: [Item] = []
        let historyEnd = min(max(currentIndex, 0), queue.count)
        let historyStart = max(historyEnd - historyLimit, 0)
        if historyStart < historyEnd {
            items.append(.heading(.backTo))
            for index in historyStart..<historyEnd {
                items.append(.song(Song(index: index, song: queue[index], role: .history, upcomingPosition: nil,
                                        occurrence: counts[index])))
            }
        }
        if isPlaying, queue.indices.contains(currentIndex) {
            items.append(.heading(.nowPlaying))
            items.append(.song(Song(index: currentIndex, song: queue[currentIndex], role: .current,
                                    upcomingPosition: nil, occurrence: counts[currentIndex])))
        }
        items += upcomingItems(queue: queue, after: currentIndex, autoplayStart: autoplayStart, occurrences: counts)
        return items
    }

    /// Whether anything is coming up after the current song.
    static func hasUpcoming(_ items: [Item]) -> Bool {
        items.contains { item in
            if case .song(let row) = item { return row.upcomingPosition != nil }
            return false
        }
    }

    private static func upcomingItems(queue: [DisplayableSong], after currentIndex: Int, autoplayStart: Int?,
                                      occurrences: [Int]) -> [Item] {
        let upcoming = Array(queue.indices.filter { $0 > currentIndex })
        let sections = MiniPlayerQueueSections.split(upcoming, queueIndex: { $0 }, autoplayStart: autoplayStart)
        var items: [Item] = []
        if !sections.requested.isEmpty, !sections.autoplay.isEmpty {
            items.append(.heading(.playingNext))
        }
        for (position, index) in sections.requested.enumerated() {
            items.append(.song(Song(index: index, song: queue[index], role: .requested, upcomingPosition: position,
                                    occurrence: occurrences[index])))
        }
        if !sections.autoplay.isEmpty {
            items.append(.heading(.continuePlaying))
            for (offset, index) in sections.autoplay.enumerated() {
                items.append(.song(Song(index: index, song: queue[index], role: .autoplay,
                                        upcomingPosition: sections.requested.count + offset,
                                        occurrence: occurrences[index])))
            }
        }
        return items
    }

    /// For each place in the queue, how many times its song came before it.
    private static func occurrences(_ queue: [DisplayableSong]) -> [Int] {
        var seen: [String: Int] = [:]
        return queue.map { song in
            let occurrence = seen[song.id, default: 0]
            seen[song.id] = occurrence + 1
            return occurrence
        }
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
