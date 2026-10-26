import CoreGraphics
import Foundation

/// The equaliser the Winamp window drives. `EqualizerSettings` provides all of it already, so the
/// Mac app conforms it with an empty extension; if that model changes, only the extension does.
@MainActor
protocol WinampEqualizerModel: AnyObject {
    var isEnabled: Bool { get set }
    /// Ten gains in dB, in the engine's band order.
    var gains: [Float] { get }
    /// dB; the app's model allows cuts only, so a boost on the slider stops at 0.
    var preamp: Float { get }
    func setGain(_ gain: Float, band: Int)
    func setPreamp(_ value: Float)
    func apply(_ preset: EqualizerPreset)
}

/// Something in the equaliser window that reacts to the mouse.
nonisolated enum WinampEqualizerControl: Sendable, Hashable {
    case titleBar
    case close
    case shade
    case on
    case auto
    case presets
    case preamp
    /// A band slider, 0 to 9, left to right.
    case band(Int)
}

/// The classic 275×116 equaliser window, in window pixels from the top left.
nonisolated enum WinampEqualizerLayout {
    static let size = CGSize(width: 275, height: 116)
    static let shadeSize = CGSize(width: 275, height: 14)
    static let titleBar = CGRect(x: 0, y: 0, width: 275, height: 14)
    static let close = CGRect(x: 264, y: 3, width: 9, height: 9)
    static let shade = CGRect(x: 254, y: 3, width: 9, height: 9)
    static let on = CGRect(x: 14, y: 18, width: 26, height: 12)
    static let auto = CGRect(x: 40, y: 18, width: 32, height: 12)
    static let graph = CGRect(x: 86, y: 17, width: 113, height: 19)
    static let presets = CGRect(x: 217, y: 18, width: 44, height: 12)
    static let sliderSize = CGSize(width: 14, height: 63)
    static let sliderTop: CGFloat = 38
    static let preamp = CGRect(x: 21, y: sliderTop, width: 14, height: 63)

    static func band(_ index: Int) -> CGRect {
        CGRect(x: 78 + CGFloat(index) * 18, y: sliderTop, width: sliderSize.width, height: sliderSize.height)
    }

    /// `hasShade` is false for skins without `eq_ex.bmp`, which have no shade button.
    static func control(at point: CGPoint, hasShade: Bool) -> WinampEqualizerControl? {
        guard CGRect(origin: .zero, size: size).contains(point) else { return nil }
        if close.contains(point) { return .close }
        if hasShade, shade.contains(point) { return .shade }
        if titleBar.contains(point) { return .titleBar }
        if on.contains(point) { return .on }
        if auto.contains(point) { return .auto }
        if presets.contains(point) { return .presets }
        if preamp.contains(point) { return .preamp }
        for index in 0..<WinampEqualizerBands.count where band(index).contains(point) { return .band(index) }
        return nil
    }

    // MARK: Windowshade (eq_ex.bmp)

    static let shadeClose = CGRect(x: 264, y: 3, width: 9, height: 9)
    static let shadeUnshade = CGRect(x: 254, y: 3, width: 9, height: 9)

    static func shadeControl(at point: CGPoint) -> WinampEqualizerControl? {
        guard CGRect(origin: .zero, size: shadeSize).contains(point) else { return nil }
        if shadeClose.contains(point) { return .close }
        if shadeUnshade.contains(point) { return .shade }
        return .titleBar
    }
}

/// Winamp's ten bands and how they reach the engine's.
///
/// Winamp's sliders are labelled 60 Hz to 16 kHz; the engine's ten bands run 32 Hz to 16 kHz,
/// an octave apart. Each slider drives the engine band in the same position, so the sliders,
/// the Settings equaliser and saved presets always agree and nothing is lost going back and
/// forth. The bundled skin is labelled with the engine's frequencies.
nonisolated enum WinampEqualizerBands {
    static let count = 10
    static let winampFrequencies: [Float] = [60, 170, 310, 600, 1_000, 3_000, 6_000, 12_000, 14_000, 16_000]
    static var engineFrequencies: [Float] { Equalizer.frequencies }

    /// The engine band a slider drives.
    static func engineBand(forSlider slider: Int) -> Int? {
        (0..<count).contains(slider) && slider < Equalizer.bandCount ? slider : nil
    }

    /// The slider showing an engine band.
    static func slider(forEngineBand band: Int) -> Int? {
        (0..<Equalizer.bandCount).contains(band) && band < count ? band : nil
    }

    /// Ten gains in slider order from the engine's gains; missing bands read as 0 dB.
    static func sliderGains(fromEngine gains: [Float]) -> [Float] {
        (0..<count).map { slider in engineBand(forSlider: slider).flatMap { gains.indices.contains($0) ? gains[$0] : nil } ?? 0 }
    }
}

/// The vertical slider maths shared by the preamp and the ten bands: +12 dB at the top, −12 dB at
/// the bottom, an 11-pixel thumb in a 63-pixel well.
nonisolated enum WinampEqualizerSlider {
    static let range: ClosedRange<Float> = -12...12
    static let thumbSize: CGFloat = 11
    /// Pixels the thumb's top can move.
    static let travel: CGFloat = 51
    /// Within this many dB of the middle, a dragged slider settles on 0 dB.
    static let centreSnap: Float = 0.6

    /// 0 at −12 dB, 1 at +12 dB.
    static func fraction(for dB: Float) -> Double {
        guard dB.isFinite else { return 0.5 }
        return Double((min(max(dB, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    static func dB(for fraction: Double) -> Float {
        let fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0.5
        return range.lowerBound + Float(fraction) * (range.upperBound - range.lowerBound)
    }

    /// The thumb's distance from the top of the well.
    static func thumbOffset(for dB: Float) -> CGFloat {
        ((1 - fraction(for: dB)) * Double(travel)).rounded()
    }

    /// Which of the 28 well backgrounds to draw: 0 at −12 dB, 27 at +12 dB.
    static func backgroundFrame(for dB: Float) -> Int {
        Int((fraction(for: dB) * Double(WinampSprites.sliderFrameCount - 1)).rounded())
    }

    /// Where the thumb's top was grabbed, so a drag doesn't jump; a click off the thumb centres it.
    static func grabOffset(pointerY: CGFloat, currentDB: Float) -> CGFloat {
        let top = thumbOffset(for: currentDB)
        return pointerY >= top && pointerY < top + thumbSize ? pointerY - top : thumbSize / 2
    }

    /// The value for a pointer `pointerY` pixels below the top of the well, rounded to 0.1 dB
    /// and drawn to 0 dB near the middle.
    static func dB(pointerY: CGFloat, grabOffset: CGFloat) -> Float {
        let top = min(max(pointerY - grabOffset, 0), travel)
        var value = dB(for: 1 - Double(top / travel))
        if abs(value) < centreSnap { value = 0 }
        return (value * 10).rounded() / 10
    }
}

/// The response curve in the small graph above the sliders: a natural cubic spline through the
/// ten bands, one row per column, 0 at the top.
nonisolated enum WinampEqualizerGraph {
    static let width = 113
    static let height = 19

    static func row(for dB: Float) -> Int {
        let row = ((1 - WinampEqualizerSlider.fraction(for: dB)) * Double(height - 1)).rounded()
        return min(max(Int(row), 0), height - 1)
    }

    /// One row per column across the graph.
    static func curve(gains: [Float]) -> [Int] {
        let values = WinampEqualizerBands.sliderGains(fromEngine: gains).map(Double.init)
        let spacing = Double(width - 1) / Double(values.count - 1)
        let xs = values.indices.map { Double($0) * spacing }
        let spline = NaturalSpline(xs: xs, ys: values)
        return (0..<width).map { column in
            row(for: Float(spline.value(at: Double(column))))
        }
    }

    /// A natural cubic spline: second derivative zero at both ends.
    private struct NaturalSpline {
        let xs: [Double]
        let ys: [Double]
        let second: [Double]

        init(xs: [Double], ys: [Double]) {
            self.xs = xs
            self.ys = ys
            let count = xs.count
            var second = [Double](repeating: 0, count: count)
            guard count > 2 else {
                self.second = second
                return
            }
            var upper = [Double](repeating: 0, count: count)
            for index in 1..<(count - 1) {
                let sigma = (xs[index] - xs[index - 1]) / (xs[index + 1] - xs[index - 1])
                let pivot = sigma * second[index - 1] + 2
                second[index] = (sigma - 1) / pivot
                let slope = (ys[index + 1] - ys[index]) / (xs[index + 1] - xs[index])
                    - (ys[index] - ys[index - 1]) / (xs[index] - xs[index - 1])
                upper[index] = (6 * slope / (xs[index + 1] - xs[index - 1]) - sigma * upper[index - 1]) / pivot
            }
            second[count - 1] = 0
            for index in stride(from: count - 2, through: 0, by: -1) {
                second[index] = second[index] * second[index + 1] + upper[index]
            }
            self.second = second
        }

        func value(at x: Double) -> Double {
            guard xs.count > 1 else { return ys.first ?? 0 }
            var low = 0
            var high = xs.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if xs[middle] > x { high = middle } else { low = middle }
            }
            let span = xs[high] - xs[low]
            guard span > 0 else { return ys[low] }
            let a = (xs[high] - x) / span
            let b = (x - xs[low]) / span
            return a * ys[low] + b * ys[high]
                + ((a * a * a - a) * second[low] + (b * b * b - b) * second[high]) * span * span / 6
        }
    }
}

/// A named curve: a preamp and ten band gains in dB, in slider order.
nonisolated struct WinampEqualizerPreset: Sendable, Hashable, Codable {
    var name: String
    var preamp: Float
    var gains: [Float]

    init(name: String, preamp: Float, gains: [Float]) {
        self.name = name
        self.preamp = preamp
        self.gains = WinampEqualizerBands.sliderGains(fromEngine: gains)
    }
}

/// Winamp's `.eqf` preset files (and `.q1` libraries, which hold several presets).
///
/// A file is the header "Winamp EQ library file v1.1", 0x1A, "!--", then for each preset a
/// 257-byte name padded with zeros and eleven bytes: the ten bands then the preamp. A byte is 0
/// at +12 dB and 63 at −12 dB.
nonisolated enum WinampEQF {
    static let header = Array("Winamp EQ library file v1.1".utf8) + [0x1A] + Array("!--".utf8)
    static let nameLength = 257
    static let valueCount = 11
    static var presetLength: Int { nameLength + valueCount }
    /// Preset libraries are small; larger files decode to nothing.
    static let maximumFileSize = 1024 * 1024

    static func byte(for dB: Float) -> UInt8 {
        let fraction = WinampEqualizerSlider.fraction(for: dB)
        return UInt8(((1 - fraction) * 63).rounded())
    }

    static func dB(for byte: UInt8) -> Float {
        WinampEqualizerSlider.dB(for: 1 - Double(min(byte, 63)) / 63)
    }

    static func encode(_ presets: [WinampEqualizerPreset]) -> Data {
        var data = Data(header)
        for preset in presets {
            var name = Array(preset.name.utf8.prefix(nameLength - 1))
            name += [UInt8](repeating: 0, count: nameLength - name.count)
            data.append(contentsOf: name)
            data.append(contentsOf: WinampEqualizerBands.sliderGains(fromEngine: preset.gains).map(byte(for:)))
            data.append(byte(for: preset.preamp))
        }
        return data
    }

    /// Every complete preset in the file; nil when it isn't an EQ file.
    static func decode(_ data: Data) -> [WinampEqualizerPreset]? {
        guard data.count <= maximumFileSize else { return nil }
        let bytes = [UInt8](data)
        guard bytes.starts(with: header) else { return nil }
        var presets: [WinampEqualizerPreset] = []
        var offset = header.count
        while offset + presetLength <= bytes.count {
            let nameBytes = bytes[offset..<(offset + nameLength)].prefix { $0 != 0 }
            let name = String(decoding: nameBytes, as: UTF8.self)
            let values = bytes[(offset + nameLength)..<(offset + presetLength)].map(dB(for:))
            presets.append(WinampEqualizerPreset(name: name, preamp: values[10], gains: Array(values[0..<10])))
            offset += presetLength
        }
        return presets
    }
}

/// AUTO: Winamp loads a preset for each song. Here the built-in preset matching the playing
/// song's genre is applied while AUTO is on; songs without a matching genre leave the curve alone.
nonisolated enum WinampAutoEqualizer {
    static func preset(forGenre genre: String?) -> EqualizerPreset? {
        guard let genre = genre?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil),
              !genre.isEmpty else { return nil }
        let rules: [(EqualizerPreset, [String])] = [
            (.hipHop, ["hip-hop", "hip hop", "hiphop", "rap", "trap"]),
            (.electronic, ["electro", "techno", "house", "trance", "edm", "dance", "drum and bass", "dubstep", "synth"]),
            (.classical, ["classical", "classique", "klassik", "baroque", "opera", "orchestra", "symphon", "chamber"]),
            (.jazz, ["jazz", "swing", "bebop", "blues"]),
            (.rock, ["rock", "metal", "punk", "grunge", "indie"]),
            (.acoustic, ["acoustic", "folk", "country", "singer-songwriter", "bluegrass"]),
            (.vocal, ["vocal", "a cappella", "spoken", "podcast", "audiobook"]),
            (.pop, ["pop", "r&b", "soul", "funk", "disco"]),
        ]
        return rules.first { _, words in words.contains { genre.contains($0) } }?.0
    }
}

/// Everything the equaliser window draws, as plain values.
nonisolated struct WinampEqualizerDisplayState: Sendable, Hashable {
    var isActive = true
    var isShaded = false
    var isOn = false
    var isAuto = false
    var preamp: Float = 0
    /// Ten gains in slider order.
    var gains: [Float] = Array(repeating: 0, count: WinampEqualizerBands.count)
    var pressed: WinampEqualizerControl?
}

/// Draws the equaliser window from `eqmain.bmp`, and its shade bar from `eq_ex.bmp`.
nonisolated enum WinampEqualizerRenderer {
    static func hasShadeSprites(_ skin: WinampSkin) -> Bool {
        skin.image(for: WinampSprites.equalizerShadeActive) != nil
    }

    static func render(_ state: WinampEqualizerDisplayState, skin: WinampSkin, sprites: WinampSpriteCache,
                       scale: CGFloat = 1) -> CGImage? {
        let size = state.isShaded ? WinampEqualizerLayout.shadeSize : WinampEqualizerLayout.size
        guard let canvas = WinampCanvas.make(size: size, scale: scale, sprites: sprites) else { return nil }
        if state.isShaded {
            canvas.draw(state.isActive ? WinampSprites.equalizerShadeActive : WinampSprites.equalizerShadeInactive, at: .zero)
            if state.pressed == .shade { canvas.draw(WinampSprites.equalizerShadeUnshadePressed, at: WinampEqualizerLayout.shadeUnshade.origin) }
            let close = WinampSprites.equalizerShadeClose
            canvas.draw(state.pressed == .close ? close.pressed : close.normal, at: WinampEqualizerLayout.shadeClose.origin)
            return canvas.makeImage()
        }
        typealias Layout = WinampEqualizerLayout
        canvas.draw(WinampSprites.equalizerBackground, at: .zero)
        canvas.draw(state.isActive ? WinampSprites.equalizerTitleBarActive : WinampSprites.equalizerTitleBarInactive, at: .zero)
        if state.pressed == .close { canvas.draw(WinampSprites.equalizerClose.pressed, at: Layout.close.origin) }
        if state.pressed == .shade, hasShadeSprites(skin) {
            canvas.draw(WinampSprites.equalizerShadeButtonPressed, at: Layout.shade.origin)
        }
        canvas.draw(toggle(WinampSprites.equalizerOn, on: state.isOn, pressed: state.pressed == .on), at: Layout.on.origin)
        canvas.draw(toggle(WinampSprites.equalizerAuto, on: state.isAuto, pressed: state.pressed == .auto), at: Layout.auto.origin)
        let presets = WinampSprites.equalizerPresets
        canvas.draw(state.pressed == .presets ? presets.pressed : presets.normal, at: Layout.presets.origin)

        drawGraph(state, canvas: canvas)
        drawSlider(value: state.preamp, rect: Layout.preamp, pressed: state.pressed == .preamp, canvas: canvas)
        for (index, gain) in state.gains.prefix(WinampEqualizerBands.count).enumerated() {
            drawSlider(value: gain, rect: Layout.band(index), pressed: state.pressed == .band(index), canvas: canvas)
        }
        return canvas.makeImage()
    }

    private static func drawSlider(value: Float, rect: CGRect, pressed: Bool, canvas: WinampCanvas) {
        canvas.draw(WinampSprites.equalizerSliderBackground(frame: WinampEqualizerSlider.backgroundFrame(for: value)), at: rect.origin)
        let thumb = pressed ? WinampSprites.equalizerSliderThumb.pressed : WinampSprites.equalizerSliderThumb.normal
        canvas.draw(thumb, at: CGPoint(x: rect.minX + 1, y: rect.minY + WinampEqualizerSlider.thumbOffset(for: value)))
    }

    /// The curve takes each pixel's colour from the skin's 19-pixel colour strip, by row.
    private static func drawGraph(_ state: WinampEqualizerDisplayState, canvas: WinampCanvas) {
        let graph = WinampEqualizerLayout.graph
        canvas.draw(WinampSprites.equalizerGraphBackground, at: graph.origin)
        let preampRow = WinampEqualizerGraph.row(for: state.preamp)
        canvas.draw(WinampSprites.equalizerPreampLine, at: CGPoint(x: graph.minX, y: graph.minY + CGFloat(preampRow)))
        let rows = WinampEqualizerGraph.curve(gains: state.gains)
        let strip = WinampSprites.equalizerGraphLineColors
        var previous: Int?
        for (column, row) in rows.enumerated() {
            // Join steep steps so the curve stays unbroken.
            let from = previous.map { min($0, row) } ?? row
            let to = previous.map { max($0, row) } ?? row
            for y in from...to {
                let colour = WinampSprite(strip.sheet, strip.x, strip.y + y, 1, 1)
                canvas.draw(colour, at: CGPoint(x: graph.minX + CGFloat(column), y: graph.minY + CGFloat(y)))
            }
            previous = row
        }
    }

    private static func toggle(_ sprites: WinampToggleSprites, on: Bool, pressed: Bool) -> WinampSprite {
        let state = on ? sprites.on : sprites.off
        return pressed ? state.pressed : state.normal
    }
}
