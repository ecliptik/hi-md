import CoreGraphics
import Foundation
import Testing
@testable import Minidisc

@Suite("Mac MiniPlayer as a bar")
struct MiniPlayerPresentationBarTests {
    private let big = CGSize(width: 1600, height: 1000)

    // MARK: Size

    @Test func theBarIsAShortStripThatOnlyChangesItsWidth() {
        let bar = MiniPlayerLayout.bar
        #expect(bar.minimumSize == CGSize(width: MiniPlayerLayout.barMinimumWidth, height: MiniPlayerLayout.barHeight))
        #expect(bar.maximumSize == CGSize(width: MiniPlayerLayout.barMaximumWidth, height: MiniPlayerLayout.barHeight))
        // Fixed height: the least and most agree.
        #expect(bar.minimumSize.height == bar.maximumSize.height)
        #expect((72...84).contains(MiniPlayerLayout.barHeight))
        #expect((360...400).contains(MiniPlayerLayout.barMinimumWidth))
        #expect(MiniPlayerLayout.barMaximumWidth == 900)
        // No aspect ratio, no artwork stage, no pane.
        #expect(!bar.keepsSquare)
        #expect(MiniPlayerLayout.compact.keepsSquare)
        #expect(bar.artworkSide(in: CGSize(width: 560, height: 76)) == 0)
        #expect(bar.paneSize(in: CGSize(width: 560, height: 76)) == .zero)
        // Widths are kept within the limits, always at the bar's height.
        #expect(MiniPlayerLayout.barSize(width: 100) == CGSize(width: 380, height: 76))
        #expect(MiniPlayerLayout.barSize(width: 2000) == CGSize(width: 900, height: 76))
        #expect(MiniPlayerLayout.barSize(width: 612.4) == CGSize(width: 612, height: 76))
    }

    @Test func theBarIsChosenNotReachedByResizing() {
        // As a bar, whatever the size or pane state.
        #expect(MiniPlayerLayout.layout(for: CGSize(width: 560, height: 76), isPaneOpen: false, isBar: true) == .bar)
        #expect(MiniPlayerLayout.layout(for: CGSize(width: 320, height: 660), isPaneOpen: true, isBar: true) == .bar)
        // A short wide window that isn't a bar is still compact.
        #expect(MiniPlayerLayout.layout(for: CGSize(width: 560, height: 76), isPaneOpen: false) == .compact)
    }

    // MARK: In and out

    @Test func leavingTheBarGoesBackToTheCompactSizeBefore() {
        var sizing = MiniPlayerWindowSizing()
        var panel = MiniPlayerPanelState(pane: .upNext, isOpen: false)
        let compact = CGSize(width: 347, height: 347)
        let bar = sizing.sizeEnteringBar(from: compact, panel: &panel, barWidth: nil)
        #expect(bar == CGSize(width: MiniPlayerLayout.barDefaultWidth, height: MiniPlayerLayout.barHeight))
        #expect(sizing.compactSizeBeforeBar == compact)
        // Back to exactly that square, and forgotten after.
        #expect(sizing.sizeLeavingBar(compactSide: 500) == compact)
        #expect(sizing.compactSizeBeforeBar == nil)
        // The bar comes back at its last width.
        #expect(sizing.sizeEnteringBar(from: compact, panel: &panel, barWidth: 700) == CGSize(width: 700, height: 76))
    }

    @Test func aBarRestoredAtLaunchExpandsToTheLastCompactSide() {
        var sizing = MiniPlayerWindowSizing()
        #expect(sizing.sizeLeavingBar(compactSide: 400) == CGSize(width: 400, height: 400))
        #expect(sizing.sizeLeavingBar(compactSide: nil)
                == CGSize(width: MiniPlayerLayout.defaultSide, height: MiniPlayerLayout.defaultSide))
        // Kept within the compact limits.
        #expect(sizing.sizeLeavingBar(compactSide: 2000) == CGSize(width: 720, height: 720))
    }

    @Test func theBarClosesAnyPaneAndOpeningOneGoesToTheTallLayout() {
        var sizing = MiniPlayerWindowSizing()
        var panel = MiniPlayerPanelState(pane: .upNext, isOpen: false)
        let compact = CGSize(width: 347, height: 347)
        // A pane opened from compact, then Show as Bar.
        _ = panel.toggle(.upNext, canShowLyrics: true)
        let opened = sizing.sizeOpeningPane(from: compact, available: big)
        _ = sizing.sizeEnteringBar(from: CGSize(width: 500, height: 900), panel: &panel, barWidth: nil)
        #expect(!panel.isOpen)
        #expect(panel.pane == .upNext)
        // The square to come back to is the one before the pane, not the resized tall window.
        #expect(sizing.compactSizeBeforeBar == compact)
        #expect(opened.height > compact.height)
        // Opening a pane from the bar: the compact square with the pane under it.
        var next = panel
        #expect(next.show(.lyrics, canShowLyrics: true) == .open)
        let target = sizing.sizeOpeningPaneFromBar(compactSide: nil, available: big)
        #expect(target == CGSize(width: 347, height: 347 + MiniPlayerLayout.paneHeight))
        #expect(MiniPlayerLayout.layout(for: target, isPaneOpen: next.isOpen) == .tall)
        #expect(sizing.compactSizeBeforeBar == nil)
        // Closing that pane goes back to the square, not the bar.
        #expect(sizing.sizeClosingPane(from: target) == compact)
    }

    @Test func openingAPaneFromABarRestoredAtLaunchUsesTheLastSide() {
        var sizing = MiniPlayerWindowSizing()
        let target = sizing.sizeOpeningPaneFromBar(compactSide: 300, available: big)
        #expect(target == CGSize(width: 300, height: 300 + MiniPlayerLayout.paneHeight))
        // No room below the bar: beside the artwork.
        var low = MiniPlayerWindowSizing()
        let wide = low.sizeOpeningPaneFromBar(compactSide: 300, available: CGSize(width: 1600, height: 400))
        #expect(MiniPlayerLayout.layout(for: wide, isPaneOpen: true) == .wide)
    }

    // MARK: Restoring

    @Test func aRestoredBarWindowFitsTheBar() {
        // Already a bar: its width is kept, within the limits.
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 600, height: 76), isPaneOpen: false, isBar: true)
                == CGSize(width: 600, height: 76))
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 1200, height: 76.5), isPaneOpen: false, isBar: true)
                == CGSize(width: 900, height: 76))
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 300, height: 76), isPaneOpen: false, isBar: true)
                == CGSize(width: 380, height: 76))
        // A square (made a bar while closed, or by an older version): the bar's last width.
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 320, height: 320), isPaneOpen: false, isBar: true, barWidth: 640)
                == CGSize(width: 640, height: 76))
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 320, height: 660), isPaneOpen: true, isBar: true)
                == CGSize(width: MiniPlayerLayout.barDefaultWidth, height: 76))
        // Not a bar any more: a bar-shaped window becomes the smallest square.
        #expect(MiniPlayerLayout.reconciled(CGSize(width: 600, height: 76), isPaneOpen: false)
                == CGSize(width: 260, height: 260))
    }

    // MARK: Limits

    @Test func theWindowsLeastSizeFollowsTheLayoutAndMakesRoomMidAnimation() {
        // Settled: each layout's own minimum, the same for the root view and the window (with a
        // pane beside the artwork that's the wide layout's, not the tall one's).
        for layout in MiniPlayerLayout.allCases {
            #expect(MiniPlayerLayoutChange.minimumSize(settledIn: layout, during: nil) == layout.minimumSize)
        }
        #expect(MiniPlayerLayoutChange.minimumSize(settledIn: .wide, during: nil) == CGSize(width: 540, height: 260))
        // To and from the bar: room for a square as narrow as the compact one and as short as the bar.
        let toBar = MiniPlayerLayoutChange(from: .compact, to: .bar)
        #expect(toBar.minimumSize == CGSize(width: 260, height: 76))
        #expect(toBar.maximumSize == CGSize(width: 900, height: 720))
        #expect(MiniPlayerLayoutChange(from: .bar, to: .tall).minimumSize == CGSize(width: 260, height: 76))
        #expect(MiniPlayerLayoutChange.minimumSize(settledIn: .bar, during: toBar) == toBar.minimumSize)
        // Opening a pane: the compact minimum until the window is tall.
        #expect(MiniPlayerLayoutChange(from: .compact, to: .tall).minimumSize == CGSize(width: 260, height: 260))
        // Every target size fits inside the limits on its way.
        let change = MiniPlayerLayoutChange(from: .tall, to: .bar)
        for size in [CGSize(width: 320, height: 660), CGSize(width: 560, height: 76)] {
            #expect(size.width >= change.minimumSize.width && size.height >= change.minimumSize.height)
            #expect(size.width <= change.maximumSize.width && size.height <= change.maximumSize.height)
        }
    }

    // MARK: Narrowing

    @Test func asTheBarNarrowsTheMenuGoesThenTheHeartThenTheTimes() {
        let all = MiniPlayerBarItems(width: MiniPlayerLayout.barMaximumWidth)
        #expect(all.showsMenu && all.showsHeart && all.showsTimes)
        // The first bar has room for everything.
        let first = MiniPlayerBarItems(width: MiniPlayerLayout.barDefaultWidth)
        #expect(first.showsMenu && first.showsHeart && first.showsTimes)

        let noMenu = MiniPlayerBarItems(width: MiniPlayerBarItems.menuWidth - 1)
        #expect(!noMenu.showsMenu && noMenu.showsHeart && noMenu.showsTimes)
        let noHeart = MiniPlayerBarItems(width: MiniPlayerBarItems.heartWidth - 1)
        #expect(!noHeart.showsMenu && !noHeart.showsHeart && noHeart.showsTimes)
        let bare = MiniPlayerBarItems(width: MiniPlayerBarItems.timesWidth - 1)
        #expect(!bare.showsMenu && !bare.showsHeart && !bare.showsTimes)
        #expect(MiniPlayerBarItems(width: MiniPlayerLayout.barMinimumWidth) == bare)

        // In that order, all within the bar's widths.
        #expect(MiniPlayerLayout.barMinimumWidth < MiniPlayerBarItems.timesWidth)
        #expect(MiniPlayerBarItems.timesWidth < MiniPlayerBarItems.heartWidth)
        #expect(MiniPlayerBarItems.heartWidth < MiniPlayerBarItems.menuWidth)
        #expect(MiniPlayerBarItems.menuWidth <= MiniPlayerLayout.barDefaultWidth)
        // Never a heart without the times, nor a menu without the heart.
        for width in stride(from: MiniPlayerLayout.barMinimumWidth, through: MiniPlayerLayout.barMaximumWidth, by: 5) {
            let items = MiniPlayerBarItems(width: width)
            #expect(!items.showsHeart || items.showsTimes)
            #expect(!items.showsMenu || items.showsHeart)
        }
    }
}
