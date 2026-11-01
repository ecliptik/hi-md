import CoreGraphics
import Testing
@testable import Minidisc

@Suite("Winamp zoom that fits the screen")
struct WinampFittingZoomTests {
    // The main window with the playlist docked under it, at 1×: 275 wide, 116 + 400 tall.
    private let stack = CGSize(width: 275, height: 516)

    @Test func aLargeMonitorKeepsTheChosenZoom() {
        #expect(WinampDocking.fittingZoom(unitSize: stack, in: CGRect(x: 0, y: 0, width: 3008, height: 1660), preferred: 2) == 2)
    }

    @Test func aLaptopDisplayStepsDownUntilItFits() {
        // A 15-inch MacBook Pro's default 1440×900, less the menu bar.
        #expect(WinampDocking.fittingZoom(unitSize: stack, in: CGRect(x: 0, y: 0, width: 1440, height: 875), preferred: 2) == 1)
        #expect(WinampDocking.fittingZoom(unitSize: stack, in: CGRect(x: 0, y: 0, width: 1440, height: 1100), preferred: 3) == 2)
    }

    @Test func nothingGoesBelowOne() {
        #expect(WinampDocking.fittingZoom(unitSize: CGSize(width: 2000, height: 2000), in: CGRect(x: 0, y: 0, width: 800, height: 600), preferred: 4) == 1)
        #expect(WinampDocking.fittingZoom(unitSize: stack, in: CGRect(x: 0, y: 0, width: 800, height: 600), preferred: 1) == 1)
    }
}
