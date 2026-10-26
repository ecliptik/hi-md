import CoreGraphics
import Foundation

/// The bitmaps in a classic Winamp 2 skin, with the size each has in the original skin format.
nonisolated enum WinampSpriteSheet: String, CaseIterable, Sendable {
    case main
    case cbuttons
    case titlebar
    case posbar
    case volume
    case balance
    case numbers
    case numsEx = "nums_ex"
    case text
    case playpaus
    case monoster
    case shufrep
    case eqmain
    case pledit

    var fileName: String { rawValue + ".bmp" }

    /// The size the classic coordinates assume. Real skins are sometimes larger (an `eqmain`
    /// without the graph strip is 275×292); sprites outside a smaller bitmap come out nil.
    var classicSize: (width: Int, height: Int) {
        switch self {
        case .main: (275, 116)
        case .cbuttons: (136, 36)
        case .titlebar: (344, 87)
        case .posbar: (307, 10)
        case .volume: (68, 433)
        case .balance: (47, 433)
        case .numbers: (99, 13)
        case .numsEx: (108, 13)
        case .text: (155, 18)
        case .playpaus: (42, 9)
        case .monoster: (58, 24)
        case .shufrep: (92, 85)
        case .eqmain: (275, 315)
        case .pledit: (280, 186)
        }
    }

    /// A skin needs one of `numbers` or `nums_ex`, and Winamp draws the balance slider from
    /// `volume` when `balance` is missing.
    static let required: [WinampSpriteSheet] = allCases.filter { $0 != .numsEx && $0 != .balance && $0 != .numbers }
}

/// A rectangle in one sprite sheet, in pixels from the top-left corner.
nonisolated struct WinampSprite: Sendable, Hashable {
    let sheet: WinampSpriteSheet
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init(_ sheet: WinampSpriteSheet, _ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.sheet = sheet
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// A two-state button sprite.
nonisolated struct WinampButtonSprites: Sendable, Hashable {
    let normal: WinampSprite
    let pressed: WinampSprite
}

/// A toggle such as Shuffle: off and on, each normal and pressed.
nonisolated struct WinampToggleSprites: Sendable, Hashable {
    let off: WinampButtonSprites
    let on: WinampButtonSprites
}

/// Sprite rectangles in the classic Winamp 2 skin format. The coordinates are the format's public
/// layout, as documented by the Webamp project (MIT); no Webamp code is used.
nonisolated enum WinampSprites {
    // MARK: main.bmp

    static let mainBackground = WinampSprite(.main, 0, 0, 275, 116)

    // MARK: cbuttons.bmp

    static let previous = button(.cbuttons, x: 0, width: 23, height: 18)
    static let play = button(.cbuttons, x: 23, width: 23, height: 18)
    static let pause = button(.cbuttons, x: 46, width: 23, height: 18)
    static let stop = button(.cbuttons, x: 69, width: 23, height: 18)
    static let next = button(.cbuttons, x: 92, width: 22, height: 18)
    static let eject = button(.cbuttons, x: 114, width: 22, height: 16)
    static let transport = [previous, play, pause, stop, next, eject]

    // MARK: titlebar.bmp

    static let titleBarActive = WinampSprite(.titlebar, 27, 0, 275, 14)
    static let titleBarInactive = WinampSprite(.titlebar, 27, 15, 275, 14)
    static let shadeBarActive = WinampSprite(.titlebar, 27, 29, 275, 14)
    static let shadeBarInactive = WinampSprite(.titlebar, 27, 42, 275, 14)
    static let options = WinampButtonSprites(normal: WinampSprite(.titlebar, 0, 0, 9, 9),
                                             pressed: WinampSprite(.titlebar, 0, 9, 9, 9))
    static let minimize = WinampButtonSprites(normal: WinampSprite(.titlebar, 9, 0, 9, 9),
                                              pressed: WinampSprite(.titlebar, 9, 9, 9, 9))
    static let close = WinampButtonSprites(normal: WinampSprite(.titlebar, 18, 0, 9, 9),
                                           pressed: WinampSprite(.titlebar, 18, 9, 9, 9))
    static let shade = WinampButtonSprites(normal: WinampSprite(.titlebar, 0, 18, 9, 9),
                                           pressed: WinampSprite(.titlebar, 9, 18, 9, 9))
    static let unshade = WinampButtonSprites(normal: WinampSprite(.titlebar, 0, 27, 9, 9),
                                             pressed: WinampSprite(.titlebar, 9, 27, 9, 9))
    static let clutterBar = WinampSprite(.titlebar, 304, 0, 8, 43)
    static let clutterBarDisabled = WinampSprite(.titlebar, 312, 0, 8, 43)

    // MARK: posbar.bmp

    static let seekBackground = WinampSprite(.posbar, 0, 0, 248, 10)
    static let seekThumb = WinampButtonSprites(normal: WinampSprite(.posbar, 248, 0, 29, 10),
                                               pressed: WinampSprite(.posbar, 278, 0, 29, 10))

    // MARK: volume.bmp and balance.bmp

    /// 28 backgrounds, from empty to full, stacked 15 pixels apart.
    static let sliderFrameCount = 28
    static func volumeBackground(frame: Int) -> WinampSprite {
        WinampSprite(.volume, 0, clampedFrame(frame) * 15, 68, 13)
    }
    static let volumeThumb = WinampButtonSprites(normal: WinampSprite(.volume, 15, 422, 14, 11),
                                                 pressed: WinampSprite(.volume, 0, 422, 14, 11))
    /// Frame 0 is centred; the frame grows towards either side.
    static func balanceBackground(frame: Int) -> WinampSprite {
        WinampSprite(.balance, 9, clampedFrame(frame) * 15, 38, 13)
    }
    static let balanceThumb = WinampButtonSprites(normal: WinampSprite(.balance, 15, 422, 14, 11),
                                                  pressed: WinampSprite(.balance, 0, 422, 14, 11))

    // MARK: numbers.bmp and nums_ex.bmp

    /// A 9×13 time digit. `nums_ex` adds a blank and a minus sign after the digits.
    static func digit(_ value: Int, extended: Bool = false) -> WinampSprite {
        WinampSprite(extended ? .numsEx : .numbers, min(max(value, 0), 9) * 9, 0, 9, 13)
    }
    static let digitBlank = WinampSprite(.numsEx, 90, 0, 9, 13)
    static let digitMinus = WinampSprite(.numsEx, 99, 0, 9, 13)
    /// `numbers.bmp` has no minus glyph: the minus is drawn from a 5×1 strip of the "2".
    static let numbersMinus = WinampSprite(.numbers, 20, 6, 5, 1)

    // MARK: text.bmp

    static let glyphWidth = 5
    static let glyphHeight = 6

    /// The 5×6 glyph for `character`; unknown characters draw as a space.
    static func glyph(for character: Character) -> WinampSprite {
        let cell = glyphCell(for: character) ?? glyphCell(for: " ")!
        return WinampSprite(.text, cell.column * glyphWidth, cell.row * glyphHeight, glyphWidth, glyphHeight)
    }

    /// Row and column of a character in `text.bmp`'s 31×3 grid.
    static func glyphCell(for character: Character) -> (row: Int, column: Int)? {
        let lower = Character(character.lowercased())
        if let ascii = lower.asciiValue {
            if (97...122).contains(ascii) { return (0, Int(ascii) - 97) }
            if (48...57).contains(ascii) { return (1, Int(ascii) - 48) }
        }
        return glyphPunctuation[lower]
    }

    private static let glyphPunctuation: [Character: (row: Int, column: Int)] = [
        "\"": (0, 26), "@": (0, 27), " ": (0, 30),
        "…": (1, 10), ".": (1, 11), ":": (1, 12), "(": (1, 13), ")": (1, 14), "-": (1, 15),
        "'": (1, 16), "!": (1, 17), "_": (1, 18), "+": (1, 19), "\\": (1, 20), "/": (1, 21),
        "[": (1, 22), "]": (1, 23), "^": (1, 24), "&": (1, 25), "%": (1, 26), ",": (1, 27),
        "=": (1, 28), "$": (1, 29), "#": (1, 30),
        "å": (2, 0), "ö": (2, 1), "ä": (2, 2), "?": (2, 3), "*": (2, 4),
        // Stand-ins the format has no glyph for.
        "<": (1, 22), ">": (1, 23), "{": (1, 13), "}": (1, 14), "`": (1, 16), "~": (1, 15),
        "|": (1, 21), ";": (1, 12),
    ]

    // MARK: playpaus.bmp

    static let playingIndicator = WinampSprite(.playpaus, 0, 0, 9, 9)
    static let pausedIndicator = WinampSprite(.playpaus, 9, 0, 9, 9)
    static let stoppedIndicator = WinampSprite(.playpaus, 18, 0, 9, 9)
    /// The 3-pixel strip left of the indicator: lit while audio is flowing, dark while buffering.
    static let workingIndicator = WinampSprite(.playpaus, 39, 0, 3, 9)
    static let notWorkingIndicator = WinampSprite(.playpaus, 36, 0, 3, 9)

    // MARK: monoster.bmp

    static let stereoOn = WinampSprite(.monoster, 0, 0, 29, 12)
    static let stereoOff = WinampSprite(.monoster, 0, 12, 29, 12)
    static let monoOn = WinampSprite(.monoster, 29, 0, 27, 12)
    static let monoOff = WinampSprite(.monoster, 29, 12, 27, 12)

    // MARK: shufrep.bmp

    static let repeatToggle = toggle(x: 0, width: 28, height: 15, rowHeight: 15, onOffset: 30)
    static let shuffleToggle = toggle(x: 28, width: 47, height: 15, rowHeight: 15, onOffset: 30)
    static let equalizerToggle = WinampToggleSprites(
        off: WinampButtonSprites(normal: WinampSprite(.shufrep, 0, 61, 23, 12), pressed: WinampSprite(.shufrep, 46, 61, 23, 12)),
        on: WinampButtonSprites(normal: WinampSprite(.shufrep, 0, 73, 23, 12), pressed: WinampSprite(.shufrep, 46, 73, 23, 12))
    )
    static let playlistToggle = WinampToggleSprites(
        off: WinampButtonSprites(normal: WinampSprite(.shufrep, 23, 61, 23, 12), pressed: WinampSprite(.shufrep, 69, 61, 23, 12)),
        on: WinampButtonSprites(normal: WinampSprite(.shufrep, 23, 73, 23, 12), pressed: WinampSprite(.shufrep, 69, 73, 23, 12))
    )

    // MARK: eqmain.bmp

    static let equalizerBackground = WinampSprite(.eqmain, 0, 0, 275, 116)
    static let equalizerTitleBarActive = WinampSprite(.eqmain, 0, 134, 275, 14)
    static let equalizerTitleBarInactive = WinampSprite(.eqmain, 0, 149, 275, 14)
    static let equalizerClose = WinampButtonSprites(normal: WinampSprite(.eqmain, 0, 116, 9, 9),
                                                    pressed: WinampSprite(.eqmain, 0, 125, 9, 9))
    static let equalizerOn = WinampToggleSprites(
        off: WinampButtonSprites(normal: WinampSprite(.eqmain, 10, 119, 26, 12), pressed: WinampSprite(.eqmain, 128, 119, 26, 12)),
        on: WinampButtonSprites(normal: WinampSprite(.eqmain, 69, 119, 26, 12), pressed: WinampSprite(.eqmain, 187, 119, 26, 12))
    )
    static let equalizerAuto = WinampToggleSprites(
        off: WinampButtonSprites(normal: WinampSprite(.eqmain, 36, 119, 32, 12), pressed: WinampSprite(.eqmain, 154, 119, 32, 12)),
        on: WinampButtonSprites(normal: WinampSprite(.eqmain, 95, 119, 32, 12), pressed: WinampSprite(.eqmain, 213, 119, 32, 12))
    )
    static let equalizerPresets = WinampButtonSprites(normal: WinampSprite(.eqmain, 224, 164, 44, 12),
                                                      pressed: WinampSprite(.eqmain, 224, 176, 44, 12))
    /// 28 slider fills, two rows of 14, from -12 dB to +12 dB.
    static func equalizerSliderBackground(frame: Int) -> WinampSprite {
        let frame = clampedFrame(frame)
        return WinampSprite(.eqmain, 13 + (frame % 14) * 15, 164 + (frame / 14) * 65, 14, 63)
    }
    static let equalizerSliderThumb = WinampButtonSprites(normal: WinampSprite(.eqmain, 0, 164, 11, 11),
                                                          pressed: WinampSprite(.eqmain, 0, 176, 11, 11))
    static let equalizerGraphBackground = WinampSprite(.eqmain, 0, 294, 113, 19)
    /// One pixel per row: the colours of the response curve, top to bottom.
    static let equalizerGraphLineColors = WinampSprite(.eqmain, 115, 294, 1, 19)
    static let equalizerPreampLine = WinampSprite(.eqmain, 0, 314, 113, 1)

    // MARK: pledit.bmp

    static let playlistTopLeftActive = WinampSprite(.pledit, 0, 0, 25, 20)
    static let playlistTitleActive = WinampSprite(.pledit, 26, 0, 100, 20)
    static let playlistTopTileActive = WinampSprite(.pledit, 127, 0, 25, 20)
    static let playlistTopRightActive = WinampSprite(.pledit, 153, 0, 25, 20)
    static let playlistTopLeftInactive = WinampSprite(.pledit, 0, 21, 25, 20)
    static let playlistTitleInactive = WinampSprite(.pledit, 26, 21, 100, 20)
    static let playlistTopTileInactive = WinampSprite(.pledit, 127, 21, 25, 20)
    static let playlistTopRightInactive = WinampSprite(.pledit, 153, 21, 25, 20)
    static let playlistLeftTile = WinampSprite(.pledit, 0, 42, 12, 29)
    static let playlistRightTile = WinampSprite(.pledit, 31, 42, 20, 29)
    static let playlistBottomLeft = WinampSprite(.pledit, 0, 72, 125, 38)
    static let playlistBottomRight = WinampSprite(.pledit, 126, 72, 150, 38)
    static let playlistBottomTile = WinampSprite(.pledit, 179, 0, 25, 38)
    static let playlistVisualizerBackground = WinampSprite(.pledit, 205, 0, 75, 38)
    static let playlistScrollThumb = WinampButtonSprites(normal: WinampSprite(.pledit, 52, 53, 8, 18),
                                                         pressed: WinampSprite(.pledit, 61, 53, 8, 18))
    /// Pressed states of the buttons painted into the top-right corner.
    static let playlistClosePressed = WinampSprite(.pledit, 52, 42, 9, 9)
    static let playlistShadePressed = WinampSprite(.pledit, 62, 42, 9, 9)

    /// The +ADD, −REM, SEL, MISC and LIST pop-up menus: each item normal and pressed, plus the
    /// strip drawn down the menu's left edge.
    nonisolated struct PlaylistMenu: Sendable, Hashable {
        let items: [WinampButtonSprites]
        let bar: WinampSprite
    }

    static let playlistAddMenu = menu(x: 0, items: 3, barX: 48)       // URL, folder, file
    static let playlistRemoveMenu = menu(x: 54, items: 4, barX: 100)  // all, crop, selected, misc
    static let playlistSelectMenu = menu(x: 104, items: 3, barX: 150) // invert, none, all
    static let playlistMiscMenu = menu(x: 154, items: 3, barX: 200)   // sort, info, options
    static let playlistListMenu = menu(x: 204, items: 3, barX: 250)   // new, save, load

    // MARK: Every sprite

    /// Every fixed sprite, for validating a skin. Frame-based sprites are listed at both ends.
    static var all: [WinampSprite] {
        var sprites: [WinampSprite] = [
            mainBackground, titleBarActive, titleBarInactive, shadeBarActive, shadeBarInactive,
            clutterBar, clutterBarDisabled, seekBackground,
            playingIndicator, pausedIndicator, stoppedIndicator, workingIndicator, notWorkingIndicator,
            stereoOn, stereoOff, monoOn, monoOff,
            equalizerBackground, equalizerTitleBarActive, equalizerTitleBarInactive,
            equalizerGraphBackground, equalizerGraphLineColors, equalizerPreampLine,
            playlistTopLeftActive, playlistTitleActive, playlistTopTileActive, playlistTopRightActive,
            playlistTopLeftInactive, playlistTitleInactive, playlistTopTileInactive, playlistTopRightInactive,
            playlistLeftTile, playlistRightTile, playlistBottomLeft, playlistBottomRight, playlistBottomTile,
            playlistVisualizerBackground, playlistClosePressed, playlistShadePressed,
            volumeBackground(frame: 0), volumeBackground(frame: sliderFrameCount - 1),
            balanceBackground(frame: 0), balanceBackground(frame: sliderFrameCount - 1),
            equalizerSliderBackground(frame: 0), equalizerSliderBackground(frame: sliderFrameCount - 1),
            digitBlank, digitMinus, numbersMinus,
        ]
        let buttons = transport + [options, minimize, close, shade, unshade, seekThumb, volumeThumb, balanceThumb,
                                   equalizerClose, equalizerPresets, equalizerSliderThumb, playlistScrollThumb]
        let toggles = [repeatToggle, shuffleToggle, equalizerToggle, playlistToggle, equalizerOn, equalizerAuto]
        let menus = [playlistAddMenu, playlistRemoveMenu, playlistSelectMenu, playlistMiscMenu, playlistListMenu]
        sprites += buttons.flatMap { [$0.normal, $0.pressed] }
        sprites += toggles.flatMap { [$0.off.normal, $0.off.pressed, $0.on.normal, $0.on.pressed] }
        sprites += menus.flatMap { $0.items.flatMap { [$0.normal, $0.pressed] } + [$0.bar] }
        sprites += (0...9).flatMap { [digit($0), digit($0, extended: true)] }
        for row in 0..<3 {
            for column in 0..<31 { sprites.append(WinampSprite(.text, column * glyphWidth, row * glyphHeight, glyphWidth, glyphHeight)) }
        }
        return sprites
    }

    // MARK: Builders

    private static func clampedFrame(_ frame: Int) -> Int {
        min(max(frame, 0), sliderFrameCount - 1)
    }

    private static func button(_ sheet: WinampSpriteSheet, x: Int, width: Int, height: Int) -> WinampButtonSprites {
        WinampButtonSprites(normal: WinampSprite(sheet, x, 0, width, height),
                            pressed: WinampSprite(sheet, x, height, width, height))
    }

    private static func toggle(x: Int, width: Int, height: Int, rowHeight: Int, onOffset: Int) -> WinampToggleSprites {
        WinampToggleSprites(
            off: WinampButtonSprites(normal: WinampSprite(.shufrep, x, 0, width, height),
                                     pressed: WinampSprite(.shufrep, x, rowHeight, width, height)),
            on: WinampButtonSprites(normal: WinampSprite(.shufrep, x, onOffset, width, height),
                                    pressed: WinampSprite(.shufrep, x, onOffset + rowHeight, width, height))
        )
    }

    private static func menu(x: Int, items: Int, barX: Int) -> PlaylistMenu {
        PlaylistMenu(
            items: (0..<items).map { index in
                WinampButtonSprites(normal: WinampSprite(.pledit, x, 111 + index * 19, 22, 18),
                                    pressed: WinampSprite(.pledit, x + 23, 111 + index * 19, 22, 18))
            },
            bar: WinampSprite(.pledit, barX, 111, 3, items * 18)
        )
    }
}

/// Where the classic main window draws each element, in its 275×116 coordinate space.
nonisolated enum WinampMainLayout {
    static let size = CGSize(width: 275, height: 116)
    static let titleBar = CGRect(x: 0, y: 0, width: 275, height: 14)
    static let clutterBar = CGPoint(x: 10, y: 22)
    static let playbackIndicator = CGPoint(x: 26, y: 28)
    static let workingIndicator = CGPoint(x: 24, y: 28)
    /// Minutes and seconds digits; the minus sign sits at x 36 (y 32 for `numbers.bmp`).
    static let timeDigits = [CGPoint(x: 48, y: 26), CGPoint(x: 60, y: 26), CGPoint(x: 78, y: 26), CGPoint(x: 90, y: 26)]
    static let timeMinus = CGPoint(x: 36, y: 26)
    static let visualizer = CGRect(x: 24, y: 43, width: 76, height: 16)
    static let title = CGRect(x: 111, y: 27, width: 154, height: 6)
    static let kbps = CGRect(x: 111, y: 43, width: 15, height: 6)
    static let khz = CGRect(x: 156, y: 43, width: 10, height: 6)
    static let mono = CGPoint(x: 212, y: 41)
    static let stereo = CGPoint(x: 239, y: 41)
    static let volume = CGRect(x: 107, y: 57, width: 68, height: 13)
    static let balance = CGRect(x: 177, y: 57, width: 38, height: 13)
    static let equalizerToggle = CGPoint(x: 219, y: 58)
    static let playlistToggle = CGPoint(x: 242, y: 58)
    static let seekBar = CGRect(x: 16, y: 72, width: 248, height: 10)
    static let previous = CGPoint(x: 16, y: 88)
    static let play = CGPoint(x: 39, y: 88)
    static let pause = CGPoint(x: 62, y: 88)
    static let stop = CGPoint(x: 85, y: 88)
    static let next = CGPoint(x: 108, y: 88)
    static let eject = CGPoint(x: 136, y: 89)
    static let shuffle = CGPoint(x: 164, y: 89)
    static let repeatToggle = CGPoint(x: 210, y: 89)
    static let options = CGPoint(x: 6, y: 3)
    static let minimize = CGPoint(x: 244, y: 3)
    static let shade = CGPoint(x: 254, y: 3)
    static let close = CGPoint(x: 264, y: 3)
}
