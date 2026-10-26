import CoreGraphics
import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

private func queueSong(_ id: String, title: String? = nil, artist: String? = "Artist", album: String? = "Album",
                       duration: TimeInterval = 180, track: Int? = nil, suffix: String? = "flac") -> DisplayableSong {
    DisplayableSong(from: Song(id: id, title: title ?? "Song \(id)", album: album, artist: artist, track: track,
                               suffix: suffix, duration: Int(duration)))
}

// MARK: - Playlist window layout

@Suite("Winamp playlist layout")
struct WinampPlaylistLayoutTests {
    @Test func sizeGrowsInWinampSteps() {
        #expect(WinampPlaylistSize.standard.pixelSize == CGSize(width: 275, height: 232))
        #expect(WinampPlaylistSize(widthSteps: 2, heightSteps: 1).pixelSize == CGSize(width: 325, height: 145))
        #expect(WinampPlaylistSize(widthSteps: -3, heightSteps: 999).heightSteps == WinampPlaylistSize.maximumSteps)
        #expect(WinampPlaylistSize(widthSteps: -3, heightSteps: 0).widthSteps == 0)
    }

    @Test func resizeDragSnapsToTheNearestStep() {
        #expect(WinampPlaylistSize.fitting(CGSize(width: 287, height: 130)) == WinampPlaylistSize(widthSteps: 0, heightSteps: 0))
        #expect(WinampPlaylistSize.fitting(CGSize(width: 288, height: 131)) == WinampPlaylistSize(widthSteps: 1, heightSteps: 1))
        #expect(WinampPlaylistSize.fitting(CGSize(width: 100, height: 20)) == WinampPlaylistSize(widthSteps: 0, heightSteps: 0))
        #expect(WinampPlaylistSize.fitting(CGSize(width: CGFloat.nan, height: CGFloat.infinity)) == WinampPlaylistSize(widthSteps: 0, heightSteps: 0))
    }

    @Test func listSitsBetweenTheFrameAndShowsWholeRows() {
        let size = WinampPlaylistSize.standard.pixelSize
        #expect(WinampPlaylistLayout.list(in: size) == CGRect(x: 12, y: 20, width: 243, height: 174))
        #expect(WinampPlaylistLayout.visibleRows(in: size) == 13)
        #expect(WinampPlaylistLayout.visibleRows(in: WinampPlaylistSize.minimum) == 4)
        #expect(WinampPlaylistLayout.scrollTrack(in: size) == CGRect(x: 260, y: 20, width: 8, height: 174))
    }

    @Test func hitTestingFindsEveryPart() {
        let size = WinampPlaylistSize(widthSteps: 2, heightSteps: 4).pixelSize   // 325×232
        typealias Layout = WinampPlaylistLayout
        #expect(Layout.control(at: CGPoint(x: 318, y: 6), in: size) == .close)
        #expect(Layout.control(at: CGPoint(x: 308, y: 6), in: size) == .shade)
        #expect(Layout.control(at: CGPoint(x: 150, y: 8), in: size) == .titleBar)
        #expect(Layout.control(at: CGPoint(x: 40, y: 60), in: size) == .list)
        #expect(Layout.control(at: CGPoint(x: 313, y: 60), in: size) == .scrollBar)
        #expect(Layout.control(at: CGPoint(x: 15, y: 210), in: size) == .menu(.add))
        #expect(Layout.control(at: CGPoint(x: 50, y: 210), in: size) == .menu(.remove))
        #expect(Layout.control(at: CGPoint(x: 80, y: 210), in: size) == .menu(.select))
        #expect(Layout.control(at: CGPoint(x: 110, y: 210), in: size) == .menu(.misc))
        #expect(Layout.control(at: CGPoint(x: 280, y: 210), in: size) == .menu(.list))
        #expect(Layout.control(at: CGPoint(x: 178, y: 220), in: size) == .mini(.previous))
        #expect(Layout.control(at: CGPoint(x: 220, y: 220), in: size) == .mini(.eject))
        #expect(Layout.control(at: CGPoint(x: 320, y: 228), in: size) == .resize)
        #expect(Layout.control(at: CGPoint(x: 200, y: 200), in: size) == .footer)
        #expect(Layout.control(at: CGPoint(x: 400, y: 10), in: size) == nil)
    }

    @Test func menusRiseFromTheirButtons() {
        let size = WinampPlaylistSize.standard.pixelSize
        let button = WinampPlaylistLayout.menuButton(.remove, in: size)
        let items = WinampPlaylistLayout.menuItems(.remove, in: size)
        #expect(items.count == 4)
        #expect(items.last?.maxY == button.maxY)
        #expect(items.first?.minY == button.maxY - 72)
        #expect(WinampPlaylistLayout.menuBar(.remove, in: size).minX == button.minX)
        #expect(WinampPlaylistLayout.menuItem(at: CGPoint(x: items[1].midX, y: items[1].midY), in: .remove, size: size) == .crop)
        #expect(WinampPlaylistLayout.menuItem(at: CGPoint(x: 200, y: 10), in: .remove, size: size) == nil)
        #expect(WinampPlaylistMenuKind.add.items == [.addURL, .addFolder, .addFile])
        #expect(WinampPlaylistMenuKind.list.items == [.newList, .saveList, .loadList])
    }
}

// MARK: - Scrolling

@Suite("Winamp playlist scrolling")
struct WinampPlaylistScrollTests {
    private let size = WinampPlaylistSize.standard.pixelSize

    @Test func rowsUnderThePointerCountFromTheFirstVisibleRow() {
        #expect(WinampPlaylistScroll.row(at: CGPoint(x: 30, y: 21), firstRow: 0, count: 50, size: size) == 0)
        #expect(WinampPlaylistScroll.row(at: CGPoint(x: 30, y: 32), firstRow: 0, count: 50, size: size) == 0)
        #expect(WinampPlaylistScroll.row(at: CGPoint(x: 30, y: 34), firstRow: 10, count: 50, size: size) == 11)
        #expect(WinampPlaylistScroll.row(at: CGPoint(x: 30, y: 60), firstRow: 0, count: 2, size: size) == nil)
        #expect(WinampPlaylistScroll.row(at: CGPoint(x: 300, y: 60), firstRow: 0, count: 50, size: size) == nil)
        #expect(WinampPlaylistScroll.clampedRow(at: -50, firstRow: 3, count: 50, size: size) == 0)
        #expect(WinampPlaylistScroll.clampedRow(at: 9_999, firstRow: 3, count: 50, size: size) == 49)
    }

    @Test func firstRowStaysInRange() {
        #expect(WinampPlaylistScroll.maximumFirstRow(count: 50, visible: 13) == 37)
        #expect(WinampPlaylistScroll.maximumFirstRow(count: 5, visible: 13) == 0)
        #expect(WinampPlaylistScroll.clampedFirstRow(-4, count: 50, visible: 13) == 0)
        #expect(WinampPlaylistScroll.clampedFirstRow(90, count: 50, visible: 13) == 37)
    }

    @Test func keepingARowVisibleScrollsTheLeastDistance() {
        #expect(WinampPlaylistScroll.firstRow(showing: 5, current: 0, count: 50, visible: 13) == 0)
        #expect(WinampPlaylistScroll.firstRow(showing: 13, current: 0, count: 50, visible: 13) == 1)
        #expect(WinampPlaylistScroll.firstRow(showing: 2, current: 10, count: 50, visible: 13) == 2)
        #expect(WinampPlaylistScroll.firstRow(showing: 49, current: 0, count: 50, visible: 13) == 37)
    }

    @Test func thumbAndFirstRowConvertBothWays() {
        let track: CGFloat = 174
        #expect(WinampPlaylistScroll.thumbOffset(firstRow: 0, count: 50, visible: 13, trackHeight: track) == 0)
        #expect(WinampPlaylistScroll.thumbOffset(firstRow: 37, count: 50, visible: 13, trackHeight: track) == 156)
        #expect(WinampPlaylistScroll.thumbOffset(firstRow: 0, count: 5, visible: 13, trackHeight: track) == 0)
        for row in 0...37 {
            let offset = WinampPlaylistScroll.thumbOffset(firstRow: row, count: 50, visible: 13, trackHeight: track)
            #expect(WinampPlaylistScroll.firstRow(forThumbOffset: offset, count: 50, visible: 13, trackHeight: track) == row)
        }
        #expect(WinampPlaylistScroll.firstRow(forThumbOffset: 900, count: 50, visible: 13, trackHeight: track) == 37)
    }
}

// MARK: - Text and footer time

@Suite("Winamp playlist text")
struct WinampPlaylistTextTests {
    @Test func rowsAreNumberedWithArtistAndTitle() {
        #expect(WinampPlaylistText.rowTitle(number: 3, artist: "Björk", title: "Jóga") == "3. Björk - Jóga")
        #expect(WinampPlaylistText.rowTitle(number: 12, artist: " ", title: "Untitled") == "12. Untitled")
        #expect(WinampPlaylistText.rowTitle(number: 1, artist: nil, title: "Intro") == "1. Intro")
    }

    @Test func durationsUseMinutesAndHours() {
        #expect(WinampPlaylistText.duration(225) == "3:45")
        #expect(WinampPlaylistText.duration(3_725) == "1:02:05")
        #expect(WinampPlaylistText.duration(0) == "")
        #expect(WinampPlaylistText.duration(.nan) == "")
    }

    @Test func footerAddsSelectedAndTotalTimes() {
        let all: [TimeInterval] = [180, 240, 300.4, 3_600]
        #expect(WinampPlaylistText.runningTime(selected: [180, 240], total: all) == "7:00/1:12:00")
        #expect(WinampPlaylistText.runningTime(selected: [], total: []) == "0:00/0:00")
        #expect(WinampPlaylistText.runningTime(selected: [], total: [59.6]) == "0:00/1:00")
    }

    @Test func unknownLengthsAddAPlus() {
        #expect(WinampPlaylistText.runningTime(selected: [0], total: [120, 0, .infinity]) == "0:00+/2:00+")
    }

    @Test func miniTimeFollowsTheTimeMode() {
        #expect(WinampPlaylistText.miniTime(position: 65, duration: 200, mode: .elapsed) == "1:05")
        #expect(WinampPlaylistText.miniTime(position: 65, duration: 200, mode: .remaining) == "-2:15")
    }
}

// MARK: - Selection

@Suite("Winamp playlist selection")
struct WinampPlaylistSelectionTests {
    @Test func clicksSelectExtendAndToggle() {
        var selection = WinampPlaylistSelection()
        selection.click(4)
        #expect(selection.rows == [4])
        selection.click(7, extending: true)
        #expect(selection.rows == [4, 5, 6, 7])
        selection.click(2, extending: true)
        #expect(selection.rows == [2, 3, 4])
        selection.click(9, toggling: true)
        #expect(selection.rows == [2, 3, 4, 9])
        selection.click(3, toggling: true)
        #expect(selection.rows == [2, 4, 9])
        #expect(selection.focus == 3)
    }

    @Test func keyboardMovesTheFocusWithinTheList() {
        var selection = WinampPlaylistSelection()
        selection.moveFocus(by: 1, count: 5)
        #expect(selection.rows == [0])
        selection.moveFocus(by: 10, count: 5)
        #expect(selection.rows == [4])
        selection.moveFocus(by: -2, count: 5, extending: true)
        #expect(selection.rows == [2, 3, 4])
        selection.moveFocus(by: -9, count: 5)
        #expect(selection.rows == [0])
    }

    @Test func selectMenuActions() {
        var selection = WinampPlaylistSelection(rows: [1, 3], focus: 3)
        selection.invert(count: 5)
        #expect(selection.rows == [0, 2, 4])
        selection.selectAll(count: 3)
        #expect(selection.rows == [0, 1, 2])
        selection.selectNone()
        #expect(selection.rows.isEmpty)
    }

    @Test func shorterListsDropRowsPastTheEnd() {
        var selection = WinampPlaylistSelection(rows: [1, 6, 8], focus: 8)
        selection.clamp(count: 7)
        #expect(selection.rows == [1, 6])
        #expect(selection.focus == 6)
    }
}

// MARK: - Reordering

@Suite("Winamp queue reordering")
struct WinampQueueReorderTests {
    @Test func selectedRowsMoveTogetherAndStopAtTheEnds() {
        let down = WinampQueueReorder.shifted(count: 6, selected: [1, 2], by: 2)
        #expect(down.order == [0, 3, 4, 1, 2, 5])
        #expect(down.selection == [3, 4])
        let blocked = WinampQueueReorder.shifted(count: 6, selected: [4, 5], by: 3)
        #expect(blocked.order == [0, 1, 2, 3, 4, 5])
        #expect(blocked.selection == [4, 5])
        let up = WinampQueueReorder.shifted(count: 6, selected: [0, 3], by: -2)
        #expect(up.order == [0, 3, 1, 2, 4, 5])
        #expect(up.selection == [0, 1])
    }

    @Test func movesReachTheTargetWithoutMovingThePlayingSong() throws {
        var generator = SystemRandomNumberGenerator()
        for count in [1, 2, 3, 6, 12] {
            for _ in 0..<40 {
                let target = Array(0..<count).shuffled(using: &generator)
                let current = Int.random(in: 0..<count, using: &generator)
                let moves = try #require(WinampQueueReorder.moves(toward: target, currentIndex: current))
                var queue = Array(0..<count)
                for move in moves {
                    #expect(queue[move.from] != current)
                    // QueueEditing refuses moves that leave the song where it is.
                    #expect(move.toOffset != move.from && move.toOffset != move.from + 1)
                    WinampQueueReorder.apply(move, to: &queue)
                }
                #expect(queue == target)
            }
        }
    }

    @Test func aShiftPlansFewMoves() throws {
        let shift = WinampQueueReorder.shifted(count: 10, selected: [5], by: -3)
        let moves = try #require(WinampQueueReorder.moves(toward: shift.order, currentIndex: 0))
        #expect(moves == [WinampQueueReorder.Move(from: 5, toOffset: 2)])
        #expect(WinampQueueReorder.moves(toward: [0, 0, 1], currentIndex: nil) == nil)
    }

    @Test func sortsKeepTiesInOrder() {
        let songs = [queueSong("a", title: "Beta", artist: "Zed", album: "Two", track: 2),
                     queueSong("b", title: "alpha", artist: "Amy", album: "One", track: 1),
                     queueSong("c", title: "Gamma", artist: "Amy", album: "One", track: 3),
                     queueSong("d", title: "beta", artist: "Zed", album: "Two", track: 1)]
        var generator = SystemRandomNumberGenerator()
        #expect(WinampQueueReorder.sortedOrder(songs, by: .title, using: &generator) == [1, 0, 3, 2])
        #expect(WinampQueueReorder.sortedOrder(songs, by: .artist, using: &generator) == [1, 2, 3, 0])
        #expect(WinampQueueReorder.sortedOrder(songs, by: .album, using: &generator) == [1, 2, 3, 0])
        #expect(WinampQueueReorder.sortedOrder(songs, by: .reverse, using: &generator) == [3, 2, 1, 0])
        #expect(Set(WinampQueueReorder.sortedOrder(songs, by: .shuffle, using: &generator)) == [0, 1, 2, 3])
    }

    @Test func duplicatesAreLaterCopiesButNeverThePlayingOne() {
        #expect(WinampQueueReorder.duplicateIndices(["a", "b", "a", "c", "b"], currentIndex: nil) == [2, 4])
        #expect(WinampQueueReorder.duplicateIndices(["a", "b", "a"], currentIndex: 2) == [])
    }
}
