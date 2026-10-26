import CoreGraphics
import Foundation
import Testing
@testable import Minidisc

@Suite("Winamp heart placement and drawing")
struct WinampHeartTests {
    private let map = WinampMainHitMap.classic

    @Test func theHeartIsAButtonOverItsHitArea() {
        #expect(map.rect(for: .favorite) == WinampHeart.hitArea)
        #expect(map.control(at: CGPoint(x: WinampHeart.origin.x + 3, y: WinampHeart.origin.y + 3)) == .favorite)
        #expect(WinampMainControl.favorite.isButton)
        #expect(!WinampMainHitMap.shade.regions.contains { $0.control == .favorite })
    }

    @Test func theHeartFitsTheGapBesideKHz() {
        let heart = CGRect(origin: WinampHeart.origin, size: CGSize(width: WinampHeart.width, height: WinampHeart.height))
        #expect(WinampHeart.hitArea.contains(heart))
        // The same height as the kbps and kHz text, on the same line.
        #expect(heart.minY == WinampMainLayout.khz.minY && heart.height == WinampMainLayout.khz.height)
        // Clear of the kHz box and its label, the mono light, the title and the volume slider.
        let neighbours = [
            WinampMainLayout.khz.insetBy(dx: 0, dy: 0).union(CGRect(x: 166, y: 43, width: 20, height: 6)),
            CGRect(origin: WinampMainLayout.mono, size: CGSize(width: 27, height: 12)),
            WinampMainLayout.title.insetBy(dx: 0, dy: -3),
            WinampMainLayout.volume,
        ]
        for neighbour in neighbours {
            #expect(!WinampHeart.hitArea.intersects(neighbour), "\(neighbour)")
        }
        // No other control shares any of the heart's area.
        for region in map.regions where region.control != .favorite {
            #expect(!region.rect.intersects(WinampHeart.hitArea), "\(region.control)")
        }
    }

    @Test func heartGlyphsAreSevenBySix() {
        let filled = WinampHeart.pixels(filled: true)
        let outline = WinampHeart.pixels(filled: false)
        for pixel in filled + outline {
            #expect(pixel.x >= 0 && pixel.x < CGFloat(WinampHeart.width))
            #expect(pixel.y >= 0 && pixel.y < CGFloat(WinampHeart.height))
        }
        #expect(Set(outline.map { "\($0)" }).isSubset(of: Set(filled.map { "\($0)" })))
        #expect(filled.count == 27)
        #expect(outline.count == 14)
        // The hollow heart is open in the middle; the solid one isn't.
        #expect(!outline.contains(CGPoint(x: 3, y: 2)))
        #expect(filled.contains(CGPoint(x: 3, y: 2)))
        // Both come to a single point at the bottom.
        #expect(filled.filter { $0.y == 5 } == [CGPoint(x: 3, y: 5)])
        #expect(outline.filter { $0.y == 5 } == [CGPoint(x: 3, y: 5)])
    }

    @Test func textColourIsTheCommonestAfterTheBackground() throws {
        let black = WinampColor(red: 0, green: 0, blue: 0)
        let green = WinampColor(red: 0, green: 0xE0, blue: 0)
        let dim = WinampColor(red: 0, green: 0x60, blue: 0)
        var pixels = Array(repeating: black, count: 60)
        for index in 0..<10 { pixels[index * 3] = green }
        pixels[1] = dim
        pixels[4] = dim
        let image = try #require(makeImage(width: 10, height: 6, pixels: pixels))
        #expect(WinampTextColor.dominantForeground(in: image) == green)
        let plain = try #require(makeImage(width: 2, height: 1, pixels: [black, black]))
        #expect(WinampTextColor.dominantForeground(in: plain) == nil)
    }

    @Test func bundledSkinHasATextColour() throws {
        let skin = try WinampSkin.bundled()
        let color = try #require(WinampTextColor.of(skin))
        #expect(color != skin.visColors[0])
        let noText = WinampSkin(name: "no text", sheets: skin.sheets.filter { $0.key != .text },
                                playlistStyle: skin.playlistStyle, visColors: skin.visColors, regions: [:])
        #expect(WinampTextColor.of(noText) == nil)
    }

    @Test func rendersHollowSolidAndHiddenHearts() throws {
        let skin = try WinampSkin.bundled()
        let ink = try #require(WinampTextColor.of(skin))
        let x = Int(WinampHeart.origin.x)
        let y = Int(WinampHeart.origin.y)

        var state = WinampMainDisplayState()
        let hidden = try #require(WinampMainRenderer.render(state, skin: skin))
        #expect(pixel(of: hidden, x: x, y: y + 1) != ink)

        state.favorite = WinampFavoriteStatus(songID: "s1", isFavorite: false, isOnline: true)
        let hollow = try #require(WinampMainRenderer.render(state, skin: skin))
        #expect(pixel(of: hollow, x: x, y: y + 1) == ink)
        #expect(pixel(of: hollow, x: x + 3, y: y + 5) == ink)
        #expect(pixel(of: hollow, x: x + 3, y: y + 2) != ink)

        state.favorite.isFavorite = true
        let solid = try #require(WinampMainRenderer.render(state, skin: skin))
        #expect(pixel(of: solid, x: x + 3, y: y + 2) == ink)

        // Held down, it moves a pixel down and right.
        state.pressed = .favorite
        let pressed = try #require(WinampMainRenderer.render(state, skin: skin))
        #expect(pixel(of: pressed, x: x + 4, y: y + 6) == ink)
        #expect(pixel(of: pressed, x: x, y: y + 1) != ink)
    }

    private func makeImage(width: Int, height: Int, pixels: [WinampColor]) -> CGImage? {
        var bytes: [UInt8] = []
        for color in pixels { bytes += [color.red, color.green, color.blue, 255] }
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    private func pixel(of image: CGImage, x: Int, y: Int) -> WinampColor {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return WinampColor(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
}

@Suite("Winamp current song heart")
struct WinampFavoriteStatusTests {
    @Test func aServerSongShowsItsState() {
        let starred = WinampFavoriteStatus.current(songID: "s1", isLocalFile: false, isRadio: false, isOnline: true) { $0 == "s1" }
        #expect(starred == WinampFavoriteStatus(songID: "s1", isFavorite: true, isOnline: true))
        #expect(starred.isShown && starred.canToggle)
        #expect(String(localized: starred.menuTitle) == String(localized: "Remove Current Song from Favorites"))

        let plain = WinampFavoriteStatus.current(songID: "s2", isLocalFile: false, isRadio: false, isOnline: true) { $0 == "s1" }
        #expect(plain.isShown && !plain.isFavorite)
        #expect(String(localized: plain.menuTitle) == String(localized: "Add Current Song to Favorites"))
    }

    @Test func offlineShowsTheHeartButCannotChangeIt() {
        let status = WinampFavoriteStatus.current(songID: "s1", isLocalFile: false, isRadio: false, isOnline: false) { _ in true }
        #expect(status.isShown && status.isFavorite)
        #expect(!status.canToggle)
    }

    @Test func nothingToStarHidesTheHeart() {
        let cases: [WinampFavoriteStatus] = [
            .current(songID: nil, isLocalFile: false, isRadio: false, isOnline: true) { _ in true },
            .current(songID: "", isLocalFile: false, isRadio: false, isOnline: true) { _ in true },
            .current(songID: "s1", isLocalFile: true, isRadio: false, isOnline: true) { _ in true },
            .current(songID: "local:abc", isLocalFile: false, isRadio: false, isOnline: true) { _ in true },
            .current(songID: "s1", isLocalFile: false, isRadio: true, isOnline: true) { _ in true },
        ]
        for status in cases {
            #expect(status == .unavailable)
            #expect(!status.isShown && !status.canToggle)
        }
    }
}

@Suite("Winamp playlist selection hearts")
struct WinampFavoriteSelectionTests {
    private func song(_ id: String, local: Bool = false) -> WinampFavoriteSelection.Song {
        WinampFavoriteSelection.Song(id: id, isLocalFile: local)
    }

    @Test func starsTheSongsThatArentFavouritesYet() {
        let action = WinampFavoriteSelection.action(for: [song("a"), song("b"), song("c")]) { $0 == "b" }
        #expect(action == .star(["a", "c"]))
        #expect(String(localized: WinampFavoriteSelection.title(for: action)) == String(localized: "Add to Favorites"))
    }

    @Test func unstarsWhenEverySongIsAFavourite() {
        let action = WinampFavoriteSelection.action(for: [song("a"), song("b")]) { _ in true }
        #expect(action == .unstar(["a", "b"]))
        #expect(String(localized: WinampFavoriteSelection.title(for: action)) == String(localized: "Remove from Favorites"))
    }

    @Test func leavesOutLocalFilesAndRepeats() {
        let songs = [song("a"), song("l1", local: true), song("local:x"), song("a"), song("b")]
        #expect(WinampFavoriteSelection.serverSongIDs(songs) == ["a", "b"])
        #expect(WinampFavoriteSelection.action(for: songs) { _ in false } == .star(["a", "b"]))
    }

    @Test func nothingStarrableGivesNoAction() {
        #expect(WinampFavoriteSelection.action(for: []) { _ in false } == nil)
        let action = WinampFavoriteSelection.action(for: [song("l1", local: true)]) { _ in false }
        #expect(action == nil)
        #expect(String(localized: WinampFavoriteSelection.title(for: action)) == String(localized: "Add to Favorites"))
    }
}
