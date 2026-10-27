import CoreGraphics
import Testing
@testable import Minidisc

@Suite("Spinning disc click on the Mac player's artwork")
struct ArtworkDiscToggleTests {
    /// A 320-point MiniPlayer: the traffic lights and capsule across the top 44 points, the song,
    /// scrubber and transport over the bottom 120, and the scrim fading in 56 points above them.
    private let miniPlayer = ArtworkDiscHitArea(
        size: CGSize(width: 320, height: 320),
        controls: [CGRect(x: 0, y: 0, width: 320, height: 44), CGRect(x: 0, y: 200, width: 320, height: 120)],
        covered: [CGRect(x: 0, y: 144, width: 320, height: 176)]
    )

    // MARK: Where

    @Test func onlyACircleInTheMiddleTakesTheClick() {
        let area = ArtworkDiscHitArea(size: CGSize(width: 400, height: 400))
        #expect(area.diameter == 400 * ArtworkDiscHitArea.fraction)
        #expect(area.contains(CGPoint(x: 200, y: 200)))
        // Just inside and just outside the circle's edge, straight up from the middle.
        #expect(area.contains(CGPoint(x: 200, y: 200 - area.diameter / 2 + 1)))
        #expect(!area.contains(CGPoint(x: 200, y: 200 - area.diameter / 2 - 1)))
        // The corners of its square are outside the circle, and the artwork's edges far outside.
        #expect(!area.contains(CGPoint(x: area.circle.minX + 2, y: area.circle.minY + 2)))
        #expect(!area.contains(CGPoint(x: 10, y: 200)))
        #expect(!area.contains(CGPoint(x: 200, y: 395)))
    }

    @Test func theCircleFollowsTheShorterSideAndStaysCentred() {
        let area = ArtworkDiscHitArea(size: CGSize(width: 600, height: 300))
        #expect(area.diameter == 300 * ArtworkDiscHitArea.fraction)
        #expect(area.circle.midX == 300 && area.circle.midY == 150)
        #expect(!ArtworkDiscHitArea(size: .zero).contains(.zero))
    }

    @Test func clicksNearTheControlsDontCount() {
        // The middle of the artwork, between the top band and the scrim, takes it.
        #expect(miniPlayer.contains(CGPoint(x: 160, y: 100)))
        // On the scrim above the controls, and on the controls themselves.
        #expect(!miniPlayer.contains(CGPoint(x: 160, y: 150)))
        #expect(!miniPlayer.contains(CGPoint(x: 160, y: 250)))
        // The smallest MiniPlayer: its circle reaches up to the top band, and stops 12 points short.
        let smallest = ArtworkDiscHitArea(size: CGSize(width: 260, height: 260),
                                          controls: [CGRect(x: 0, y: 0, width: 260, height: 44)])
        #expect(smallest.circle.minY < 44 + ArtworkDiscHitArea.controlClearance)
        #expect(!smallest.contains(CGPoint(x: 130, y: 55.5)))
        #expect(smallest.contains(CGPoint(x: 130, y: 57)))
    }

    @Test func theMarginAppliesToControlsButNotToTheScrim() {
        let control = ArtworkDiscHitArea(size: CGSize(width: 400, height: 400),
                                         controls: [CGRect(x: 0, y: 250, width: 400, height: 150)])
        #expect(!control.contains(CGPoint(x: 200, y: 245)))
        #expect(control.contains(CGPoint(x: 200, y: 236)))
        let scrim = ArtworkDiscHitArea(size: CGSize(width: 400, height: 400),
                                       covered: [CGRect(x: 0, y: 250, width: 400, height: 150)])
        #expect(scrim.contains(CGPoint(x: 200, y: 245)))
        #expect(!scrim.contains(CGPoint(x: 200, y: 251)))
    }

    @Test func theTooltipCoversOnlyTheClearPartOfTheCircle() {
        let clear = miniPlayer.clearRect
        #expect(clear.minY == miniPlayer.circle.minY)
        #expect(clear.maxY == 144)
        let smallest = ArtworkDiscHitArea(size: CGSize(width: 260, height: 260),
                                          controls: [CGRect(x: 0, y: 0, width: 260, height: 44)])
        #expect(abs(smallest.clearRect.minY - (44 + ArtworkDiscHitArea.controlClearance)) < 0.001)
        #expect(clear.minX == miniPlayer.circle.minX && clear.width == miniPlayer.circle.width)
        // With no room between the controls, there's nothing to click.
        let crowded = ArtworkDiscHitArea(size: CGSize(width: 260, height: 260),
                                         controls: [CGRect(x: 0, y: 0, width: 260, height: 120),
                                                    CGRect(x: 0, y: 130, width: 260, height: 130)])
        #expect(crowded.clearRect == .zero)
        #expect(!crowded.contains(CGPoint(x: 130, y: 125)))
    }

    // MARK: How

    private func press(clickCount: Int = 1, isInArea: Bool = true) -> ArtworkDiscClick {
        ArtworkDiscClick(screenLocation: CGPoint(x: 500, y: 500), windowFrame: CGRect(x: 100, y: 100, width: 320, height: 320),
                         clickCount: clickCount, isInArea: isInArea)
    }

    @Test func aStillSingleClickToggles() {
        let click = press()
        #expect(click.toggles(releasedAt: CGPoint(x: 500, y: 500), windowFrame: click.windowFrame, isInArea: true))
        // A tremble of a couple of points is still a click.
        #expect(click.toggles(releasedAt: CGPoint(x: 502, y: 501), windowFrame: click.windowFrame, isInArea: true))
    }

    @Test func dragsDontToggle() {
        let click = press()
        // The pointer moved past 3 points.
        #expect(!click.toggles(releasedAt: CGPoint(x: 504, y: 500), windowFrame: click.windowFrame, isInArea: true))
        // The window moved with the pointer, so the press looks still inside the window.
        let moved = click.windowFrame.offsetBy(dx: 40, dy: -12)
        #expect(click.isDrag(to: CGPoint(x: 500, y: 500), windowFrame: moved))
        #expect(!click.toggles(releasedAt: CGPoint(x: 500, y: 500), windowFrame: moved, isInArea: true))
    }

    @Test func aDoubleClickTogglesOnce() {
        // The first click toggles; the second of the pair is ignored, and so is a third.
        #expect(press(clickCount: 1).toggles(releasedAt: CGPoint(x: 500, y: 500),
                                             windowFrame: press().windowFrame, isInArea: true))
        #expect(!press(clickCount: 2).toggles(releasedAt: CGPoint(x: 500, y: 500),
                                              windowFrame: press().windowFrame, isInArea: true))
        #expect(!press(clickCount: 3).toggles(releasedAt: CGPoint(x: 500, y: 500),
                                              windowFrame: press().windowFrame, isInArea: true))
    }

    @Test func aPressOutsideTheAreaDoesntToggle() {
        #expect(!press(isInArea: false).toggles(releasedAt: CGPoint(x: 500, y: 500),
                                                windowFrame: press().windowFrame, isInArea: true))
        #expect(!press().toggles(releasedAt: CGPoint(x: 500, y: 500), windowFrame: press().windowFrame, isInArea: false))
    }
}
