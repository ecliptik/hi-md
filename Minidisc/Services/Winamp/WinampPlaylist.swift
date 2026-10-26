import CoreGraphics
import Foundation

/// The playlist window's size in Winamp's resize steps: 25 pixels across and 29 down, from the
/// smallest window of 275×116.
nonisolated struct WinampPlaylistSize: Sendable, Hashable, Codable {
    static let minimum = CGSize(width: 275, height: 116)
    static let widthStep: CGFloat = 25
    static let heightStep: CGFloat = 29
    static let maximumSteps = 60
    /// Winamp's default playlist: as wide as the main window, 232 pixels tall.
    static let standard = WinampPlaylistSize(widthSteps: 0, heightSteps: 4)

    let widthSteps: Int
    let heightSteps: Int

    init(widthSteps: Int, heightSteps: Int) {
        self.widthSteps = min(max(widthSteps, 0), Self.maximumSteps)
        self.heightSteps = min(max(heightSteps, 0), Self.maximumSteps)
    }

    var pixelSize: CGSize {
        CGSize(width: Self.minimum.width + CGFloat(widthSteps) * Self.widthStep,
               height: Self.minimum.height + CGFloat(heightSteps) * Self.heightStep)
    }

    /// The nearest whole-step size to `size`, never below the minimum, for a resize drag.
    static func fitting(_ size: CGSize) -> WinampPlaylistSize {
        let width = size.width.isFinite ? size.width : minimum.width
        let height = size.height.isFinite ? size.height : minimum.height
        return WinampPlaylistSize(widthSteps: Int(((width - minimum.width) / widthStep).rounded()),
                                  heightSteps: Int(((height - minimum.height) / heightStep).rounded()))
    }
}

/// The pop-up menus along the playlist window's bottom edge.
nonisolated enum WinampPlaylistMenuKind: CaseIterable, Sendable, Hashable {
    case add
    case remove
    case select
    case misc
    case list

    /// The items from top to bottom, in the order of their sprites in `pledit.bmp`.
    var items: [WinampPlaylistMenuItem] {
        switch self {
        case .add: [.addURL, .addFolder, .addFile]
        case .remove: [.removeAll, .crop, .removeSelected, .removeMisc]
        case .select: [.invertSelection, .selectNone, .selectAll]
        case .misc: [.sort, .fileInfo, .options]
        case .list: [.newList, .saveList, .loadList]
        }
    }

    var sprites: WinampSprites.PlaylistMenu {
        switch self {
        case .add: WinampSprites.playlistAddMenu
        case .remove: WinampSprites.playlistRemoveMenu
        case .select: WinampSprites.playlistSelectMenu
        case .misc: WinampSprites.playlistMiscMenu
        case .list: WinampSprites.playlistListMenu
        }
    }
}

nonisolated enum WinampPlaylistMenuItem: Sendable, Hashable {
    case addURL, addFolder, addFile
    case removeAll, crop, removeSelected, removeMisc
    case invertSelection, selectNone, selectAll
    case sort, fileInfo, options
    case newList, saveList, loadList
}

/// The small transport buttons in the bottom-right corner.
nonisolated enum WinampPlaylistMiniButton: CaseIterable, Sendable, Hashable {
    case previous, play, pause, stop, next, eject
}

/// Something in the playlist window that reacts to the mouse.
nonisolated enum WinampPlaylistControl: Sendable, Hashable {
    case titleBar
    case close
    case shade
    case list
    case scrollBar
    case resize
    case menu(WinampPlaylistMenuKind)
    case mini(WinampPlaylistMiniButton)
    /// The running time; clicking it does nothing, as in Winamp.
    case footer
}

/// Where the playlist window draws its parts, for any size, in window pixels from the top left.
/// The coordinates follow the classic skin format as documented by the Webamp project (MIT); no
/// Webamp code is used.
nonisolated enum WinampPlaylistLayout {
    static let titleHeight: CGFloat = 20
    static let bottomHeight: CGFloat = 38
    static let leftWidth: CGFloat = 12
    static let rightWidth: CGFloat = 20
    static let rowHeight: CGFloat = 13
    static let shadeHeight: CGFloat = 14
    static let menuItemHeight: CGFloat = 18
    static let menuItemWidth: CGFloat = 22

    /// The track list, between the side tiles and above the bottom bar.
    static func list(in size: CGSize) -> CGRect {
        CGRect(x: leftWidth, y: titleHeight, width: max(size.width - leftWidth - rightWidth, 0),
               height: max(size.height - titleHeight - bottomHeight, 0))
    }

    static func visibleRows(in size: CGSize) -> Int {
        max(Int((list(in: size).height / rowHeight).rounded(.down)), 0)
    }

    /// The scroll groove inside the right tile.
    static func scrollTrack(in size: CGSize) -> CGRect {
        CGRect(x: size.width - 15, y: titleHeight, width: 8, height: list(in: size).height)
    }

    static func close(in size: CGSize) -> CGRect { CGRect(x: size.width - 11, y: 3, width: 9, height: 9) }
    static func shade(in size: CGSize) -> CGRect { CGRect(x: size.width - 20, y: 3, width: 9, height: 9) }
    static func resize(in size: CGSize) -> CGRect { CGRect(x: size.width - 20, y: size.height - 20, width: 20, height: 20) }

    /// The 25×18 button that opens each menu.
    static func menuButton(_ kind: WinampPlaylistMenuKind, in size: CGSize) -> CGRect {
        let y = size.height - 28
        return switch kind {
        case .add: CGRect(x: 11, y: y, width: 25, height: 18)
        case .remove: CGRect(x: 40, y: y, width: 25, height: 18)
        case .select: CGRect(x: 69, y: y, width: 25, height: 18)
        case .misc: CGRect(x: 98, y: y, width: 25, height: 18)
        case .list: CGRect(x: size.width - 47, y: y, width: 25, height: 18)
        }
    }

    /// The open menu's strip and items, rising from its button so the last item covers it.
    static func menuBar(_ kind: WinampPlaylistMenuKind, in size: CGSize) -> CGRect {
        let button = menuButton(kind, in: size)
        let height = CGFloat(kind.items.count) * menuItemHeight
        return CGRect(x: button.minX, y: button.maxY - height, width: 3, height: height)
    }

    static func menuItems(_ kind: WinampPlaylistMenuKind, in size: CGSize) -> [CGRect] {
        let bar = menuBar(kind, in: size)
        return kind.items.indices.map { index in
            CGRect(x: bar.maxX, y: bar.minY + CGFloat(index) * menuItemHeight, width: menuItemWidth, height: menuItemHeight)
        }
    }

    /// The item of an open menu under `point`.
    static func menuItem(at point: CGPoint, in kind: WinampPlaylistMenuKind, size: CGSize) -> WinampPlaylistMenuItem? {
        zip(kind.items, menuItems(kind, in: size)).first { $0.1.contains(point) }?.0
    }

    // MARK: Bottom-right corner

    static func bottomRightOrigin(in size: CGSize) -> CGPoint { CGPoint(x: size.width - 150, y: size.height - bottomHeight) }

    /// "selected/total" in text glyphs.
    static func runningTime(in size: CGSize) -> CGPoint {
        let corner = bottomRightOrigin(in: size)
        return CGPoint(x: corner.x + 7, y: corner.y + 10)
    }

    /// The playing song's time in text glyphs.
    static func miniTime(in size: CGSize) -> CGPoint {
        let corner = bottomRightOrigin(in: size)
        return CGPoint(x: corner.x + 66, y: corner.y + 23)
    }

    static func miniButton(_ button: WinampPlaylistMiniButton, in size: CGSize) -> CGRect {
        let corner = bottomRightOrigin(in: size)
        let (x, width): (CGFloat, CGFloat) = switch button {
        case .previous: (3, 7)
        case .play: (10, 8)
        case .pause: (18, 10)
        case .stop: (28, 9)
        case .next: (37, 8)
        case .eject: (45, 9)
        }
        return CGRect(x: corner.x + x, y: corner.y + 22, width: width, height: 8)
    }

    // MARK: Hit testing

    static func control(at point: CGPoint, in size: CGSize) -> WinampPlaylistControl? {
        guard CGRect(origin: .zero, size: size).contains(point) else { return nil }
        if close(in: size).contains(point) { return .close }
        if shade(in: size).contains(point) { return .shade }
        if point.y < titleHeight { return .titleBar }
        if list(in: size).contains(point) { return .list }
        if scrollTrack(in: size).contains(point) { return .scrollBar }
        for kind in WinampPlaylistMenuKind.allCases where menuButton(kind, in: size).contains(point) {
            return .menu(kind)
        }
        for button in WinampPlaylistMiniButton.allCases where miniButton(button, in: size).contains(point) {
            return .mini(button)
        }
        if resize(in: size).contains(point) { return .resize }
        if point.y >= size.height - bottomHeight { return .footer }
        return nil
    }

    // MARK: Windowshade

    static func shadeSize(width: CGFloat) -> CGSize { CGSize(width: width, height: shadeHeight) }
    static func shadeUnshade(width: CGFloat) -> CGRect { CGRect(x: width - 21, y: 3, width: 9, height: 9) }
    static func shadeClose(width: CGFloat) -> CGRect { CGRect(x: width - 11, y: 3, width: 9, height: 9) }
    static func shadeTitle(width: CGFloat) -> CGRect { CGRect(x: 5, y: 4, width: max(width - 76, 0), height: 6) }
    static func shadeTime(width: CGFloat) -> CGPoint { CGPoint(x: width - 66, y: 4) }

    static func shadeControl(at point: CGPoint, width: CGFloat) -> WinampPlaylistControl? {
        guard CGRect(origin: .zero, size: shadeSize(width: width)).contains(point) else { return nil }
        if shadeClose(width: width).contains(point) { return .close }
        if shadeUnshade(width: width).contains(point) { return .shade }
        return .titleBar
    }
}

/// Rows and the scroll position of the track list.
nonisolated enum WinampPlaylistScroll {
    /// The first row that keeps the last row at the bottom.
    static func maximumFirstRow(count: Int, visible: Int) -> Int {
        max(count - max(visible, 1), 0)
    }

    static func clampedFirstRow(_ row: Int, count: Int, visible: Int) -> Int {
        min(max(row, 0), maximumFirstRow(count: count, visible: visible))
    }

    /// The row index under a point, or nil below the last row.
    static func row(at point: CGPoint, firstRow: Int, count: Int, size: CGSize) -> Int? {
        let list = WinampPlaylistLayout.list(in: size)
        guard list.contains(point) else { return nil }
        let row = firstRow + Int(((point.y - list.minY) / WinampPlaylistLayout.rowHeight).rounded(.down))
        return row < count ? row : nil
    }

    /// The row a drag over the list points at, clamped into the list even above or below it.
    static func clampedRow(at y: CGFloat, firstRow: Int, count: Int, size: CGSize) -> Int {
        let list = WinampPlaylistLayout.list(in: size)
        let row = firstRow + Int(((y - list.minY) / WinampPlaylistLayout.rowHeight).rounded(.down))
        return min(max(row, 0), max(count - 1, 0))
    }

    /// Scrolls the least distance that shows `row`.
    static func firstRow(showing row: Int, current: Int, count: Int, visible: Int) -> Int {
        let visible = max(visible, 1)
        var first = current
        if row < first { first = row } else if row >= first + visible { first = row - visible + 1 }
        return clampedFirstRow(first, count: count, visible: visible)
    }

    static let thumbHeight: CGFloat = 18

    /// The thumb's distance from the top of the groove.
    static func thumbOffset(firstRow: Int, count: Int, visible: Int, trackHeight: CGFloat) -> CGFloat {
        let maximum = maximumFirstRow(count: count, visible: visible)
        let travel = max(trackHeight - thumbHeight, 0)
        guard maximum > 0 else { return 0 }
        return (CGFloat(min(max(firstRow, 0), maximum)) / CGFloat(maximum) * travel).rounded()
    }

    /// The first row for a thumb dragged to `offset` from the top of the groove.
    static func firstRow(forThumbOffset offset: CGFloat, count: Int, visible: Int, trackHeight: CGFloat) -> Int {
        let maximum = maximumFirstRow(count: count, visible: visible)
        let travel = max(trackHeight - thumbHeight, 0)
        guard maximum > 0, travel > 0 else { return 0 }
        let fraction = min(max(offset / travel, 0), 1)
        return Int((fraction * CGFloat(maximum)).rounded())
    }
}

/// The playlist window's text: rows, durations and the running time in the footer.
nonisolated enum WinampPlaylistText {
    /// "12. Artist - Title", as Winamp numbers and names entries.
    static func rowTitle(number: Int, artist: String?, title: String) -> String {
        let artist = artist?.trimmingCharacters(in: .whitespaces) ?? ""
        return artist.isEmpty ? "\(number). \(title)" : "\(number). \(artist) - \(title)"
    }

    /// "3:45", or empty for an unknown length.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        return WinampMarquee.clock(Int(seconds.rounded()))
    }

    /// Winamp's "selected/total", such as "7:30/1:02:03". A "+" follows a sum that leaves out
    /// songs of unknown length.
    static func runningTime(selected: [TimeInterval], total: [TimeInterval]) -> String {
        "\(sum(selected))/\(sum(total))"
    }

    private static func sum(_ durations: [TimeInterval]) -> String {
        var seconds = 0
        var hasUnknown = false
        for duration in durations {
            if duration.isFinite, duration > 0 {
                seconds += Int(duration.rounded())
            } else {
                hasUnknown = true
            }
        }
        return WinampMarquee.clock(seconds) + (hasUnknown ? "+" : "")
    }

    /// The playing song's time for the corner display: "2:05", or "-1:40" counting down.
    static func miniTime(position: TimeInterval, duration: TimeInterval, mode: WinampTimeMode) -> String {
        let display = WinampTimeDisplay.make(position: position, duration: duration, mode: mode)
        return (display.isNegative ? "-" : "") + "\(display.minutes):" + String(format: "%02d", display.seconds)
    }
}

/// Which rows are selected, with Winamp's click, shift-click and command-click behaviour and
/// keyboard focus.
nonisolated struct WinampPlaylistSelection: Sendable, Hashable {
    private(set) var rows: Set<Int> = []
    /// The row the keyboard moves from.
    private(set) var focus: Int?
    /// Where a shift-click range starts.
    private(set) var anchor: Int?

    init(rows: Set<Int> = [], focus: Int? = nil) {
        self.rows = rows
        self.focus = focus
        anchor = focus
    }

    func contains(_ row: Int) -> Bool { rows.contains(row) }

    /// A plain click selects one row; shift extends from the anchor; command toggles one row.
    mutating func click(_ row: Int, extending: Bool = false, toggling: Bool = false) {
        if extending, let anchor {
            rows = Set(min(anchor, row)...max(anchor, row))
        } else if toggling {
            if rows.contains(row) { rows.remove(row) } else { rows.insert(row) }
            anchor = row
        } else {
            rows = [row]
            anchor = row
        }
        focus = row
    }

    mutating func selectAll(count: Int) {
        rows = count > 0 ? Set(0..<count) : []
    }

    mutating func selectNone() {
        rows = []
    }

    mutating func invert(count: Int) {
        rows = Set(0..<max(count, 0)).subtracting(rows)
    }

    /// Moves the focus by `delta` rows, selecting it alone or, extending, from the anchor.
    mutating func moveFocus(by delta: Int, count: Int, extending: Bool = false) {
        guard count > 0 else { return }
        let start = focus ?? (delta >= 0 ? -1 : count)
        let row = min(max(start + delta, 0), count - 1)
        if extending, anchor != nil {
            click(row, extending: true)
        } else {
            click(row)
        }
    }

    /// Replaces the rows, as after a reorder, keeping the focus on the moved block.
    mutating func set(_ rows: Set<Int>, focus: Int?) {
        self.rows = rows
        self.focus = focus
        anchor = focus
    }

    /// Drops rows past the end of a shorter list.
    mutating func clamp(count: Int) {
        rows = rows.filter { $0 >= 0 && $0 < count }
        if let focus, focus >= count { self.focus = count > 0 ? count - 1 : nil }
        if let anchor, anchor >= count { self.anchor = self.focus }
    }
}

/// Reordering plans for the play queue. The player can't move the playing song, so every plan
/// is made of moves of other songs: a move takes the song at `from` and inserts it before the
/// song at `toOffset`, counted before the removal, as `Array.move(fromOffsets:toOffset:)` does.
nonisolated enum WinampQueueReorder {
    struct Move: Sendable, Hashable {
        let from: Int
        let toOffset: Int
    }

    /// The order after moving the selected rows `delta` rows up (negative) or down, as a list of
    /// the current indices. A block stops at the top or bottom, as in Winamp.
    static func shifted(count: Int, selected: Set<Int>, by delta: Int) -> (order: [Int], selection: Set<Int>) {
        var order = Array(0..<max(count, 0))
        var chosen = Set(order.indices.filter { selected.contains($0) })
        let step = delta > 0 ? 1 : -1
        for _ in 0..<abs(delta) {
            // From the leading edge, so a row moves into the place the row ahead of it just left.
            for position in chosen.sorted(by: step > 0 ? (>) : (<)) {
                let target = position + step
                guard order.indices.contains(target), !chosen.contains(target) else { continue }
                order.swapAt(position, target)
                chosen.remove(position)
                chosen.insert(target)
            }
        }
        return (order, chosen)
    }

    /// Moves that rearrange the queue into `order` (a permutation of the current indices) without
    /// ever moving `currentIndex`, the playing song. Nil when `order` isn't a permutation.
    static func moves(toward order: [Int], currentIndex: Int?) -> [Move]? {
        guard Set(order) == Set(0..<order.count) else { return nil }
        var items = Array(0..<order.count)
        var moves: [Move] = []
        for position in order.indices {
            let wanted = order[position]
            guard var index = items.firstIndex(of: wanted), index != position else { continue }
            if wanted != currentIndex {
                moves.append(Move(from: index, toOffset: position))
                items.remove(at: index)
                items.insert(wanted, at: position)
                continue
            }
            // The playing song can't move: carry the songs in front of it past it, one at a time.
            while index > position {
                let move = Move(from: position, toOffset: index + 1)
                moves.append(move)
                apply(move, to: &items)
                index -= 1
            }
        }
        return moves
    }

    static func apply<Element>(_ move: Move, to array: inout [Element]) {
        guard array.indices.contains(move.from), (0...array.count).contains(move.toOffset) else { return }
        let element = array.remove(at: move.from)
        array.insert(element, at: move.from < move.toOffset ? move.toOffset - 1 : move.toOffset)
    }

    /// Sort keys for the Misc menu's Sort List.
    enum SortKey: Sendable, CaseIterable {
        case title
        case artist
        case album
        case reverse
        case shuffle
    }

    /// The new order for a sort of `songs`. Equal keys keep their order.
    static func sortedOrder(_ songs: [DisplayableSong], by key: SortKey,
                            using generator: inout some RandomNumberGenerator) -> [Int] {
        let indices = Array(songs.indices)
        func compare(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
            (lhs ?? "").compare(rhs ?? "", options: [.caseInsensitive, .numeric], locale: .current)
        }
        func albumOrder(_ lhs: Int, _ rhs: Int) -> Bool {
            let a = songs[lhs], b = songs[rhs]
            let album = compare(a.albumName, b.albumName)
            if album != .orderedSame { return album == .orderedAscending }
            if (a.discNumber ?? 0) != (b.discNumber ?? 0) { return (a.discNumber ?? 0) < (b.discNumber ?? 0) }
            if (a.trackNumber ?? 0) != (b.trackNumber ?? 0) { return (a.trackNumber ?? 0) < (b.trackNumber ?? 0) }
            return lhs < rhs
        }
        switch key {
        case .title:
            return indices.sorted { lhs, rhs in
                let result = compare(songs[lhs].title, songs[rhs].title)
                return result == .orderedSame ? lhs < rhs : result == .orderedAscending
            }
        case .artist:
            return indices.sorted { lhs, rhs in
                let result = compare(songs[lhs].artist, songs[rhs].artist)
                return result == .orderedSame ? albumOrder(lhs, rhs) : result == .orderedAscending
            }
        case .album:
            return indices.sorted(by: albumOrder)
        case .reverse:
            return indices.reversed()
        case .shuffle:
            return indices.shuffled(using: &generator)
        }
    }

    /// Later copies of a song already in the list, except the playing one.
    static func duplicateIndices(_ songIDs: [String], currentIndex: Int?) -> [Int] {
        var seen: Set<String> = []
        var duplicates: [Int] = []
        for (index, id) in songIDs.enumerated() {
            if seen.contains(id), index != currentIndex {
                duplicates.append(index)
            } else {
                seen.insert(id)
            }
        }
        return duplicates
    }
}
