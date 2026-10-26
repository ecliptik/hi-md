import CoreGraphics
import CoreText
import Foundation

/// Draws skin sprites in a window's top-left pixel coordinates into a bitmap `scale` times the
/// window's size. Sprites are scaled with nearest-neighbour filtering so they stay pixel-exact;
/// text drawn with `drawString` is rendered at the full scale, so it stays sharp at every zoom and on
/// Retina displays.
nonisolated struct WinampCanvas {
    let context: CGContext
    let sprites: WinampSpriteCache
    /// The window's size in skin pixels.
    let size: CGSize
    let scale: CGFloat

    /// A cleared sRGB bitmap of `size × scale` pixels, or nil if the size is empty.
    static func make(size: CGSize, scale: CGFloat, sprites: WinampSpriteCache) -> WinampCanvas? {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.scaleBy(x: scale, y: scale)
        return WinampCanvas(context: context, sprites: sprites, size: size, scale: scale)
    }

    func makeImage() -> CGImage? { context.makeImage() }

    /// A top-left rectangle in the context's bottom-left user space.
    func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    func draw(_ sprite: WinampSprite, at origin: CGPoint) {
        draw(sprite, in: CGRect(origin: origin, size: CGSize(width: sprite.width, height: sprite.height)))
    }

    /// Stretches or squeezes the sprite into `rect`.
    func draw(_ sprite: WinampSprite, in rect: CGRect) {
        guard let image = sprites.image(for: sprite) else { return }
        context.draw(image, in: flipped(rect))
    }

    /// Repeats the sprite across `rect`, left to right and top to bottom, cutting the last copies.
    func tile(_ sprite: WinampSprite, in rect: CGRect) {
        guard sprite.width > 0, sprite.height > 0 else { return }
        context.saveGState()
        context.clip(to: flipped(rect))
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                draw(sprite, at: CGPoint(x: x, y: y))
                x += CGFloat(sprite.width)
            }
            y += CGFloat(sprite.height)
        }
        context.restoreGState()
    }

    func fill(_ rect: CGRect, color: WinampColor) {
        context.setFillColor(color.cgColor)
        context.fill(flipped(rect))
    }

    /// `text.bmp` glyphs, 5 pixels apart.
    func drawGlyphs(_ text: String, at origin: CGPoint) {
        for (index, character) in text.enumerated() {
            draw(WinampSprites.glyph(for: character),
                 at: CGPoint(x: origin.x + CGFloat(index * WinampSprites.glyphWidth), y: origin.y))
        }
    }

    func withClip(to rect: CGRect, _ body: () -> Void) {
        context.saveGState()
        context.clip(to: flipped(rect))
        body()
        context.restoreGState()
    }

    /// One line of text with its baseline `baseline` pixels below `origin.y`, cut at `maxWidth`.
    /// Right-aligned text ends at `origin.x + maxWidth`.
    func drawString(_ string: String, font: CTFont, color: WinampColor, at origin: CGPoint,
                    baseline: CGFloat, maxWidth: CGFloat, alignRight: Bool = false) {
        guard !string.isEmpty, maxWidth > 0 else { return }
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color.cgColor]
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x = alignRight ? origin.x + maxWidth - width : origin.x
        context.saveGState()
        context.clip(to: flipped(CGRect(x: origin.x, y: origin.y - 2, width: maxWidth, height: baseline + 6)))
        context.setShouldAntialias(true)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: size.height - origin.y - baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// The skin's playlist font at `pixelSize` window pixels, falling back to Helvetica and Arial.
    static func font(named name: String, pixelSize: CGFloat) -> CTFont {
        for candidate in [name, "Helvetica", "Arial"] where !candidate.isEmpty {
            let font = CTFontCreateWithName(candidate as CFString, pixelSize, nil)
            // CoreText substitutes a default font for unknown names; keep it only on a family match.
            let family = CTFontCopyFamilyName(font) as String
            if family.caseInsensitiveCompare(candidate) == .orderedSame || candidate == "Arial" { return font }
        }
        return CTFontCreateUIFontForLanguage(.system, pixelSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, pixelSize, nil)
    }
}
