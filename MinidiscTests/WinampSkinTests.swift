import Compression
import CoreGraphics
import Foundation
import Testing
@testable import Minidisc

// MARK: - Fixtures

/// A 24-bit bottom-up BMP, the format most classic skins use.
private func makeBMP(width: Int, height: Int, color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
    let rowSize = (width * 3 + 3) & ~3
    let pixelBytes = rowSize * height
    var data = Data()
    func le16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]) }
    func le32(_ value: Int) { le16(value & 0xFFFF); le16(value >> 16 & 0xFFFF) }
    data.append(contentsOf: Array("BM".utf8))
    le32(54 + pixelBytes); le32(0); le32(54)
    le32(40); le32(width); le32(height); le16(1); le16(24); le32(0); le32(pixelBytes); le32(2835); le32(2835); le32(0); le32(0)
    for row in (0..<height).reversed() {
        var bytes = [UInt8]()
        for column in 0..<width {
            let (r, g, b) = color(column, row)
            bytes += [b, g, r]
        }
        bytes += [UInt8](repeating: 0, count: rowSize - width * 3)
        data.append(contentsOf: bytes)
    }
    return data
}

/// Writes a ZIP with stored or raw-DEFLATE entries, enough to exercise `ZipArchive`.
private struct TestZipWriter {
    struct File {
        let path: String
        let data: Data
        let deflate: Bool
    }

    var files: [File] = []

    mutating func add(_ path: String, _ data: Data, deflate: Bool = true) {
        files.append(File(path: path, data: data, deflate: deflate))
    }

    func archive() -> Data {
        var output = Data()
        var central = Data()
        func le16(_ value: Int, _ into: inout Data) { into.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]) }
        func le32(_ value: Int, _ into: inout Data) { le16(value & 0xFFFF, &into); le16(value >> 16 & 0xFFFF, &into) }
        for file in files {
            let payload = file.deflate ? deflated(file.data) : file.data
            let crc = Int(ZipArchive.crc32(file.data))
            let name = Data(file.path.utf8)
            let offset = output.count
            le32(0x0403_4B50, &output); le16(20, &output); le16(0x800, &output); le16(file.deflate ? 8 : 0, &output)
            le16(0, &output); le16(0x21, &output); le32(crc, &output)
            le32(payload.count, &output); le32(file.data.count, &output); le16(name.count, &output); le16(0, &output)
            output.append(name)
            output.append(payload)

            le32(0x0201_4B50, &central); le16(20, &central); le16(20, &central); le16(0x800, &central)
            le16(file.deflate ? 8 : 0, &central); le16(0, &central); le16(0x21, &central); le32(crc, &central)
            le32(payload.count, &central); le32(file.data.count, &central); le16(name.count, &central)
            le16(0, &central); le16(0, &central); le16(0, &central); le16(0, &central); le32(0, &central)
            le32(offset, &central)
            central.append(name)
        }
        let centralOffset = output.count
        output.append(central)
        le32(0x0605_4B50, &output); le16(0, &output); le16(0, &output)
        le16(files.count, &output); le16(files.count, &output)
        le32(central.count, &output); le32(centralOffset, &output); le16(0, &output)
        return output
    }

    private func deflated(_ data: Data) -> Data {
        let capacity = data.count + 1024
        var output = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBytes { source in
            compression_encode_buffer(&output, capacity, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return Data(output.prefix(written))
    }
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw so that pixel (x, y), counted from the top, lands on the context's single pixel.
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (bytes[0], bytes[1], bytes[2])
}

private let red: (UInt8, UInt8, UInt8) = (255, 0, 0)
private let blue: (UInt8, UInt8, UInt8) = (0, 0, 255)

/// Colour management may move a channel by a step or two, so compare loosely.
private func isRed(_ color: (UInt8, UInt8, UInt8)) -> Bool { color.0 > 200 && color.1 < 50 && color.2 < 50 }
private func isBlue(_ color: (UInt8, UInt8, UInt8)) -> Bool { color.0 < 50 && color.1 < 50 && color.2 > 200 }

/// Every sheet at its classic size, filled blue; the play button's pressed state is red.
/// Files sit in a nested folder with mixed case, half stored and half deflated.
private func makeSkinArchive(omitting: Set<WinampSpriteSheet> = [], extras: [String: String] = [:]) -> Data {
    var zip = TestZipWriter()
    for (index, sheet) in WinampSpriteSheet.allCases.enumerated() where !omitting.contains(sheet) {
        let size = sheet.classicSize
        let bmp = makeBMP(width: size.width, height: size.height) { x, y in
            sheet == .cbuttons && (23..<46).contains(x) && (18..<36).contains(y) ? red : blue
        }
        let name = index.isMultiple(of: 2) ? sheet.fileName.uppercased() : sheet.fileName
        zip.add("Cool Skin/\(name)", bmp, deflate: index.isMultiple(of: 3))
    }
    zip.add("__MACOSX/Cool Skin/._main.bmp", Data("junk".utf8), deflate: false)
    for (name, text) in extras {
        zip.add("Cool Skin/\(name)", Data(text.utf8), deflate: false)
    }
    return zip.archive()
}

// MARK: - ZIP

@Suite("Skin ZIP reader")
struct ZipArchiveTests {
    @Test func readsStoredAndDeflatedEntries() throws {
        var zip = TestZipWriter()
        let text = Data(String(repeating: "Winamp skins are ZIP files. ", count: 50).utf8)
        zip.add("plain.txt", text, deflate: false)
        zip.add("folder/Packed.TXT", text, deflate: true)
        zip.add("empty.txt", Data(), deflate: false)
        let archive = try ZipArchive(data: zip.archive())
        #expect(archive.entries.count == 3)
        #expect(try archive.contents(named: "plain.txt") == text)
        let packed = try #require(archive.entry(named: "packed.txt"))
        #expect(packed.method == ZipArchive.deflateMethod)
        #expect(packed.compressedSize < packed.uncompressedSize)
        #expect(try archive.contents(of: packed) == text)
        #expect(try archive.contents(named: "EMPTY.TXT") == Data())
        #expect(archive.entry(named: "missing.txt") == nil)
    }

    @Test func prefersTheShallowestRealFile() throws {
        var zip = TestZipWriter()
        zip.add("__MACOSX/main.bmp", Data("resource fork".utf8), deflate: false)
        zip.add("skin/._main.bmp", Data("apple double".utf8), deflate: false)
        zip.add("skin/deeper/main.bmp", Data("deep".utf8), deflate: false)
        zip.add("skin/Main.bmp", Data("right".utf8), deflate: false)
        let archive = try ZipArchive(data: zip.archive())
        #expect(try archive.contents(named: "main.bmp") == Data("right".utf8))
    }

    @Test func rejectsNonZipAndDetectsCorruption() throws {
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(data: Data("not a zip at all, sorry".utf8)) }
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(data: Data()) }

        var zip = TestZipWriter()
        zip.add("a.txt", Data("hello, skin".utf8), deflate: false)
        var bytes = [UInt8](zip.archive())
        // The stored payload starts after the 30-byte local header and the 5-byte name.
        bytes[35] ^= 0xFF
        let archive = try ZipArchive(data: Data(bytes))
        #expect(throws: ZipArchive.ZipError.corrupt("checksum of a.txt")) { try archive.contents(named: "a.txt") }
    }

    @Test func crcMatchesTheStandardCheckValue() {
        #expect(ZipArchive.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
    }
}

// MARK: - Skins

@Suite("Winamp skins")
struct WinampSkinTests {
    @Test func loadsASyntheticSkinWithMixedCaseNestedFiles() throws {
        let data = makeSkinArchive(extras: [
            "PLEDIT.TXT": "[Text]\r\nNormal=#00FF00\r\nCurrent=FFFFFF\r\nnormalbg=#000000 ; trailing\r\nSelectedBG=#0000C6\r\nFont=Arial\r\n",
            "viscolor.txt": "0,0,0, // background\n24,33,41\n255 , 1 , 2 // spaced\n",
            "region.txt": "[Normal]\nNumPoints=4, 4\nPointList=0,0, 275,0, 275,14, 0,14,  0,15, 275,15, 275,116, 0,116\n[WindowShade]\nNumPoints=4\nPointList=0 0 275 0 275 14 0 14\n",
        ])
        let skin = try WinampSkin.load(data: data, name: "Cool Skin")
        #expect(skin.missingSheets.isEmpty)
        #expect(Set(skin.sheets.keys) == Set(WinampSpriteSheet.allCases))
        #expect(skin.usesExtendedNumbers)

        let pressed = try #require(skin.image(for: WinampSprites.play.pressed))
        #expect(pressed.width == 23 && pressed.height == 18)
        #expect(isRed(pixel(pressed, x: 0, y: 0)))
        #expect(isRed(pixel(pressed, x: 22, y: 17)))
        let normal = try #require(skin.image(for: WinampSprites.play.normal))
        #expect(isBlue(pixel(normal, x: 5, y: 5)))

        #expect(skin.playlistStyle.normal == WinampColor(red: 0, green: 255, blue: 0))
        #expect(skin.playlistStyle.current == WinampColor(red: 255, green: 255, blue: 255))
        #expect(skin.playlistStyle.normalBackground == WinampColor(red: 0, green: 0, blue: 0))
        #expect(skin.playlistStyle.selectedBackground == WinampColor(red: 0, green: 0, blue: 0xC6))
        #expect(skin.playlistStyle.font == "Arial")

        #expect(skin.visColors.count == 24)
        #expect(skin.visColors[1] == WinampColor(red: 24, green: 33, blue: 41))
        #expect(skin.visColors[2] == WinampColor(red: 255, green: 1, blue: 2))
        #expect(skin.visColors[3] == WinampVisColors.minidiscGold[3])

        #expect(skin.regions["normal"]?.count == 2)
        #expect(skin.regions["normal"]?[1].last == CGPoint(x: 0, y: 116))
        #expect(skin.regions["windowshade"]?.first?.count == 4)
    }

    @Test func spritesOutsideASmallerSheetAreNil() throws {
        // Many real eqmain.bmp files stop at 292 pixels, before the graph strip.
        var zip = TestZipWriter()
        zip.add("eqmain.bmp", makeBMP(width: 275, height: 292) { _, _ in blue })
        let skin = try WinampSkin.load(data: zip.archive(), name: "Short", fallback: try WinampSkin.bundled())
        #expect(skin.image(for: WinampSprites.equalizerBackground) != nil)
        #expect(skin.image(for: WinampSprites.equalizerPreampLine) == nil)
    }

    @Test func missingSheetsFailWithoutAFallback() {
        let data = makeSkinArchive(omitting: [.cbuttons, .numbers, .numsEx, .balance])
        #expect(throws: WinampSkin.LoadError.missingSheets([.cbuttons, .numbers])) {
            try WinampSkin.load(data: data, name: "Broken")
        }
    }

    @Test func missingSheetsComeFromTheFallback() throws {
        let fallback = try WinampSkin.bundled()
        let data = makeSkinArchive(omitting: [.cbuttons, .numsEx, .balance])
        let skin = try WinampSkin.load(data: data, name: "Partial", fallback: fallback)
        #expect(skin.missingSheets.isEmpty)
        // The skin's own numbers.bmp wins, so the fallback's nums_ex isn't mixed in.
        #expect(!skin.usesExtendedNumbers)
        // Balance falls back to the skin's own volume.bmp, as in Winamp.
        #expect(skin.sheets[.balance] === skin.sheets[.volume])
        let play = try #require(skin.image(for: WinampSprites.play.normal))
        #expect(play.width == 23)
        #expect(skin.playlistStyle == fallback.playlistStyle)
        #expect(skin.visColors == fallback.visColors)
    }

    @Test func parsesLooseTextFiles() {
        let style = WinampPlaylistStyle.parse("[text]\nNormal = 00ff00\nCurrent=#zzzzzz\n")
        #expect(style.normal == WinampColor(red: 0, green: 255, blue: 0))
        #expect(style.current == WinampPlaylistStyle.minidiscGold.current)
        #expect(WinampColor(hex: "#12345") == nil)
        #expect(WinampVisColors.parse("").count == 24)
        #expect(WinampRegions.parse("[Normal]\nNumPoints=3\nPointList=1,2\n").isEmpty)
    }

    @Test func glyphLookupFollowsTheTextGrid() {
        #expect(WinampSprites.glyph(for: "a") == WinampSprite(.text, 0, 0, 5, 6))
        #expect(WinampSprites.glyph(for: "Z") == WinampSprite(.text, 125, 0, 5, 6))
        #expect(WinampSprites.glyph(for: "5") == WinampSprite(.text, 25, 6, 5, 6))
        #expect(WinampSprites.glyph(for: "#") == WinampSprite(.text, 150, 6, 5, 6))
        #expect(WinampSprites.glyph(for: "?") == WinampSprite(.text, 15, 12, 5, 6))
        #expect(WinampSprites.glyph(for: "€") == WinampSprites.glyph(for: " "))
        #expect(WinampSprites.digit(7) == WinampSprite(.numbers, 63, 0, 9, 13))
        #expect(WinampSprites.digit(3, extended: true) == WinampSprite(.numsEx, 27, 0, 9, 13))
        #expect(WinampSprites.volumeBackground(frame: 99) == WinampSprites.volumeBackground(frame: 27))
    }

    @Test func everySpriteFitsItsClassicSheet() {
        for sprite in WinampSprites.all {
            let size = sprite.sheet.classicSize
            #expect(sprite.x >= 0 && sprite.y >= 0 && sprite.x + sprite.width <= size.width && sprite.y + sprite.height <= size.height,
                    "\(sprite)")
        }
    }

    @Test func bundledMinidiscGoldHasEverySprite() throws {
        let skin = try WinampSkin.bundled()
        #expect(skin.name == "MinidiscGold")
        #expect(skin.missingSheets.isEmpty)
        #expect(Set(skin.sheets.keys) == Set(WinampSpriteSheet.allCases))
        for sheet in WinampSpriteSheet.allCases {
            let image = try #require(skin.sheets[sheet])
            #expect(image.width == sheet.classicSize.width && image.height == sheet.classicSize.height, "\(sheet)")
        }
        for sprite in WinampSprites.all {
            let image = skin.image(for: sprite)
            #expect(image?.width == sprite.width && image?.height == sprite.height, "\(sprite)")
        }
        #expect(skin.visColors.count == 24)
        #expect(skin.visColors == WinampVisColors.minidiscGold)
        #expect(skin.playlistStyle == .minidiscGold)
    }
}
