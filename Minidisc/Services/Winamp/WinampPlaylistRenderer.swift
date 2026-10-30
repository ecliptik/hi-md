import CoreGraphics
import CoreText
import Foundation

/// Everything the playlist window draws, as plain values.
nonisolated struct WinampPlaylistDisplayState: Sendable, Hashable {
    struct Row: Sendable, Hashable {
        var title: String
        var duration: String
        var isSelected = false
        var isCurrent = false
        /// Added by Autoplay after the listener's own songs; drawn dimmer.
        var isAutoplay = false
        /// The first Autoplay song: a dotted line above it marks where the playlist ends.
        var startsAutoplay = false
    }

    var size = WinampPlaylistSize.standard.pixelSize
    var isActive = true
    var isShaded = false
    /// Only the rows on screen, from `firstRow`.
    var rows: [Row] = []
    var firstRow = 0
    var totalRows = 0
    /// The row with the keyboard focus, drawn with Winamp's thin outline.
    var focusedRow: Int?
    var runningTime = ""
    var miniTime = ""
    var pressed: WinampPlaylistControl?
    var openMenu: WinampPlaylistMenuKind?
    var highlightedMenuItem: WinampPlaylistMenuItem?
    /// The shaded bar's text: the playing song's title.
    var shadeTitle = ""
}

/// Draws the playlist window from `pledit.bmp` and the colours and font in `pledit.txt`.
nonisolated enum WinampPlaylistRenderer {
    /// The playlist font's size in window pixels; rows are 13 pixels apart.
    static let fontSize: CGFloat = 9.5
    static let textBaseline: CGFloat = 10

    static func render(_ state: WinampPlaylistDisplayState, skin: WinampSkin, sprites: WinampSpriteCache,
                       scale: CGFloat) -> CGImage? {
        let size = state.isShaded ? WinampPlaylistLayout.shadeSize(width: state.size.width) : state.size
        guard let canvas = WinampCanvas.make(size: size, scale: scale, sprites: sprites) else { return nil }
        if state.isShaded {
            drawShade(state, skin: skin, canvas: canvas)
        } else {
            drawWindow(state, skin: skin, canvas: canvas)
        }
        return canvas.makeImage()
    }

    // MARK: Window

    private static func drawWindow(_ state: WinampPlaylistDisplayState, skin: WinampSkin, canvas: WinampCanvas) {
        typealias Layout = WinampPlaylistLayout
        let size = state.size
        let style = skin.playlistStyle
        let list = Layout.list(in: size)
        canvas.fill(list, color: style.normalBackground)

        // Title bar: corners, the title centred, tiles between.
        let active = state.isActive
        canvas.tile(active ? WinampSprites.playlistTopTileActive : WinampSprites.playlistTopTileInactive,
                    in: CGRect(x: 25, y: 0, width: size.width - 50, height: Layout.titleHeight))
        let title = active ? WinampSprites.playlistTitleActive : WinampSprites.playlistTitleInactive
        canvas.draw(title, at: CGPoint(x: ((size.width - CGFloat(title.width)) / 2).rounded(.down), y: 0))
        canvas.draw(active ? WinampSprites.playlistTopLeftActive : WinampSprites.playlistTopLeftInactive, at: .zero)
        canvas.draw(active ? WinampSprites.playlistTopRightActive : WinampSprites.playlistTopRightInactive,
                    at: CGPoint(x: size.width - 25, y: 0))
        if state.pressed == .close { canvas.draw(WinampSprites.playlistClosePressed, at: Layout.close(in: size).origin) }
        if state.pressed == .shade { canvas.draw(WinampSprites.playlistShadePressed, at: Layout.shade(in: size).origin) }

        // Sides.
        canvas.tile(WinampSprites.playlistLeftTile, in: CGRect(x: 0, y: Layout.titleHeight, width: Layout.leftWidth, height: list.height))
        canvas.tile(WinampSprites.playlistRightTile,
                    in: CGRect(x: size.width - Layout.rightWidth, y: Layout.titleHeight, width: Layout.rightWidth, height: list.height))

        // Bottom: the left and right corners, tiles between, and the visualiser panel when wide.
        let bottomY = size.height - Layout.bottomHeight
        canvas.tile(WinampSprites.playlistBottomTile, in: CGRect(x: 125, y: bottomY, width: max(size.width - 275, 0), height: Layout.bottomHeight))
        canvas.draw(WinampSprites.playlistBottomLeft, at: CGPoint(x: 0, y: bottomY))
        if size.width >= 350 {
            canvas.draw(WinampSprites.playlistVisualizerBackground, at: CGPoint(x: size.width - 225, y: bottomY))
        }
        canvas.draw(WinampSprites.playlistBottomRight, at: CGPoint(x: size.width - 150, y: bottomY))

        drawRows(state, style: style, canvas: canvas)
        drawScrollThumb(state, canvas: canvas)
        canvas.drawGlyphs(state.runningTime, at: Layout.runningTime(in: size))
        canvas.drawGlyphs(state.miniTime, at: Layout.miniTime(in: size))
        if let kind = state.openMenu { drawMenu(kind, highlighted: state.highlightedMenuItem, size: size, canvas: canvas) }
    }

    private static func drawRows(_ state: WinampPlaylistDisplayState, style: WinampPlaylistStyle, canvas: WinampCanvas) {
        let list = WinampPlaylistLayout.list(in: state.size)
        let font = WinampCanvas.font(named: style.font, pixelSize: fontSize)
        let rowHeight = WinampPlaylistLayout.rowHeight
        canvas.withClip(to: list) {
            for (offset, row) in state.rows.enumerated() {
                let rect = CGRect(x: list.minX, y: list.minY + CGFloat(offset) * rowHeight, width: list.width, height: rowHeight)
                guard rect.minY < list.maxY else { break }
                if row.isSelected { canvas.fill(rect, color: style.selectedBackground) }
                if state.focusedRow == state.firstRow + offset {
                    drawFocusOutline(rect, color: style.normal, canvas: canvas)
                }
                if row.startsAutoplay {
                    var x = rect.minX + 3
                    while x < rect.maxX - 3 {
                        canvas.fill(CGRect(x: x, y: rect.minY, width: 1, height: 1), color: style.autoplay)
                        x += 2
                    }
                }
                let color = row.isCurrent ? style.current : row.isAutoplay ? style.autoplay : style.normal
                let durationWidth = CGFloat(max(row.duration.count, 4)) * 6 + 4
                canvas.drawString(row.duration, font: font, color: color, at: CGPoint(x: rect.maxX - durationWidth - 3, y: rect.minY),
                                  baseline: textBaseline, maxWidth: durationWidth, alignRight: true)
                canvas.drawString(row.title, font: font, color: color, at: CGPoint(x: rect.minX + 3, y: rect.minY),
                                  baseline: textBaseline, maxWidth: rect.width - durationWidth - 9)
            }
        }
    }

    /// A one-pixel dotted outline, Winamp's mark for the focused row.
    private static func drawFocusOutline(_ rect: CGRect, color: WinampColor, canvas: WinampCanvas) {
        var x = rect.minX
        while x < rect.maxX {
            canvas.fill(CGRect(x: x, y: rect.minY, width: 1, height: 1), color: color)
            canvas.fill(CGRect(x: x, y: rect.maxY - 1, width: 1, height: 1), color: color)
            x += 2
        }
        var y = rect.minY
        while y < rect.maxY {
            canvas.fill(CGRect(x: rect.minX, y: y, width: 1, height: 1), color: color)
            canvas.fill(CGRect(x: rect.maxX - 1, y: y, width: 1, height: 1), color: color)
            y += 2
        }
    }

    private static func drawScrollThumb(_ state: WinampPlaylistDisplayState, canvas: WinampCanvas) {
        let track = WinampPlaylistLayout.scrollTrack(in: state.size)
        let visible = WinampPlaylistLayout.visibleRows(in: state.size)
        let offset = WinampPlaylistScroll.thumbOffset(firstRow: state.firstRow, count: state.totalRows,
                                                      visible: visible, trackHeight: track.height)
        let sprites = WinampSprites.playlistScrollThumb
        canvas.draw(state.pressed == .scrollBar ? sprites.pressed : sprites.normal,
                    at: CGPoint(x: track.minX, y: track.minY + offset))
    }

    private static func drawMenu(_ kind: WinampPlaylistMenuKind, highlighted: WinampPlaylistMenuItem?,
                                 size: CGSize, canvas: WinampCanvas) {
        let sprites = kind.sprites
        canvas.draw(sprites.bar, in: WinampPlaylistLayout.menuBar(kind, in: size))
        for ((item, rect), itemSprites) in zip(zip(kind.items, WinampPlaylistLayout.menuItems(kind, in: size)), sprites.items) {
            canvas.draw(item == highlighted ? itemSprites.pressed : itemSprites.normal, in: rect)
        }
    }

    // MARK: Windowshade

    /// Winamp's shaded playlist: a 14-pixel bar with the playing song and its time.
    static func hasShadeSprites(_ skin: WinampSkin) -> Bool {
        skin.image(for: WinampSprites.playlistShadeLeft) != nil && skin.image(for: WinampSprites.playlistShadeRightActive) != nil
    }

    private static func drawShade(_ state: WinampPlaylistDisplayState, skin: WinampSkin, canvas: WinampCanvas) {
        let width = state.size.width
        canvas.tile(WinampSprites.playlistShadeTile, in: CGRect(x: 25, y: 0, width: max(width - 75, 0), height: 14))
        canvas.draw(WinampSprites.playlistShadeLeft, at: .zero)
        canvas.draw(state.isActive ? WinampSprites.playlistShadeRightActive : WinampSprites.playlistShadeRightInactive,
                    at: CGPoint(x: width - 50, y: 0))
        if state.pressed == .close { canvas.draw(WinampSprites.playlistClosePressed, at: WinampPlaylistLayout.shadeClose(width: width).origin) }
        if state.pressed == .shade { canvas.draw(WinampSprites.playlistUnshadePressed, at: WinampPlaylistLayout.shadeUnshade(width: width).origin) }
        let titleRect = WinampPlaylistLayout.shadeTitle(width: width)
        canvas.withClip(to: titleRect) {
            canvas.drawGlyphs(state.shadeTitle, at: titleRect.origin)
        }
        let time = state.miniTime
        let timeOrigin = WinampPlaylistLayout.shadeTime(width: width)
        canvas.drawGlyphs(time, at: CGPoint(x: timeOrigin.x + CGFloat(max(6 - time.count, 0) * WinampSprites.glyphWidth), y: timeOrigin.y))
    }
}
