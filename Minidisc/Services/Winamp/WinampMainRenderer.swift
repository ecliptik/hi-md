import CoreGraphics
import Foundation

/// Draws the classic main window from a skin's sprites into a 275×116 bitmap, one sprite pixel
/// per bitmap pixel. Callers scale the result with nearest-neighbour filtering for 1× and 2×.
/// Pixels outside the skin's `region.txt` shape stay transparent.
nonisolated enum WinampMainRenderer {
    static let width = Int(WinampMainLayout.size.width)
    static let height = Int(WinampMainLayout.size.height)

    static func render(_ state: WinampMainDisplayState, skin: WinampSkin, sprites: WinampSpriteCache? = nil) -> CGImage? {
        if state.isShaded {
            return renderShade(state, sprites: sprites ?? WinampSpriteCache(skin: skin))
        }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(state, skin: skin, sprites: sprites ?? WinampSpriteCache(skin: skin), in: context)
        return context.makeImage()
    }

    /// Draws into a context whose user space is the window's pixels with the origin at the
    /// bottom left, as a bitmap context's is.
    static func draw(_ state: WinampMainDisplayState, skin: WinampSkin, sprites: WinampSpriteCache, in context: CGContext) {
        var canvas = Canvas(context: context, sprites: sprites, height: CGFloat(height))
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        if let shape = WinampWindowShape(skin: skin).path {
            canvas.clip(to: shape)
        }

        typealias Layout = WinampMainLayout
        canvas.draw(WinampSprites.mainBackground, at: .zero)
        canvas.draw(state.isActive ? WinampSprites.titleBarActive : WinampSprites.titleBarInactive, at: .zero)
        for (control, sprites, origin) in [
            (WinampMainControl.options, WinampSprites.options, Layout.options),
            (.minimize, WinampSprites.minimize, Layout.minimize),
            (.shade, WinampSprites.shade, Layout.shade),
            (.close, WinampSprites.close, Layout.close),
        ] where state.pressed == control {
            canvas.draw(sprites.pressed, at: origin)
        }

        drawClutterBar(state, canvas: &canvas)
        drawIndicator(state, canvas: &canvas)
        if let time = state.time {
            drawTime(time, skin: skin, canvas: &canvas)
        }
        drawVisualizer(state.visualizer, colors: skin.visColors, canvas: &canvas)
        drawText(state, canvas: &canvas)
        canvas.draw(state.channels == .mono ? WinampSprites.monoOn : WinampSprites.monoOff, at: Layout.mono)
        canvas.draw(state.channels == .stereo ? WinampSprites.stereoOn : WinampSprites.stereoOff, at: Layout.stereo)
        drawSliders(state, canvas: &canvas)
        drawButtons(state, canvas: &canvas)
    }

    // MARK: Windowshade

    /// The 275×14 shade bar: its background from `titlebar.bmp` (which carries the small
    /// transport's icons), the pressed corner buttons, the time and the position slider.
    static func renderShade(_ state: WinampMainDisplayState, sprites: WinampSpriteCache) -> CGImage? {
        guard let canvas = WinampCanvas.make(size: WinampMainShadeLayout.size, scale: 1, sprites: sprites) else { return nil }
        typealias Layout = WinampMainLayout
        typealias Shade = WinampMainShadeLayout
        canvas.draw(state.isActive ? WinampSprites.shadeBarActive : WinampSprites.shadeBarInactive, at: .zero)
        for (control, sprite, origin) in [
            (WinampMainControl.options, WinampSprites.options.pressed, Layout.options),
            (.minimize, WinampSprites.minimize.pressed, Layout.minimize),
            (.shade, WinampSprites.unshade.pressed, Layout.shade),
            (.close, WinampSprites.close.pressed, Layout.close),
        ] where state.pressed == control {
            canvas.draw(sprite, at: origin)
        }
        canvas.drawGlyphs(Shade.timeText(state.time), at: Shade.time)
        canvas.draw(WinampSprites.shadePositionBackground, at: Shade.seekBar.origin)
        if let fraction = state.seekFraction {
            let geometry = WinampSliderGeometry.shadeSeek
            let offset = geometry.thumbOffset(for: fraction)
            let thumb = offset == 0 ? WinampSprites.shadePositionThumbLeft
                : offset == geometry.travel ? WinampSprites.shadePositionThumbRight : WinampSprites.shadePositionThumb
            canvas.draw(thumb, at: CGPoint(x: Shade.seekBar.minX + CGFloat(offset), y: Shade.seekBar.minY))
        }
        return canvas.makeImage()
    }

    // MARK: Parts

    private static func drawClutterBar(_ state: WinampMainDisplayState, canvas: inout Canvas) {
        let origin = WinampMainLayout.clutterBar
        canvas.draw(WinampSprites.clutterBar, at: origin)
        for button in WinampClutterButton.allCases {
            let isOn = switch button {
            case .alwaysOnTop: state.isAlwaysOnTop
            case .doubleSize: state.isDoubleSize
            case .options, .info, .visualizer: false
            }
            guard isOn || state.pressed == .clutter(button) else { continue }
            canvas.draw(WinampSprites.clutterSelected(button), at: CGPoint(x: origin.x, y: origin.y + CGFloat(button.rows.top)))
        }
    }

    private static func drawIndicator(_ state: WinampMainDisplayState, canvas: inout Canvas) {
        switch state.playback {
        case .playing:
            canvas.draw(state.isBuffering ? WinampSprites.notWorkingIndicator : WinampSprites.workingIndicator,
                        at: WinampMainLayout.workingIndicator)
            canvas.draw(WinampSprites.playingIndicator, at: WinampMainLayout.playbackIndicator)
        case .paused:
            canvas.draw(WinampSprites.pausedIndicator, at: WinampMainLayout.playbackIndicator)
        case .stopped:
            canvas.draw(WinampSprites.stoppedIndicator, at: WinampMainLayout.playbackIndicator)
        }
    }

    private static func drawTime(_ time: WinampTimeDisplay, skin: WinampSkin, canvas: inout Canvas) {
        let extended = skin.usesExtendedNumbers
        if time.isNegative {
            if extended {
                canvas.draw(WinampSprites.digitMinus, at: WinampMainLayout.timeMinus)
            } else {
                // numbers.bmp has no minus: a 5×1 strip of its "2" sits mid-height in the first cell.
                canvas.draw(WinampSprites.numbersMinus, at: CGPoint(x: WinampMainLayout.timeMinus.x + 2,
                                                                   y: WinampMainLayout.timeMinus.y + 6))
            }
        }
        for (digit, origin) in zip(time.digits, WinampMainLayout.timeDigits) {
            canvas.draw(WinampSprites.digit(digit, extended: extended), at: origin)
        }
    }

    private static func drawText(_ state: WinampMainDisplayState, canvas: inout Canvas) {
        let title = WinampMainLayout.title
        canvas.withClip(to: title) { canvas in
            canvas.drawText(state.title, at: title.origin)
        }
        // Rates are right-aligned at the end of their boxes; a long one runs out to the left.
        for (text, box) in [(state.kbps, WinampMainLayout.kbps), (state.khz, WinampMainLayout.khz)] {
            guard let text else { continue }
            let width = CGFloat(text.count * WinampSprites.glyphWidth)
            canvas.drawText(text, at: CGPoint(x: box.maxX - width, y: box.minY))
        }
    }

    private static func drawSliders(_ state: WinampMainDisplayState, canvas: inout Canvas) {
        typealias Layout = WinampMainLayout
        let volume = WinampSliderGeometry.volume
        canvas.draw(WinampSprites.volumeBackground(frame: WinampSliderGeometry.backgroundFrame(for: state.volume)),
                    at: Layout.volume.origin)
        let volumeThumb = state.pressed == .volume ? WinampSprites.volumeThumb.pressed : WinampSprites.volumeThumb.normal
        canvas.draw(volumeThumb, at: CGPoint(x: Layout.volume.minX + CGFloat(volume.thumbOffset(for: state.volume)),
                                             y: Layout.volume.minY + 1))

        let balance = WinampSliderGeometry.balance
        canvas.draw(WinampSprites.balanceBackground(frame: WinampBalance.backgroundFrame(for: state.balance)),
                    at: Layout.balance.origin)
        let balanceThumb = state.pressed == .balance ? WinampSprites.balanceThumb.pressed : WinampSprites.balanceThumb.normal
        canvas.draw(balanceThumb, at: CGPoint(
            x: Layout.balance.minX + CGFloat(balance.thumbOffset(for: WinampBalance.fraction(for: state.balance))),
            y: Layout.balance.minY + 1
        ))

        canvas.draw(toggle(WinampSprites.equalizerToggle, on: state.isEqualizerOn, pressed: state.pressed == .equalizer),
                    at: Layout.equalizerToggle)
        canvas.draw(toggle(WinampSprites.playlistToggle, on: state.isPlaylistOn, pressed: state.pressed == .playlist),
                    at: Layout.playlistToggle)

        canvas.draw(WinampSprites.seekBackground, at: Layout.seekBar.origin)
        if let fraction = state.seekFraction {
            let thumb = state.pressed == .seek ? WinampSprites.seekThumb.pressed : WinampSprites.seekThumb.normal
            canvas.draw(thumb, at: CGPoint(x: Layout.seekBar.minX + CGFloat(WinampSliderGeometry.seek.thumbOffset(for: fraction)),
                                           y: Layout.seekBar.minY))
        }
    }

    private static func drawButtons(_ state: WinampMainDisplayState, canvas: inout Canvas) {
        typealias Layout = WinampMainLayout
        for (control, sprites, origin) in [
            (WinampMainControl.previous, WinampSprites.previous, Layout.previous),
            (.play, WinampSprites.play, Layout.play),
            (.pause, WinampSprites.pause, Layout.pause),
            (.stop, WinampSprites.stop, Layout.stop),
            (.next, WinampSprites.next, Layout.next),
            (.eject, WinampSprites.eject, Layout.eject),
        ] {
            canvas.draw(state.pressed == control ? sprites.pressed : sprites.normal, at: origin)
        }
        canvas.draw(toggle(WinampSprites.shuffleToggle, on: state.isShuffleOn, pressed: state.pressed == .shuffle),
                    at: Layout.shuffle)
        canvas.draw(toggle(WinampSprites.repeatToggle, on: state.isRepeatOn, pressed: state.pressed == .repeatToggle),
                    at: Layout.repeatToggle)
    }

    private static func toggle(_ sprites: WinampToggleSprites, on: Bool, pressed: Bool) -> WinampSprite {
        let state = on ? sprites.on : sprites.off
        return pressed ? state.pressed : state.normal
    }

    // MARK: Visualiser

    /// Rows of the oscilloscope, top to bottom, as offsets into its five colours: brightest
    /// colour (the first) at the centre line, dimmer towards the edges.
    private static let oscilloscopeShades = [4, 4, 3, 3, 2, 2, 1, 0, 0, 1, 2, 2, 3, 3, 4, 4]

    private static func drawVisualizer(_ picture: WinampVisualizerPicture, colors: [WinampColor], canvas: inout Canvas) {
        guard picture.mode != .off, colors.count == WinampVisColors.count else { return }
        let area = WinampMainLayout.visualizer
        let rows = Int(area.height)
        canvas.fill(area, color: colors[0])
        // Winamp's faint dot grid behind the analyser.
        for y in stride(from: 1, to: rows, by: 2) {
            for x in stride(from: 1, to: Int(area.width), by: 2) {
                canvas.fill(CGRect(x: area.minX + CGFloat(x), y: area.minY + CGFloat(y), width: 1, height: 1), color: colors[1])
            }
        }
        switch picture.mode {
        case .spectrum:
            for (index, value) in picture.bars.prefix(Int(area.width)).enumerated() {
                let x = area.minX + CGFloat(index)
                let barHeight = Int((Double(min(max(value, 0), 1)) * Double(rows)).rounded())
                // Each row keeps its own colour, so tall bars run from the top colour to the bottom one.
                for row in (rows - barHeight)..<rows {
                    canvas.fill(CGRect(x: x, y: area.minY + CGFloat(row), width: 1, height: 1), color: colors[2 + row])
                }
                if index < picture.peaks.count {
                    let peakHeight = Int((Double(min(max(picture.peaks[index], 0), 1)) * Double(rows)).rounded())
                    if peakHeight > 0 {
                        canvas.fill(CGRect(x: x, y: area.minY + CGFloat(rows - peakHeight), width: 1, height: 1), color: colors[23])
                    }
                }
            }
        case .oscilloscope:
            let center = Double(rows) / 2
            for (index, sample) in picture.waveform.prefix(Int(area.width)).enumerated() {
                let clamped = Double(min(max(sample, -1), 1))
                let row = min(max(Int((center - clamped * center).rounded(.down)), 0), rows - 1)
                canvas.fill(CGRect(x: area.minX + CGFloat(index), y: area.minY + CGFloat(row), width: 1, height: 1),
                            color: colors[18 + oscilloscopeShades[row]])
            }
        case .off:
            break
        }
    }

    // MARK: Canvas

    /// Top-left window coordinates over a bottom-left context.
    private struct Canvas {
        let context: CGContext
        let sprites: WinampSpriteCache
        let height: CGFloat

        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }

        func draw(_ sprite: WinampSprite, at origin: CGPoint) {
            guard let image = sprites.image(for: sprite) else { return }
            context.draw(image, in: flipped(CGRect(origin: origin, size: CGSize(width: sprite.width, height: sprite.height))))
        }

        func fill(_ rect: CGRect, color: WinampColor) {
            context.setFillColor(color.cgColor)
            context.fill(flipped(rect))
        }

        func drawText(_ text: String, at origin: CGPoint) {
            for (index, character) in text.enumerated() {
                draw(WinampSprites.glyph(for: character),
                     at: CGPoint(x: origin.x + CGFloat(index * WinampSprites.glyphWidth), y: origin.y))
            }
        }

        mutating func clip(to path: CGPath) {
            var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
            guard let flippedPath = path.copy(using: &transform) else { return }
            context.addPath(flippedPath)
            context.clip(using: .evenOdd)
        }

        mutating func withClip(to rect: CGRect, _ body: (inout Canvas) -> Void) {
            context.saveGState()
            context.clip(to: flipped(rect))
            body(&self)
            context.restoreGState()
        }
    }
}

/// Sprites cut from a skin's sheets once and reused frame after frame.
nonisolated final class WinampSpriteCache {
    let skin: WinampSkin
    private var images: [WinampSprite: CGImage] = [:]
    private var missing: Set<WinampSprite> = []

    init(skin: WinampSkin) {
        self.skin = skin
    }

    func image(for sprite: WinampSprite) -> CGImage? {
        if let image = images[sprite] { return image }
        guard !missing.contains(sprite) else { return nil }
        guard let image = skin.image(for: sprite) else {
            missing.insert(sprite)
            return nil
        }
        images[sprite] = image
        return image
    }
}
