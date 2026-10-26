import CoreGraphics
import Foundation
import ImageIO

/// An sRGB colour from a skin's text files.
nonisolated struct WinampColor: Sendable, Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `#RRGGBB` or `RRGGBB`, ignoring anything after the six digits.
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }.prefix(6)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

/// `pledit.txt`: the playlist window's text colours and font.
nonisolated struct WinampPlaylistStyle: Sendable, Hashable {
    var normal: WinampColor
    var current: WinampColor
    var normalBackground: WinampColor
    var selectedBackground: WinampColor
    var font: String

    static let minidiscGold = WinampPlaylistStyle(
        normal: WinampColor(red: 0xD9, green: 0xB0, blue: 0x4C),
        current: WinampColor(red: 0xFF, green: 0xF1, blue: 0xC2),
        normalBackground: WinampColor(red: 0x0E, green: 0x0C, blue: 0x09),
        selectedBackground: WinampColor(red: 0x4A, green: 0x37, blue: 0x10),
        font: "Helvetica"
    )

    /// INI-style `[Text]` keys, case-insensitive. Missing or malformed values keep `defaults`.
    static func parse(_ text: String, defaults: WinampPlaylistStyle = .minidiscGold) -> WinampPlaylistStyle {
        let values = WinampIni.parse(text)["text"] ?? [:]
        var style = defaults
        if let color = values["normal"].flatMap(WinampColor.init(hex:)) { style.normal = color }
        if let color = values["current"].flatMap(WinampColor.init(hex:)) { style.current = color }
        if let color = values["normalbg"].flatMap(WinampColor.init(hex:)) { style.normalBackground = color }
        if let color = values["selectedbg"].flatMap(WinampColor.init(hex:)) { style.selectedBackground = color }
        if let font = values["font"], !font.isEmpty { style.font = font }
        return style
    }
}

/// `viscolor.txt`: 24 colours. 0 is the background, 1 the dots, 2–17 the spectrum from top to
/// bottom, 18–22 the oscilloscope from dim to bright, and 23 the peak markers.
nonisolated enum WinampVisColors {
    static let count = 24

    static let minidiscGold: [WinampColor] = {
        var colors = [WinampColor(red: 0x08, green: 0x07, blue: 0x05), WinampColor(red: 0x2A, green: 0x22, blue: 0x12)]
        for step in 0..<16 {
            // Pale gold at the top of the bars to deep amber at the bottom.
            let t = Double(step) / 15
            colors.append(WinampColor(red: UInt8(255 - 70 * t), green: UInt8(226 - 130 * t), blue: UInt8(130 - 115 * t)))
        }
        for step in 0..<5 {
            let t = Double(step) / 4
            colors.append(WinampColor(red: UInt8(120 + 135 * t), green: UInt8(84 + 130 * t), blue: UInt8(20 + 100 * t)))
        }
        colors.append(WinampColor(red: 0xFF, green: 0xF4, blue: 0xD6))
        return colors
    }()

    /// One `r,g,b` triple per line, comments allowed. Missing lines keep `defaults`.
    static func parse(_ text: String, defaults: [WinampColor] = minidiscGold) -> [WinampColor] {
        var colors = defaults.count == count ? defaults : minidiscGold
        var index = 0
        for line in text.split(whereSeparator: \.isNewline) where index < count {
            let content = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? line
            let numbers = content.split { !$0.isNumber }.compactMap { Int($0) }
            guard numbers.count >= 3 else { continue }
            let channel = { (value: Int) in UInt8(min(max(value, 0), 255)) }
            colors[index] = WinampColor(red: channel(numbers[0]), green: channel(numbers[1]), blue: channel(numbers[2]))
            index += 1
        }
        return colors
    }
}

/// `region.txt`: window outlines as polygons, for non-rectangular windows. Keyed by section,
/// lowercased: `normal`, `windowshade`, `equalizer` and `equalizerws`.
nonisolated enum WinampRegions {
    static func parse(_ text: String) -> [String: [[CGPoint]]] {
        var regions: [String: [[CGPoint]]] = [:]
        for (section, values) in WinampIni.parse(text) {
            let counts = numbers(values["numpoints"] ?? "")
            let coordinates = numbers(values["pointlist"] ?? "")
            var polygons: [[CGPoint]] = []
            var cursor = 0
            var isValid = true
            for count in counts where count > 0 {
                // Compared by division so a huge count can't overflow; a section that claims more
                // points than it lists is dropped whole.
                guard count <= (coordinates.count - cursor) / 2 else {
                    isValid = false
                    break
                }
                polygons.append((0..<count).map {
                    CGPoint(x: coordinates[cursor + $0 * 2], y: coordinates[cursor + $0 * 2 + 1])
                })
                cursor += count * 2
            }
            if isValid, !polygons.isEmpty { regions[section] = polygons }
        }
        return regions
    }

    private static func numbers(_ text: String) -> [Int] {
        text.split { !$0.isNumber && $0 != "-" }.compactMap { Int($0) }
    }
}

/// The small INI dialect skins use: `[Section]`, `key=value`, `;` or `//` comments.
nonisolated enum WinampIni {
    static func parse(_ text: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var current = ""
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("//") { continue }
            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                current = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces).lowercased()
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            sections[current, default: [:]][key] = value
        }
        return sections
    }
}

/// A classic Winamp 2 / XMMS skin: the sprite sheets from a `.wsz` and its text files.
nonisolated struct WinampSkin: @unchecked Sendable {
    enum LoadError: Error, Equatable {
        case missingSheets([WinampSpriteSheet])
        case missingBundledSkin
    }

    static let bundledSkinName = "MinidiscGold"

    let name: String
    let sheets: [WinampSpriteSheet: CGImage]
    let playlistStyle: WinampPlaylistStyle
    let visColors: [WinampColor]
    let regions: [String: [[CGPoint]]]

    /// Required sheets the archive didn't have and the fallback skin didn't supply.
    var missingSheets: [WinampSpriteSheet] {
        let missing = WinampSpriteSheet.required.filter { sheets[$0] == nil }
        return sheets[.numbers] == nil && sheets[.numsEx] == nil ? missing + [.numbers] : missing
    }

    /// Digits come from `nums_ex` when the skin has it.
    var usesExtendedNumbers: Bool { sheets[.numsEx] != nil }

    /// Loads a `.wsz`. Sheets and text files the skin lacks come from `fallback`, the way Winamp
    /// fills gaps from its base skin. Unreadable BMPs fall back too rather than failing the skin.
    static func load(data: Data, name: String, fallback: WinampSkin? = nil) throws -> WinampSkin {
        let archive = try ZipArchive(data: data)
        var sheets = fallback?.sheets ?? [:]
        for sheet in WinampSpriteSheet.allCases {
            guard let bitmap = try? archive.contents(named: sheet.fileName) else { continue }
            if let image = image(fromBMP: bitmap) {
                sheets[sheet] = image
            }
        }
        // A skin with its own numbers.bmp but no nums_ex.bmp must not inherit the fallback's nums_ex.
        if archive.entry(named: WinampSpriteSheet.numbers.fileName) != nil,
           archive.entry(named: WinampSpriteSheet.numsEx.fileName) == nil {
            sheets[.numsEx] = nil
        }
        // Winamp draws the balance slider from the skin's own volume.bmp when balance.bmp is missing.
        if archive.entry(named: WinampSpriteSheet.balance.fileName) == nil,
           archive.entry(named: WinampSpriteSheet.volume.fileName) != nil || sheets[.balance] == nil {
            sheets[.balance] = sheets[.volume]
        }

        let text = { (file: String) -> String? in
            (try? archive.contents(named: file)).map { M3UPlaylist.text(from: $0) }
        }
        let skin = WinampSkin(
            name: name,
            sheets: sheets,
            playlistStyle: text("pledit.txt").map { WinampPlaylistStyle.parse($0, defaults: fallback?.playlistStyle ?? .minidiscGold) }
                ?? fallback?.playlistStyle ?? .minidiscGold,
            visColors: text("viscolor.txt").map { WinampVisColors.parse($0, defaults: fallback?.visColors ?? WinampVisColors.minidiscGold) }
                ?? fallback?.visColors ?? WinampVisColors.minidiscGold,
            regions: text("region.txt").map(WinampRegions.parse) ?? [:]
        )
        let missing = skin.missingSheets
        guard missing.isEmpty else { throw LoadError.missingSheets(missing) }
        return skin
    }

    static func load(contentsOf url: URL, fallback: WinampSkin? = nil) throws -> WinampSkin {
        try load(data: Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent, fallback: fallback)
    }

    /// The original "Minidisc Gold" skin shipped with the app.
    static func bundled(in bundle: Bundle = .main) throws -> WinampSkin {
        guard let url = bundle.url(forResource: bundledSkinName, withExtension: "wsz") else {
            throw LoadError.missingBundledSkin
        }
        return try load(contentsOf: url)
    }

    /// The sprite cut from its sheet, or nil if the sheet is missing or too small for it.
    func image(for sprite: WinampSprite) -> CGImage? {
        guard let sheet = sheets[sprite.sheet] else { return nil }
        guard sprite.x >= 0, sprite.y >= 0,
              sprite.x + sprite.width <= sheet.width, sprite.y + sprite.height <= sheet.height else { return nil }
        return sheet.cropping(to: sprite.rect)
    }

    /// ImageIO reads every BMP flavour skins use: 8-bit palettes, 24-bit and RLE.
    static func image(fromBMP data: Data) -> CGImage? {
        let options = [kCGImageSourceTypeIdentifierHint as String: "com.microsoft.bmp"] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
