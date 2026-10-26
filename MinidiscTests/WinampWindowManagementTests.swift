import CoreGraphics
import Foundation
import Testing
@testable import Minidisc

// MARK: - Docking

@Suite("Winamp docking")
struct WinampDockingTests {
    private let main = CGRect(x: 100, y: 500, width: 275, height: 116)

    @Test func windowsSnapToEachOthersEdgesWithinTenPoints() {
        // An equaliser dragged to 7 points below the main window snaps up against it.
        let equalizer = CGRect(x: 104, y: 377, width: 275, height: 116)
        #expect(WinampDocking.snap(equalizer, to: [main]) == CGRect(x: 100, y: 384, width: 275, height: 116))
        // 11 points away it stays put.
        let far = CGRect(x: 140, y: 373, width: 275, height: 116)
        #expect(WinampDocking.snap(far, to: [main]) == far)
        // To the right of the main window, tops lined up.
        let side = CGRect(x: 381, y: 495, width: 275, height: 116)
        #expect(WinampDocking.snap(side, to: [main]) == CGRect(x: 375, y: 500, width: 275, height: 116))
        // Windows far apart vertically don't snap sideways.
        let distant = CGRect(x: 380, y: 100, width: 275, height: 116)
        #expect(WinampDocking.snap(distant, to: [main]) == distant)
    }

    @Test func windowsSnapToScreenEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let nearCorner = CGRect(x: 6, y: 777, width: 275, height: 116)
        #expect(WinampDocking.snap(nearCorner, to: [], screens: [screen]) == CGRect(x: 0, y: 784, width: 275, height: 116))
    }

    @Test func dockedWindowsFollowTheMainWindow() {
        let equalizer = CGRect(x: 100, y: 384, width: 275, height: 116)
        let playlist = CGRect(x: 100, y: 152, width: 275, height: 232)
        let loose = CGRect(x: 900, y: 100, width: 275, height: 116)
        let frames = [main, equalizer, playlist, loose]
        #expect(WinampDocking.areDocked(main, equalizer))
        #expect(!WinampDocking.areDocked(main, playlist))
        let group = WinampDocking.dockedGroup(root: 0, frames: frames)
        #expect(group == [1, 2])
        let moved = WinampDocking.move(frames, root: 0, followers: group, by: CGVector(dx: 30, dy: -20))
        #expect(moved[1] == equalizer.offsetBy(dx: 30, dy: -20))
        #expect(moved[2] == playlist.offsetBy(dx: 30, dy: -20))
        #expect(moved[3] == loose)
    }

    @Test func draggingADockedWindowAloneUndocksIt() {
        let equalizer = CGRect(x: 100, y: 384, width: 275, height: 116)
        let moved = WinampDocking.move([main, equalizer], root: 1, followers: [], by: CGVector(dx: 0, dy: -60))
        #expect(moved[0] == main)
        #expect(!WinampDocking.areDocked(moved[0], moved[1]))
        #expect(WinampDocking.dockedGroup(root: 0, frames: moved).isEmpty)
    }

    @Test func cornerContactIsNotDocking() {
        let diagonal = CGRect(x: 375, y: 384, width: 275, height: 116)
        #expect(!WinampDocking.areDocked(main, diagonal))
    }

    @Test func shadingTheMainWindowPullsTheStackUp() {
        let equalizer = CGRect(x: 100, y: 384, width: 275, height: 116)
        let playlist = CGRect(x: 100, y: 152, width: 275, height: 232)
        let shaded = CGRect(x: 100, y: 602, width: 275, height: 14)
        let frames = WinampDocking.resize([main, equalizer, playlist], index: 0, to: shaded)
        #expect(frames[0] == shaded)
        #expect(frames[1] == CGRect(x: 100, y: 486, width: 275, height: 116))
        #expect(frames[2] == CGRect(x: 100, y: 254, width: 275, height: 232))
        #expect(WinampDocking.dockedGroup(root: 0, frames: frames) == [1, 2])
        // And unshading pushes it back down.
        let restored = WinampDocking.resize(frames, index: 0, to: main)
        #expect(restored[1] == equalizer)
        #expect(restored[2] == playlist)
    }

    @Test func wideningAWindowPushesItsRightNeighbour() {
        let playlist = CGRect(x: 100, y: 384, width: 275, height: 116)
        let side = CGRect(x: 375, y: 384, width: 275, height: 116)
        let widened = CGRect(x: 100, y: 384, width: 325, height: 116)
        let frames = WinampDocking.resize([playlist, side], index: 0, to: widened)
        #expect(frames[1] == side.offsetBy(dx: 50, dy: 0))
    }

    @Test func doubleSizeScalesTheStackAboutTheMainWindow() {
        let screen = [CGRect(x: 0, y: 0, width: 2560, height: 1415)]
        let equalizer = CGRect(x: 100, y: 384, width: 275, height: 116)
        let doubled = WinampDocking.zoom([main, equalizer], anchor: 0, from: 1, to: 2, screens: screen)
        #expect(doubled[0] == CGRect(x: 100, y: 384, width: 550, height: 232))
        #expect(doubled[1] == CGRect(x: 100, y: 152, width: 550, height: 232))
        #expect(WinampDocking.areDocked(doubled[0], doubled[1]))
        let back = WinampDocking.zoom(doubled, anchor: 0, from: 2, to: 1, screens: screen)
        #expect(back == [main, equalizer])
    }

    @Test func everyZoomLevelKeepsTheStackDockedAndReturnsExactly() {
        let screen = [CGRect(x: -5000, y: -5000, width: 15000, height: 15000)]
        let equalizer = CGRect(x: 100, y: 384, width: 275, height: 116)
        let playlist = CGRect(x: 100, y: 152, width: 275, height: 232)
        let side = CGRect(x: 375, y: 500, width: 275, height: 116)
        let start = [main, equalizer, playlist, side]
        var frames = start
        var level = 1
        for next in [4, 3, 2, 3, 1] {
            frames = WinampDocking.zoom(frames, anchor: 0, from: level, to: next, screens: screen)
            level = next
            // Sizes are exact multiples of the skin size, corners on whole points, the main
            // window's top-left corner fixed and every window still docked.
            for (frame, original) in zip(frames, start) {
                #expect(frame.width == original.width * CGFloat(next))
                #expect(frame.height == original.height * CGFloat(next))
                #expect(frame.minX == frame.minX.rounded() && frame.maxY == frame.maxY.rounded())
            }
            #expect(frames[0].minX == 100 && frames[0].maxY == 616)
            #expect(WinampDocking.dockedGroup(root: 0, frames: frames) == [1, 2, 3])
        }
        #expect(frames == start)
    }

    @Test func zoomingUpNearAScreenEdgeMovesTheStackBackOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        let nearRight = CGRect(x: 2000, y: 1200, width: 275, height: 116)
        let below = CGRect(x: 2000, y: 1084, width: 275, height: 116)
        let frames = WinampDocking.zoom([nearRight, below], anchor: 0, from: 1, to: 3, screens: [screen])
        #expect(frames[0] == CGRect(x: 1735, y: 968, width: 825, height: 348))
        #expect(frames[1] == CGRect(x: 1735, y: 620, width: 825, height: 348))
        #expect(WinampDocking.areDocked(frames[0], frames[1]))

        // A stack taller than the screen keeps its top on screen, so the title bar can be grabbed.
        let small = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let main = CGRect(x: 1000, y: 700, width: 275, height: 116)
        let equalizer = CGRect(x: 1000, y: 584, width: 275, height: 116)
        let tall = WinampDocking.zoom([main, equalizer], anchor: 0, from: 1, to: 4, screens: [small])
        #expect(tall[0] == CGRect(x: 340, y: 411, width: 1100, height: 464))
        #expect(tall[1] == CGRect(x: 340, y: -53, width: 1100, height: 464))
        #expect(WinampDocking.areDocked(tall[0], tall[1]))
    }

    @Test func aLooseWindowStaysOnItsOwnScreen() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let loose = CGRect(x: 3000, y: 100, width: 275, height: 232)
        let frames = WinampDocking.zoom([main, loose], anchor: 0, from: 1, to: 2, screens: [left, right])
        #expect(frames[0] == CGRect(x: 100, y: 384, width: 550, height: 232))
        #expect(frames[1] == CGRect(x: 2810, y: 0, width: 550, height: 464))
        #expect(right.contains(frames[1]))
    }

    @Test func screenAndFitHelpers() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        #expect(WinampDocking.screen(for: CGRect(x: 1400, y: 100, width: 275, height: 116), among: [left, right]) == right)
        #expect(WinampDocking.screen(for: CGRect(x: -900, y: 100, width: 275, height: 116), among: [left, right]) == nil)
        #expect(WinampDocking.offset(toFit: CGRect(x: 10, y: 10, width: 100, height: 100), in: left) == CGVector(dx: 0, dy: 0))
        #expect(WinampDocking.offset(toFit: CGRect(x: -20, y: 800, width: 100, height: 100), in: left) == CGVector(dx: 20, dy: -25))
        // Too big both ways: the left and top edges line up with the screen's.
        #expect(WinampDocking.offset(toFit: CGRect(x: 100, y: -500, width: 2000, height: 2000), in: left) == CGVector(dx: -100, dy: -625))
        // Off every screen, a window isn't moved.
        let lost = CGRect(x: -900, y: 100, width: 275, height: 116)
        #expect(WinampDocking.zoom([main, lost], anchor: 0, from: 1, to: 2, screens: [left])[1]
            == CGRect(x: -1900, y: -416, width: 550, height: 232))
    }
}

// MARK: - Windowshade

@Suite("Winamp windowshade")
struct WinampShadeTests {
    @Test func mainShadeBarHasItsOwnControls() {
        let map = WinampMainHitMap.shade
        #expect(map.control(at: CGPoint(x: 258, y: 6)) == .shade)
        #expect(map.control(at: CGPoint(x: 268, y: 6)) == .close)
        #expect(map.control(at: CGPoint(x: 172, y: 6)) == .previous)
        #expect(map.control(at: CGPoint(x: 180, y: 6)) == .play)
        #expect(map.control(at: CGPoint(x: 218, y: 6)) == .eject)
        #expect(map.control(at: CGPoint(x: 230, y: 6)) == .seek)
        #expect(map.control(at: CGPoint(x: 130, y: 6)) == .time)
        #expect(map.control(at: CGPoint(x: 60, y: 6)) == .titleBar)
        #expect(map.control(at: CGPoint(x: 60, y: 30)) == nil)
    }

    @Test func shadeTimeHasASignColumn() {
        #expect(WinampMainShadeLayout.timeText(WinampTimeDisplay.make(position: 65, duration: 200, mode: .elapsed)) == " 01:05")
        #expect(WinampMainShadeLayout.timeText(WinampTimeDisplay.make(position: 65, duration: 200, mode: .remaining)) == "-02:15")
        #expect(WinampMainShadeLayout.timeText(nil) == "")
    }

    @Test func playlistShadeControlsFollowItsWidth() {
        #expect(WinampPlaylistLayout.shadeControl(at: CGPoint(x: 318, y: 6), width: 325) == .close)
        #expect(WinampPlaylistLayout.shadeControl(at: CGPoint(x: 308, y: 6), width: 325) == .shade)
        #expect(WinampPlaylistLayout.shadeControl(at: CGPoint(x: 40, y: 6), width: 325) == .titleBar)
    }

    @Test func shadedWindowsRenderAsFourteenPixelBars() throws {
        let skin = try WinampSkin.bundled()
        let sprites = WinampSpriteCache(skin: skin)
        var main = WinampMainDisplayState()
        main.isShaded = true
        let mainImage = try #require(WinampMainRenderer.render(main, skin: skin, sprites: sprites))
        #expect(mainImage.width == 275 && mainImage.height == 14)

        var playlist = WinampPlaylistDisplayState()
        playlist.size = WinampPlaylistSize(widthSteps: 2, heightSteps: 4).pixelSize
        playlist.isShaded = true
        let playlistImage = try #require(WinampPlaylistRenderer.render(playlist, skin: skin, sprites: sprites, scale: 2))
        #expect(playlistImage.width == 650 && playlistImage.height == 28)
        #expect(WinampPlaylistRenderer.hasShadeSprites(skin))

        #expect(WinampEqualizerRenderer.hasShadeSprites(skin))
        let equalizer = try #require(WinampEqualizerRenderer.render(
            WinampEqualizerDisplayState(isShaded: true), skin: skin, sprites: sprites))
        #expect(equalizer.width == 275 && equalizer.height == 14)
    }

    @Test func fullWindowsRenderAtEitherSize() throws {
        let skin = try WinampSkin.bundled()
        let sprites = WinampSpriteCache(skin: skin)
        var playlist = WinampPlaylistDisplayState()
        playlist.rows = [.init(title: "1. Artist - Song", duration: "3:00", isSelected: true, isCurrent: true)]
        playlist.totalRows = 1
        playlist.openMenu = .add
        let one = try #require(WinampPlaylistRenderer.render(playlist, skin: skin, sprites: sprites, scale: 1))
        #expect(one.width == 275 && one.height == 232)
        let two = try #require(WinampEqualizerRenderer.render(WinampEqualizerDisplayState(), skin: skin, sprites: sprites, scale: 2))
        #expect(two.width == 550 && two.height == 232)
    }

    /// 3× and 4× on a Retina display draw each skin pixel as a solid 6×6 or 8×8 block of the
    /// colour it has at 1×: nearest-neighbour, with no smoothing between pixels.
    @Test func skinPixelsStaySharpAtEveryZoom() throws {
        let skin = try WinampSkin.bundled()
        let sprites = WinampSpriteCache(skin: skin)
        var state = WinampEqualizerDisplayState()
        state.isOn = true
        let one = try #require(WinampEqualizerRenderer.render(state, skin: skin, sprites: sprites, scale: 1))
        let base = rgbaPixels(one)
        for scale in [6, 8] {
            let big = try #require(WinampEqualizerRenderer.render(state, skin: skin, sprites: sprites, scale: CGFloat(scale)))
            #expect(big.width == one.width * scale && big.height == one.height * scale)
            let pixels = rgbaPixels(big)
            var mismatches = 0
            for y in 0..<big.height {
                for x in 0..<big.width {
                    let source = ((y / scale) * one.width + x / scale) * 4
                    let target = (y * big.width + x) * 4
                    if pixels[target..<target + 4] != base[source..<source + 4] { mismatches += 1 }
                }
            }
            #expect(mismatches == 0, "\(mismatches) pixels differ at \(scale)×")
        }
    }

    private func rgbaPixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}

// MARK: - Persistence

@Suite("Winamp window persistence", .serialized)
struct WinampWindowPersistenceTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "WinampWindowPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func newWindowsStartHiddenUnshadedAndStandardSize() {
        withDefaults { defaults in
            let preferences = WinampPreferences(defaults: defaults)
            for window in WinampPreferences.Window.allCases {
                #expect(!preferences.isShaded(window))
            }
            #expect(!preferences.isVisible(.equalizer))
            #expect(!preferences.isVisible(.playlist))
            #expect(preferences.topLeft(of: .playlist) == nil)
            #expect(preferences.playlistSize == .standard)
            #expect(!preferences.isEqualizerAuto)
            #expect(preferences.equalizerPresets.isEmpty)
        }
    }

    @Test func positionsVisibilityAndShadeSurviveARelaunch() {
        withDefaults { defaults in
            let first = WinampPreferences(defaults: defaults)
            first.setTopLeft(CGPoint(x: 10, y: 800), of: .main)
            first.setTopLeft(CGPoint(x: 10, y: 684), of: .equalizer)
            first.setTopLeft(CGPoint(x: 10, y: 568), of: .playlist)
            first.setVisible(true, .equalizer)
            first.setVisible(true, .playlist)
            first.setShaded(true, .main)
            first.setShaded(true, .playlist)
            first.playlistSize = WinampPlaylistSize(widthSteps: 3, heightSteps: 7)
            first.isEqualizerAuto = true

            let second = WinampPreferences(defaults: defaults)
            #expect(second.windowTopLeft == CGPoint(x: 10, y: 800))
            #expect(second.topLeft(of: .equalizer) == CGPoint(x: 10, y: 684))
            #expect(second.topLeft(of: .playlist) == CGPoint(x: 10, y: 568))
            #expect(second.isVisible(.equalizer) && second.isVisible(.playlist))
            #expect(second.isShaded(.main) && !second.isShaded(.equalizer) && second.isShaded(.playlist))
            #expect(second.playlistSize == WinampPlaylistSize(widthSteps: 3, heightSteps: 7))
            #expect(second.isEqualizerAuto)

            second.setTopLeft(CGPoint(x: CGFloat.nan, y: 0), of: .playlist)
            #expect(second.topLeft(of: .playlist) == nil)
        }
    }

    @Test func savedPresetsAreKeptByName() {
        withDefaults { defaults in
            let preferences = WinampPreferences(defaults: defaults)
            preferences.saveEqualizerPreset(WinampEqualizerPreset(name: "Zed", preamp: -2, gains: Array(repeating: 1, count: 10)))
            preferences.saveEqualizerPreset(WinampEqualizerPreset(name: "alpha", preamp: 0, gains: []))
            preferences.saveEqualizerPreset(WinampEqualizerPreset(name: "ZED", preamp: -6, gains: Array(repeating: 3, count: 10)))
            let reloaded = WinampPreferences(defaults: defaults).equalizerPresets
            #expect(reloaded.map(\.name) == ["alpha", "ZED"])
            #expect(reloaded.last?.preamp == -6)
            #expect(reloaded.first?.gains.count == 10)
            preferences.deleteEqualizerPreset(named: "alpha")
            #expect(preferences.equalizerPresets.map(\.name) == ["ZED"])
        }
    }
}
