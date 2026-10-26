import CoreGraphics
import Foundation

// The main window's display logic, kept free of AppKit so it can be tested and rendered offscreen.

/// Whether the LCD counts up from the start or down to the end. Clicking the time toggles it.
nonisolated enum WinampTimeMode: String, CaseIterable, Sendable {
    case elapsed
    case remaining

    var toggled: WinampTimeMode { self == .elapsed ? .remaining : .elapsed }
}

/// The four LCD digits, `mm:ss`, and whether a minus sign leads them.
nonisolated struct WinampTimeDisplay: Sendable, Hashable {
    /// The largest time the four digits hold. Longer times stay at 99:59.
    static let maximumSeconds = 99 * 60 + 59

    var isNegative: Bool
    var minutes: Int
    var seconds: Int

    var digits: [Int] { [minutes / 10, minutes % 10, seconds / 10, seconds % 10] }

    init(isNegative: Bool = false, totalSeconds: Int) {
        let clamped = min(max(totalSeconds, 0), Self.maximumSeconds)
        self.isNegative = isNegative
        minutes = clamped / 60
        seconds = clamped % 60
    }

    /// Elapsed time is the whole seconds played. Remaining time is the whole seconds of the
    /// duration minus those played, so elapsed and remaining always add up to the duration.
    /// Without a known duration (a live stream), remaining mode shows elapsed time.
    static func make(position: TimeInterval, duration: TimeInterval, mode: WinampTimeMode) -> WinampTimeDisplay {
        let played = position.isFinite ? Int(max(position, 0).rounded(.down)) : 0
        guard mode == .remaining, duration.isFinite, duration > 0 else {
            return WinampTimeDisplay(totalSeconds: played)
        }
        let total = Int(duration.rounded(.down))
        return WinampTimeDisplay(isNegative: true, totalSeconds: max(total - played, 0))
    }
}

/// The scrolling song title. Text longer than the display loops with a `***` separator and
/// moves one character per step, as Winamp's marquee does.
nonisolated enum WinampMarquee {
    /// 154 pixels of 5-pixel glyphs: 30 whole characters and the first pixels of a 31st.
    static let visibleCharacters = 31
    static let separator = "  ***  "
    static let stepInterval: Duration = .milliseconds(200)

    /// "Artist - Title (m:ss)". The artist and the duration are left out when unknown.
    static func songTitle(artist: String?, title: String, duration: TimeInterval) -> String {
        var text = title
        if let artist = artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty {
            text = "\(artist) - \(title)"
        }
        if duration.isFinite, duration >= 1 {
            text += " (\(clock(Int(duration.rounded(.down)))))"
        }
        return text
    }

    /// `m:ss`, or `h:mm:ss` from an hour.
    static func clock(_ totalSeconds: Int) -> String {
        let seconds = max(totalSeconds, 0)
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", seconds / 60, remainder)
    }

    static func scrolls(_ text: String) -> Bool { text.count > visibleCharacters }

    /// Steps before a scrolling text repeats: its length plus the separator. Zero when it fits.
    static func cycleLength(of text: String) -> Int {
        scrolls(text) ? text.count + separator.count : 0
    }

    /// The step after `step`, wrapping at the end of the cycle.
    static func nextStep(after step: Int, text: String) -> Int {
        let length = cycleLength(of: text)
        return length == 0 ? 0 : (step + 1) % length
    }

    /// The characters on screen at `step`. Text that fits is shown as it is, from the left.
    static func visibleText(_ text: String, step: Int) -> String {
        guard scrolls(text) else { return text }
        let loop = Array(text + separator)
        let start = ((step % loop.count) + loop.count) % loop.count
        return String((0..<visibleCharacters).map { loop[(start + $0) % loop.count] })
    }
}

/// Bitrate and sample-rate text for the small `kbps` and `kHz` boxes.
nonisolated enum WinampTrackInfoFormat {
    /// The rate actually streamed: the file's, capped by a transcoding limit.
    static func effectiveBitRate(file: Int?, maxBitRate: Int?) -> Int? {
        guard let file, file > 0 else { return maxBitRate.flatMap { $0 > 0 ? $0 : nil } }
        guard let maxBitRate, maxBitRate > 0 else { return file }
        return min(file, maxBitRate)
    }

    /// Up to three characters, right-aligned. Lossless rates of 1000 kbps or more read like
    /// `1k4` (1.4 thousand) so they still fit.
    static func kbps(_ bitRate: Int?) -> String? {
        guard let bitRate, bitRate > 0 else { return nil }
        let text = bitRate < 1000 ? String(bitRate) : "\(min(bitRate / 1000, 9))k\(bitRate % 1000 / 100)"
        return String(repeating: " ", count: max(3 - text.count, 0)) + text
    }

    /// Whole kilohertz, right-aligned to two characters (44, 48, 96, or 192 for very high rates).
    static func khz(_ samplingRate: Int?) -> String? {
        guard let samplingRate, samplingRate > 0 else { return nil }
        let text = String(Int((Double(samplingRate) / 1000).rounded()))
        return String(repeating: " ", count: max(2 - text.count, 0)) + text
    }
}

/// A horizontal slider in the main window: a background track and a thumb that slides along it.
nonisolated struct WinampSliderGeometry: Sendable, Hashable {
    /// The track's left edge in the window.
    let originX: Int
    let trackWidth: Int
    let thumbWidth: Int

    static let seek = WinampSliderGeometry(originX: 16, trackWidth: 248, thumbWidth: 29)
    static let volume = WinampSliderGeometry(originX: 107, trackWidth: 68, thumbWidth: 14)
    static let balance = WinampSliderGeometry(originX: 177, trackWidth: 38, thumbWidth: 14)
    /// The windowshade bar's small position slider.
    static let shadeSeek = WinampSliderGeometry(originX: 226, trackWidth: 17, thumbWidth: 3)

    /// How far the thumb can move: the track minus the thumb.
    var travel: Int { trackWidth - thumbWidth }

    /// The thumb's left edge relative to the track, for a value from 0 to 1.
    func thumbOffset(for fraction: Double) -> Int {
        Int((Self.clamp(fraction) * Double(travel)).rounded())
    }

    /// The value for a pointer at window x `pointerX`, keeping the point where the thumb was
    /// grabbed under the pointer.
    func fraction(pointerX: Double, grabOffset: Double) -> Double {
        guard travel > 0 else { return 0 }
        return Self.clamp((pointerX - Double(originX) - grabOffset) / Double(travel))
    }

    /// Where the thumb is held. Pressing the thumb keeps that point; pressing the track elsewhere
    /// centres the thumb on the pointer, as Winamp's sliders jump to a click.
    func grabOffset(pointerX: Double, currentFraction: Double) -> Double {
        let thumbLeft = Double(originX + thumbOffset(for: currentFraction))
        let inThumb = pointerX >= thumbLeft && pointerX < thumbLeft + Double(thumbWidth)
        return inThumb ? pointerX - thumbLeft : Double(thumbWidth) / 2
    }

    /// One of the 28 background frames for a value from 0 to 1.
    static func backgroundFrame(for fraction: Double) -> Int {
        Int((clamp(fraction) * Double(WinampSprites.sliderFrameCount - 1)).rounded())
    }

    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

/// Balance runs from -1 (left) through 0 to 1 (right); the slider stores it as 0...1.
nonisolated enum WinampBalance {
    /// Values this close to the centre snap to it, as Winamp's balance does.
    static let snapDistance = 0.12

    static func fraction(for balance: Double) -> Double {
        WinampSliderGeometry.clamp((balance + 1) / 2)
    }

    static func balance(for fraction: Double) -> Double {
        let value = WinampSliderGeometry.clamp(fraction) * 2 - 1
        return abs(value) < snapDistance ? 0 : value
    }

    /// The background darkens towards either side: frame 0 is centred.
    static func backgroundFrame(for balance: Double) -> Int {
        WinampSliderGeometry.backgroundFrame(for: abs(balance))
    }
}

/// Text Winamp shows in the title display while a slider is dragged. It is drawn in the skin's
/// ASCII bitmap font, so it is not localised, as in Winamp.
nonisolated enum WinampSliderMessage {
    static func seek(fraction: Double, duration: TimeInterval) -> String {
        let fraction = WinampSliderGeometry.clamp(fraction)
        let total = Int(max(duration, 0).rounded(.down))
        let target = Int((fraction * Double(total)).rounded(.down))
        return "Seek to: \(WinampMarquee.clock(target))/\(WinampMarquee.clock(total)) (\(Int((fraction * 100).rounded()))%)"
    }

    static func volume(_ volume: Double) -> String {
        "Volume: \(Int((WinampSliderGeometry.clamp(volume) * 100).rounded()))%"
    }

    static func balance(_ balance: Double) -> String {
        let percent = Int((min(abs(balance), 1) * 100).rounded())
        if percent == 0 { return "Balance: Center" }
        return "Balance: \(percent)% " + (balance < 0 ? "Left" : "Right")
    }
}

/// What the visualiser area shows. Clicking it cycles through the modes.
nonisolated enum WinampVisualizerMode: String, CaseIterable, Sendable {
    case spectrum
    case oscilloscope
    case off

    var next: WinampVisualizerMode {
        switch self {
        case .spectrum: .oscilloscope
        case .oscilloscope: .off
        case .off: .spectrum
        }
    }
}

/// One frame of the visualiser as drawn: bar heights and peak markers, or a trace.
nonisolated struct WinampVisualizerPicture: Sendable, Hashable {
    var mode: WinampVisualizerMode
    /// 0...1 per bar, left to right.
    var bars: [Float] = []
    /// 0...1 per bar: where each falling peak marker sits.
    var peaks: [Float] = []
    /// -1...1 per column.
    var waveform: [Float] = []

    static let off = WinampVisualizerPicture(mode: .off)
}

/// Peak markers that sit on top of the spectrum bars and fall back slowly once the bar drops.
nonisolated struct WinampPeakMarkers: Sendable, Hashable {
    /// How far a marker falls per frame after its hold runs out, at about 30 frames a second.
    static let fallPerFrame: Float = 0.012
    /// Frames a marker waits at its height before falling.
    static let holdFrames = 8

    private(set) var peaks: [Float] = []
    private var holds: [Int] = []

    mutating func update(with bars: [Float]) -> [Float] {
        if peaks.count != bars.count {
            peaks = Array(repeating: 0, count: bars.count)
            holds = Array(repeating: 0, count: bars.count)
        }
        for index in bars.indices {
            if bars[index] >= peaks[index] {
                peaks[index] = bars[index]
                holds[index] = Self.holdFrames
            } else if holds[index] > 0 {
                holds[index] -= 1
            } else {
                peaks[index] = max(peaks[index] - Self.fallPerFrame, bars[index], 0)
            }
        }
        return peaks
    }

    mutating func reset() {
        peaks = []
        holds = []
    }
}

/// Everything the main window draws, as plain values.
nonisolated struct WinampMainDisplayState: Sendable, Hashable {
    enum Playback: Sendable, Hashable {
        case playing
        case paused
        case stopped
    }

    enum Channels: Sendable, Hashable {
        case unknown
        case mono
        case stereo
    }

    var isActive = true
    var playback: Playback = .stopped
    /// Playing but waiting for audio: the indicator's strip goes dark.
    var isBuffering = false
    /// Nil leaves the LCD blank: when stopped, and on the off beat of the paused blink.
    var time: WinampTimeDisplay?
    /// The characters on screen, already scrolled.
    var title = ""
    var kbps: String?
    var khz: String?
    var channels: Channels = .unknown
    /// 0...1.
    var volume: Double = 0.7
    /// -1...1.
    var balance: Double = 0
    /// 0...1, or nil to hide the thumb when nothing seekable is loaded.
    var seekFraction: Double?
    /// The control held down. Buttons draw pressed only while the pointer stays on them.
    var pressed: WinampMainControl?
    var isShuffleOn = false
    var isRepeatOn = false
    var isEqualizerOn = false
    var isPlaylistOn = false
    var isAlwaysOnTop = false
    var isDoubleSize = false
    /// Windowshade: only the 275×14 bar with the time, position and small transport.
    var isShaded = false
    var visualizer: WinampVisualizerPicture = .off
}
