import Foundation
import Testing
@testable import Minidisc

@Suite("Mac player controls show and hide on idle")
struct PlayerChromeVisibilityTests {
    private let delay = PlayerChromeVisibility.idleDelay

    @Test func hiddenUntilThePointerMoves() {
        let chrome = PlayerChromeVisibility()
        #expect(!chrome.isVisible(at: 0))
        #expect(chrome.hideDeadline(after: 0) == nil)
    }

    @Test func activityShowsThemUntilTheIdleDelayPasses() {
        var chrome = PlayerChromeVisibility()
        chrome.registerActivity(at: 10)
        #expect(chrome.isVisible(at: 10))
        #expect(chrome.isVisible(at: 10 + delay - 0.01))
        #expect(!chrome.isVisible(at: 10 + delay))
        #expect(chrome.hideDeadline(after: 11) == 10 + delay)
        #expect(chrome.hideDeadline(after: 10 + delay) == nil)
        // About two and a half seconds, as the Music app's.
        #expect(delay == 2.5)
    }

    @Test func moreActivityPushesTheDeadlineBack() {
        var chrome = PlayerChromeVisibility()
        chrome.registerActivity(at: 0)
        chrome.registerActivity(at: 2)
        #expect(chrome.isVisible(at: 4))
        #expect(chrome.hideDeadline(after: 4) == 2 + delay)
        #expect(!chrome.isVisible(at: 2 + delay))
    }

    @Test func leavingHidesThemAtOnce() {
        var chrome = PlayerChromeVisibility()
        chrome.registerActivity(at: 0)
        chrome.pointerExited()
        #expect(!chrome.isVisible(at: 0.1))
        #expect(chrome.hideDeadline(after: 0.1) == nil)
    }

    @Test(arguments: PlayerChromeVisibility.Pin.allCases)
    func eachPinKeepsThemOnScreen(_ pin: PlayerChromeVisibility.Pin) {
        var chrome = PlayerChromeVisibility()
        chrome.registerActivity(at: 0)
        chrome.set(pin, true, at: 1)
        // VoiceOver, keyboard focus, an open menu or popover, or a scrub: however long it idles,
        // and even with the pointer gone.
        #expect(chrome.isVisible(at: 1_000))
        chrome.pointerExited()
        #expect(chrome.isVisible(at: 1_000))
        #expect(chrome.hideDeadline(after: 1_000) == nil)
    }

    @Test func releasingThePinStartsTheIdleWaitAgain() {
        var chrome = PlayerChromeVisibility()
        chrome.registerActivity(at: 0)
        chrome.set(.menu, true, at: 1)
        chrome.set(.menu, false, at: 30)
        #expect(chrome.isVisible(at: 30 + delay - 0.1))
        #expect(!chrome.isVisible(at: 30 + delay))
        #expect(chrome.hideDeadline(after: 31) == 30 + delay)
    }

    @Test func theyStayWhileAnyPinIsHeld() {
        var chrome = PlayerChromeVisibility()
        chrome.set(.scrubbing, true, at: 0)
        chrome.set(.keyboardFocus, true, at: 1)
        chrome.set(.scrubbing, false, at: 2)
        #expect(chrome.isVisible(at: 100))
        chrome.set(.keyboardFocus, false, at: 100)
        #expect(chrome.isVisible(at: 101))
        #expect(!chrome.isVisible(at: 100 + delay))
        // Releasing a pin that wasn't held changes nothing.
        var idle = PlayerChromeVisibility()
        idle.set(.popover, false, at: 5)
        #expect(!idle.isVisible(at: 5))
    }

    @Test func voiceOverKeepsThemFromTheStart() {
        var chrome = PlayerChromeVisibility()
        chrome.set(.voiceOver, true, at: 0)
        #expect(chrome.isVisible(at: 0))
        #expect(chrome.isPinned)
    }
}
