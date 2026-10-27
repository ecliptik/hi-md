import CoreGraphics
import Foundation
import Testing
@testable import Minidisc

@Suite("Winamp time display")
struct WinampTimeDisplayTests {
    @Test func elapsedShowsWholeSecondsPlayed() {
        let time = WinampTimeDisplay.make(position: 83.9, duration: 245, mode: .elapsed)
        #expect(!time.isNegative)
        #expect(time.digits == [0, 1, 2, 3])
    }

    @Test func remainingCountsDownWithAMinusSign() {
        let time = WinampTimeDisplay.make(position: 83.4, duration: 245, mode: .remaining)
        #expect(time.isNegative)
        #expect(time.digits == [0, 2, 4, 2])
        #expect(WinampTimeDisplay.make(position: 0, duration: 245.7, mode: .remaining).digits == [0, 4, 0, 5])
        #expect(WinampTimeDisplay.make(position: 300, duration: 245, mode: .remaining).digits == [0, 0, 0, 0])
    }

    @Test func elapsedAndRemainingAddUpToTheDuration() {
        for position in stride(from: 0.0, through: 245, by: 0.7) {
            let elapsed = WinampTimeDisplay.make(position: position, duration: 245, mode: .elapsed)
            let remaining = WinampTimeDisplay.make(position: position, duration: 245, mode: .remaining)
            #expect(elapsed.minutes * 60 + elapsed.seconds + remaining.minutes * 60 + remaining.seconds == 245)
        }
    }

    @Test func remainingWithoutADurationShowsElapsed() {
        let time = WinampTimeDisplay.make(position: 61, duration: 0, mode: .remaining)
        #expect(!time.isNegative)
        #expect(time.digits == [0, 1, 0, 1])
    }

    @Test func longAndInvalidTimesStayInRange() {
        #expect(WinampTimeDisplay.make(position: 7_200, duration: 0, mode: .elapsed).digits == [9, 9, 5, 9])
        #expect(WinampTimeDisplay.make(position: -4, duration: 10, mode: .elapsed).digits == [0, 0, 0, 0])
        #expect(WinampTimeDisplay.make(position: .nan, duration: 10, mode: .elapsed).digits == [0, 0, 0, 0])
        #expect(WinampTimeDisplay.make(position: 5, duration: .infinity, mode: .remaining).digits == [0, 0, 0, 5])
    }

    @Test func clickingTogglesTheMode() {
        #expect(WinampTimeMode.elapsed.toggled == .remaining)
        #expect(WinampTimeMode.remaining.toggled == .elapsed)
    }
}

@Suite("Winamp marquee")
struct WinampMarqueeTests {
    @Test func songTitleReadsArtistTitleAndDuration() {
        #expect(WinampMarquee.songTitle(artist: "Artist", title: "Title", duration: 225) == "Artist - Title (3:45)")
        #expect(WinampMarquee.songTitle(artist: nil, title: "Title", duration: 59.9) == "Title (0:59)")
        #expect(WinampMarquee.songTitle(artist: "  ", title: "Title", duration: 0) == "Title")
        #expect(WinampMarquee.songTitle(artist: "A", title: "Long", duration: 3_725) == "A - Long (1:02:05)")
    }

    @Test func shortTextStaysStill() {
        let text = "Artist - Title (3:45)"
        #expect(!WinampMarquee.scrolls(text))
        #expect(WinampMarquee.cycleLength(of: text) == 0)
        #expect(WinampMarquee.visibleText(text, step: 7) == text)
        #expect(WinampMarquee.nextStep(after: 3, text: text) == 0)
        // Exactly 31 characters still fits.
        let fits = String(repeating: "x", count: 31)
        #expect(!WinampMarquee.scrolls(fits))
    }

    @Test func longTextScrollsOneCharacterPerStepAndLoops() {
        let text = "Minidisc Ensemble - Gold on Black (4:05)" // 40 characters
        #expect(WinampMarquee.scrolls(text))
        #expect(WinampMarquee.cycleLength(of: text) == 40 + WinampMarquee.separator.count)
        #expect(WinampMarquee.visibleText(text, step: 0) == String(text.prefix(31)))
        #expect(WinampMarquee.visibleText(text, step: 1) == String(text.dropFirst().prefix(31)))
        // Past the end the separator follows, then the start of the text again.
        let loop = text + WinampMarquee.separator + text
        #expect(WinampMarquee.visibleText(text, step: 20) == String(Array(loop)[20..<51]))
        let cycle = WinampMarquee.cycleLength(of: text)
        #expect(WinampMarquee.visibleText(text, step: cycle) == WinampMarquee.visibleText(text, step: 0))
        #expect(WinampMarquee.visibleText(text, step: -1) == WinampMarquee.visibleText(text, step: cycle - 1))
        for step in 0..<cycle {
            #expect(WinampMarquee.visibleText(text, step: step).count == WinampMarquee.visibleCharacters)
        }
    }

    @Test func stepsWrapAtTheEndOfTheCycle() {
        let text = String(repeating: "abc ", count: 10)
        let cycle = WinampMarquee.cycleLength(of: text)
        #expect(WinampMarquee.nextStep(after: 0, text: text) == 1)
        #expect(WinampMarquee.nextStep(after: cycle - 1, text: text) == 0)
    }

    @Test func sliderMessagesUseThePlainBitmapFont() {
        #expect(WinampSliderMessage.seek(fraction: 0.5, duration: 245) == "Seek to: 2:02/4:05 (50%)")
        #expect(WinampSliderMessage.volume(0.543) == "Volume: 54%")
        #expect(WinampSliderMessage.balance(0) == "Balance: Center")
        #expect(WinampSliderMessage.balance(-0.31) == "Balance: 31% Left")
        #expect(WinampSliderMessage.balance(1) == "Balance: 100% Right")
        for message in [WinampSliderMessage.seek(fraction: 0.2, duration: 99), WinampSliderMessage.balance(0.4)] {
            #expect(message.allSatisfy { WinampSprites.glyphCell(for: $0) != nil })
        }
    }
}

@Suite("Winamp track info")
struct WinampTrackInfoTests {
    @Test func kbpsFitsThreeCharacters() {
        #expect(WinampTrackInfoFormat.kbps(320) == "320")
        #expect(WinampTrackInfoFormat.kbps(96) == " 96")
        #expect(WinampTrackInfoFormat.kbps(1411) == "1k4")
        #expect(WinampTrackInfoFormat.kbps(0) == nil)
        #expect(WinampTrackInfoFormat.kbps(nil) == nil)
    }

    @Test func khzIsWholeKilohertz() {
        #expect(WinampTrackInfoFormat.khz(44_100) == "44")
        #expect(WinampTrackInfoFormat.khz(48_000) == "48")
        #expect(WinampTrackInfoFormat.khz(8_000) == " 8")
        #expect(WinampTrackInfoFormat.khz(nil) == nil)
    }

    @Test func transcodingCapsTheBitrate() {
        #expect(WinampTrackInfoFormat.effectiveBitRate(file: 1_000, maxBitRate: 320) == 320)
        #expect(WinampTrackInfoFormat.effectiveBitRate(file: 128, maxBitRate: 320) == 128)
        #expect(WinampTrackInfoFormat.effectiveBitRate(file: 900, maxBitRate: nil) == 900)
        #expect(WinampTrackInfoFormat.effectiveBitRate(file: nil, maxBitRate: nil) == nil)
    }
}

@Suite("Winamp sliders")
struct WinampSliderTests {
    @Test func valuesMapToThumbPixels() {
        let seek = WinampSliderGeometry.seek
        #expect(seek.travel == 219)
        #expect(seek.thumbOffset(for: 0) == 0)
        #expect(seek.thumbOffset(for: 1) == 219)
        #expect(seek.thumbOffset(for: 0.5) == 110)
        #expect(seek.thumbOffset(for: 2) == 219)
        #expect(seek.thumbOffset(for: .nan) == 0)
        #expect(WinampSliderGeometry.volume.travel == 54)
        #expect(WinampSliderGeometry.balance.travel == 24)
    }

    @Test func pixelsMapBackToValues() {
        let volume = WinampSliderGeometry.volume
        // Grabbing the thumb's centre at the far left reads 0, at the far right 1.
        #expect(volume.fraction(pointerX: 107 + 7, grabOffset: 7) == 0)
        #expect(volume.fraction(pointerX: 107 + 54 + 7, grabOffset: 7) == 1)
        #expect(volume.fraction(pointerX: 0, grabOffset: 7) == 0)
        #expect(volume.fraction(pointerX: 500, grabOffset: 7) == 1)
        for offset in 0...volume.travel {
            let fraction = volume.fraction(pointerX: Double(107 + offset), grabOffset: 0)
            #expect(volume.thumbOffset(for: fraction) == offset)
        }
    }

    @Test func pressingTheThumbKeepsTheGrabPoint() {
        let seek = WinampSliderGeometry.seek
        // The thumb sits at 16 + 110 for a half-way value; pressing 5 pixels into it keeps 5.
        #expect(seek.grabOffset(pointerX: 16 + 110 + 5, currentFraction: 0.5) == 5)
        // Pressing the track elsewhere centres the thumb on the pointer.
        #expect(seek.grabOffset(pointerX: 40, currentFraction: 0.5) == 14.5)
        let jumped = seek.fraction(pointerX: 40, grabOffset: 14.5)
        #expect(abs(Double(16 + seek.thumbOffset(for: jumped)) + 14.5 - 40) <= 1)
    }

    @Test func backgroundFramesSpanTheSheet() {
        #expect(WinampSliderGeometry.backgroundFrame(for: 0) == 0)
        #expect(WinampSliderGeometry.backgroundFrame(for: 1) == 27)
        #expect(WinampSliderGeometry.backgroundFrame(for: 0.5) == 14)
        #expect(WinampBalance.backgroundFrame(for: 0) == 0)
        #expect(WinampBalance.backgroundFrame(for: -1) == 27)
        #expect(WinampBalance.backgroundFrame(for: 1) == 27)
    }

    @Test func balanceSnapsToTheCentre() {
        #expect(WinampBalance.fraction(for: 0) == 0.5)
        #expect(WinampBalance.fraction(for: -1) == 0)
        #expect(WinampBalance.balance(for: 0.52) == 0)
        #expect(WinampBalance.balance(for: 0) == -1)
        #expect(WinampBalance.balance(for: 1) == 1)
        #expect(abs(WinampBalance.balance(for: 0.75) - 0.5) < 1e-9)
    }
}

@Suite("Winamp main window hit map")
struct WinampHitMapTests {
    private let map = WinampMainHitMap.classic

    private func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    @Test func buttonsSitWhereTheLayoutDrawsThem() {
        let buttons: [(WinampMainControl, CGPoint, WinampSprite)] = [
            (.previous, WinampMainLayout.previous, WinampSprites.previous.normal),
            (.play, WinampMainLayout.play, WinampSprites.play.normal),
            (.pause, WinampMainLayout.pause, WinampSprites.pause.normal),
            (.stop, WinampMainLayout.stop, WinampSprites.stop.normal),
            (.next, WinampMainLayout.next, WinampSprites.next.normal),
            (.eject, WinampMainLayout.eject, WinampSprites.eject.normal),
            (.shuffle, WinampMainLayout.shuffle, WinampSprites.shuffleToggle.off.normal),
            (.repeatToggle, WinampMainLayout.repeatToggle, WinampSprites.repeatToggle.off.normal),
            (.equalizer, WinampMainLayout.equalizerToggle, WinampSprites.equalizerToggle.off.normal),
            (.playlist, WinampMainLayout.playlistToggle, WinampSprites.playlistToggle.off.normal),
            (.close, WinampMainLayout.close, WinampSprites.close.normal),
        ]
        for (control, origin, sprite) in buttons {
            let rect = CGRect(origin: origin, size: CGSize(width: sprite.width, height: sprite.height))
            #expect(map.rect(for: control) == rect, "\(control)")
            #expect(map.control(at: center(rect)) == control, "\(control)")
            #expect(control.isButton)
        }
    }

    @Test func transportButtonsMeetWithoutGaps() {
        // Prev, Play, Pause, Stop and Next are 23 pixels apart: x 16 through 129 is all buttons.
        let row: [WinampMainControl] = [.previous, .play, .pause, .stop, .next]
        for x in 16..<130 {
            let control = map.control(at: CGPoint(x: Double(x) + 0.5, y: 95))
            #expect(control.map(row.contains) == true, "x \(x)")
        }
        #expect(map.control(at: CGPoint(x: 15.5, y: 95)) == nil)
    }

    @Test func titleBarButtonsWinOverTheDragArea() {
        #expect(map.control(at: CGPoint(x: 268, y: 7)) == .close)
        #expect(map.control(at: CGPoint(x: 258, y: 7)) == .shade)
        #expect(map.control(at: CGPoint(x: 248, y: 7)) == .minimize)
        #expect(map.control(at: CGPoint(x: 10, y: 7)) == .options)
        #expect(map.control(at: CGPoint(x: 137, y: 7)) == .titleBar)
        #expect(map.control(at: CGPoint(x: 137, y: 13.5)) == .titleBar)
        #expect(map.control(at: CGPoint(x: 137, y: 14.5)) != .titleBar)
    }

    @Test func clutterLettersAndDisplays() {
        #expect(map.control(at: CGPoint(x: 13, y: 26)) == .clutter(.options))
        #expect(map.control(at: CGPoint(x: 13, y: 36)) == .clutter(.alwaysOnTop))
        #expect(map.control(at: CGPoint(x: 13, y: 43)) == .clutter(.info))
        #expect(map.control(at: CGPoint(x: 13, y: 50)) == .clutter(.doubleSize))
        #expect(map.control(at: CGPoint(x: 13, y: 58)) == .clutter(.visualizer))
        #expect(map.control(at: CGPoint(x: 70, y: 32)) == .time)
        #expect(map.control(at: CGPoint(x: 60, y: 50)) == .visualizer)
        #expect(map.control(at: CGPoint(x: 180, y: 30)) == .songTitle)
    }

    @Test func slidersCoverTheirTracks() {
        #expect(map.control(at: CGPoint(x: 17, y: 77)) == .seek)
        #expect(map.control(at: CGPoint(x: 263, y: 77)) == .seek)
        #expect(map.control(at: CGPoint(x: 108, y: 63)) == .volume)
        #expect(map.control(at: CGPoint(x: 214, y: 63)) == .balance)
        for slider in [WinampMainControl.seek, .volume, .balance] {
            #expect(!slider.isButton)
        }
    }

    @Test func everyRegionIsInsideTheWindow() {
        let window = CGRect(origin: .zero, size: WinampMainLayout.size)
        for region in map.regions {
            #expect(window.contains(region.rect), "\(region.control)")
        }
        #expect(map.control(at: CGPoint(x: 3, y: 112)) == nil)
    }

    @Test func windowShapeFollowsTheRegion() {
        #expect(WinampWindowShape(polygons: []).isRectangular)
        #expect(WinampWindowShape(polygons: []).contains(CGPoint(x: -5, y: -5)))
        let notched = WinampWindowShape(polygons: [[
            CGPoint(x: 0, y: 0), CGPoint(x: 275, y: 0), CGPoint(x: 275, y: 116), CGPoint(x: 20, y: 116), CGPoint(x: 0, y: 96),
        ]])
        #expect(!notched.isRectangular)
        #expect(notched.contains(CGPoint(x: 137, y: 58)))
        #expect(!notched.contains(CGPoint(x: 2, y: 114)))
        // Polygons with fewer than three points are ignored.
        #expect(WinampWindowShape(polygons: [[CGPoint(x: 1, y: 1)]]).isRectangular)
    }
}

@Suite("Winamp visualiser")
struct WinampVisualizerTests {
    @Test func clickingCyclesTheModes() {
        #expect(WinampVisualizerMode.spectrum.next == .oscilloscope)
        #expect(WinampVisualizerMode.oscilloscope.next == .off)
        #expect(WinampVisualizerMode.off.next == .spectrum)
    }

    @Test func peaksHoldThenFall() {
        var markers = WinampPeakMarkers()
        #expect(markers.update(with: [0.8, 0.2]) == [0.8, 0.2])
        for _ in 0..<WinampPeakMarkers.holdFrames {
            #expect(markers.update(with: [0, 0.5]) == [0.8, 0.5])
        }
        let fallen = markers.update(with: [0, 0.5])
        #expect(abs(fallen[0] - (0.8 - WinampPeakMarkers.fallPerFrame)) < 1e-6)
        #expect(fallen[1] == 0.5)
    }
}

@Suite("Winamp main window rendering")
struct WinampRendererTests {
    @Test func rendersTheBundledSkinAtClassicSize() throws {
        let skin = try WinampSkin.bundled()
        var state = WinampMainDisplayState()
        state.playback = .playing
        state.time = WinampTimeDisplay.make(position: 83, duration: 245, mode: .elapsed)
        state.title = "Hi-MD"
        state.visualizer = WinampVisualizerPicture(mode: .spectrum, bars: Array(repeating: 1, count: 75),
                                                   peaks: Array(repeating: 1, count: 75))
        let image = try #require(WinampMainRenderer.render(state, skin: skin))
        #expect(image.width == 275 && image.height == 116)
        #expect(alpha(of: image, x: 0, y: 0) == 255)
        // A full-height bar's top pixel is the peak colour.
        #expect(pixel(of: image, x: 24, y: 43) == skin.visColors[23])
    }

    @Test func regionShapesLeaveTheOutsideTransparent() throws {
        let base = try WinampSkin.bundled()
        let shaped = WinampSkin(name: "shaped", sheets: base.sheets, playlistStyle: base.playlistStyle, visColors: base.visColors,
                                regions: ["normal": [[CGPoint(x: 10, y: 0), CGPoint(x: 275, y: 0), CGPoint(x: 275, y: 116),
                                                      CGPoint(x: 0, y: 116), CGPoint(x: 0, y: 10)]]])
        let image = try #require(WinampMainRenderer.render(WinampMainDisplayState(), skin: shaped))
        #expect(alpha(of: image, x: 1, y: 1) == 0)
        #expect(alpha(of: image, x: 200, y: 60) == 255)
    }

    private func rgba(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return bytes
    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 { rgba(of: image, x: x, y: y)[3] }

    private func pixel(of image: CGImage, x: Int, y: Int) -> WinampColor {
        let bytes = rgba(of: image, x: x, y: y)
        return WinampColor(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
}

@Suite("Winamp preferences", .serialized)
struct WinampPreferencesTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "WinampPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func defaultsAreClosedSpectrumElapsedAndTheBundledSkin() {
        withDefaults { defaults in
            let preferences = WinampPreferences(defaults: defaults)
            #expect(!preferences.isOpen)
            #expect(preferences.windowTopLeft == nil)
            #expect(preferences.zoom == 1)
            #expect(!preferences.isDoubleSize)
            #expect(!preferences.isAlwaysOnTop)
            #expect(preferences.visualizerMode == .spectrum)
            #expect(preferences.timeMode == .elapsed)
            #expect(preferences.skin == .bundled)
        }
    }

    @Test func windowStatePersistsAcrossInstances() {
        withDefaults { defaults in
            let first = WinampPreferences(defaults: defaults)
            first.isOpen = true
            first.windowTopLeft = CGPoint(x: 120.5, y: 840)
            first.zoom = 3
            first.isAlwaysOnTop = true
            first.visualizerMode = .oscilloscope
            first.timeMode = .remaining

            let second = WinampPreferences(defaults: defaults)
            #expect(second.isOpen)
            #expect(second.windowTopLeft == CGPoint(x: 120.5, y: 840))
            #expect(second.zoom == 3)
            #expect(second.isDoubleSize)
            // The View menu's zoom items read the same key through @AppStorage.
            #expect(defaults.integer(forKey: WinampPreferences.Key.zoom) == 3)
            #expect(second.isAlwaysOnTop)
            #expect(second.visualizerMode == .oscilloscope)
            #expect(second.timeMode == .remaining)
            // The menu toggle reads the same key through @AppStorage.
            #expect(defaults.bool(forKey: WinampPreferences.Key.isOpen))

            second.windowTopLeft = nil
            #expect(WinampPreferences(defaults: defaults).windowTopLeft == nil)
        }
    }

    @Test func zoomIsClampedAndDoubleSizeFromAnOlderBuildBecomesTwoTimes() {
        withDefaults { defaults in
            defaults.set(true, forKey: WinampPreferences.Key.isDoubleSize)
            let migrated = WinampPreferences(defaults: defaults)
            #expect(migrated.zoom == 2)
            #expect(defaults.integer(forKey: WinampPreferences.Key.zoom) == 2)

            migrated.zoom = 9
            #expect(migrated.zoom == 4)
            migrated.zoom = 0
            #expect(migrated.zoom == 1)
            // An older build, which only knows Double Size, opens at normal size again.
            #expect(!defaults.bool(forKey: WinampPreferences.Key.isDoubleSize))
            migrated.zoom = 3
            #expect(defaults.bool(forKey: WinampPreferences.Key.isDoubleSize))

            defaults.set(17, forKey: WinampPreferences.Key.zoom)
            #expect(WinampPreferences(defaults: defaults).zoom == 4)
        }
    }

    @Test func doubleSizeTogglesBetweenOneAndTwoTimes() {
        #expect(WinampZoom.toggledDoubleSize(from: 1) == 2)
        #expect(WinampZoom.toggledDoubleSize(from: 2) == 1)
        #expect(WinampZoom.toggledDoubleSize(from: 3) == 1)
        #expect(WinampZoom.toggledDoubleSize(from: 4) == 1)
        #expect(Array(WinampZoom.levels).map(WinampZoom.title) == ["1×", "2×", "3×", "4×"])
    }

    @Test func skinChoicePersistsAndResets() {
        withDefaults { defaults in
            let bookmark = Data([1, 2, 3, 4])
            WinampPreferences(defaults: defaults).skin = .custom(name: "Classic Blue", bookmark: bookmark, isSecurityScoped: true)
            #expect(WinampPreferences(defaults: defaults).skin == .custom(name: "Classic Blue", bookmark: bookmark, isSecurityScoped: true))

            WinampPreferences(defaults: defaults).skin = .custom(name: "Copy", bookmark: bookmark, isSecurityScoped: false)
            #expect(WinampPreferences(defaults: defaults).skin == .custom(name: "Copy", bookmark: bookmark, isSecurityScoped: false))

            WinampPreferences(defaults: defaults).skin = .bundled
            #expect(WinampPreferences(defaults: defaults).skin == .bundled)
            #expect(defaults.data(forKey: WinampPreferences.Key.skinBookmark) == nil)
        }
    }

    @Test func unreadableValuesFallBack() {
        withDefaults { defaults in
            defaults.set("sparkles", forKey: WinampPreferences.Key.visualizerMode)
            defaults.set("backwards", forKey: WinampPreferences.Key.timeMode)
            defaults.set([1.0], forKey: WinampPreferences.Key.windowTopLeft)
            defaults.set(Data(), forKey: WinampPreferences.Key.skinBookmark)
            let preferences = WinampPreferences(defaults: defaults)
            #expect(preferences.visualizerMode == .spectrum)
            #expect(preferences.timeMode == .elapsed)
            #expect(preferences.windowTopLeft == nil)
            #expect(preferences.skin == .bundled)
        }
    }
}
