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
        let equalizer = CGRect(x: 100, y: 384, width: 275, height: 116)
        let doubled = WinampDocking.scale([main, equalizer], anchor: 0, by: 2)
        #expect(doubled[0] == CGRect(x: 100, y: 384, width: 550, height: 232))
        #expect(doubled[1] == CGRect(x: 100, y: 152, width: 550, height: 232))
        #expect(WinampDocking.areDocked(doubled[0], doubled[1]))
        let back = WinampDocking.scale(doubled, anchor: 0, by: 0.5)
        #expect(back == [main, equalizer])
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
