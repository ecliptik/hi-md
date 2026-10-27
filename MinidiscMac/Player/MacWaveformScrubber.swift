import SwiftUI

/// Plexamp's scrubber: the elapsed time, the song's waveform and its length. The waveform is
/// mirrored about its middle, the played part in the accent colour with a thin playhead. Until
/// the song has a local copy to measure it's a plain rounded bar. Click or drag to seek; the
/// seek happens on release. Stacked, as over the MiniPlayer's artwork, the times go under the
/// waveform, elapsed and remaining, with `centerLabel` (the format) between them.
struct MacWaveformScrubber: View {
    let envelope: WaveformEnvelope?
    var height: Double = 26
    var isStacked = false
    var centerLabel: String? = nil
    /// In a row (not stacked): whether the times sit either side of the waveform, which a
    /// narrow MiniPlayer bar drops.
    var showsTimes = true
    /// In a row: the time after the waveform counts down what's left rather than the length.
    var showsRemaining = false
    var timeFont: Font = .caption.weight(.bold)
    var timeWidth: Double = 34

    @Environment(MacPlayback.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragPosition: TimeInterval?

    private static let secondary = Color.white.opacity(NowPlayingText.secondaryOpacity)
    /// The unplayed bars and track: a graphical object, so at least 3:1 on the backdrop.
    private static let unplayed = Color.white.opacity(PlayerBackgroundPalette.dimmedOpacity)
    private static let seekStep: TimeInterval = 10

    var body: some View {
        let state = playback.state
        let duration = state.duration > 0 ? state.duration : (state.currentTrack?.duration ?? 0)
        let shown = min(dragPosition ?? state.position, max(duration, 0))
        let canSeek = state.currentTrack != nil && !state.isLiveStream && duration > 0
        Group {
            if isStacked {
                VStack(spacing: 3) {
                    bar(shown: shown, duration: duration, canSeek: canSeek, state: state)
                    HStack(spacing: 6) {
                        Text(Self.time(shown))
                        Spacer(minLength: 4)
                        if let centerLabel {
                            Text(verbatim: centerLabel)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 1))
                                .accessibilityLabel(Text("Format: \(centerLabel)"))
                        }
                        Spacer(minLength: 4)
                        Text(verbatim: "-" + Self.time(max(duration - shown, 0)))
                    }
                    .font(.caption2.weight(.bold))
                }
            } else {
                HStack(spacing: showsRemaining ? 6 : 8) {
                    if showsTimes {
                        Text(Self.time(shown))
                            .frame(minWidth: timeWidth, alignment: .trailing)
                    }
                    bar(shown: shown, duration: duration, canSeek: canSeek, state: state)
                    if showsTimes {
                        Text(verbatim: showsRemaining ? "-" + Self.time(max(duration - shown, 0)) : Self.time(duration))
                            .frame(minWidth: timeWidth, alignment: .leading)
                    }
                }
            }
        }
        .font(timeFont)
        .monospacedDigit()
        .foregroundStyle(Self.secondary)
        .opacity(canSeek || state.currentTrack == nil ? 1 : 0.6)
        .onDisappear {
            if state.lyricsClock.isScrubbing { playback.cancelScrub() }
        }
    }

    private func bar(shown: TimeInterval, duration: TimeInterval, canSeek: Bool, state: PlayerState) -> some View {
            GeometryReader { proxy in
                let progress = duration > 0 ? shown / duration : 0
                waveform(progress: progress, size: proxy.size)
                    // The next song's waveform, or the plain bar, fades in rather than snapping.
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: envelope)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canSeek else { return }
                            let position = Self.position(at: value.location.x, width: proxy.size.width, duration: duration)
                            dragPosition = position
                            // The lyrics follow the drag before the seek.
                            playback.scrub(to: position)
                        }
                        .onEnded { value in
                            guard canSeek else { return }
                            let target = Self.position(at: value.location.x, width: proxy.size.width, duration: duration)
                            dragPosition = target
                            Task {
                                await playback.seek(to: target)
                                dragPosition = nil
                            }
                        })
            }
            .frame(height: height)
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue(Text(Self.time(shown)))
            .accessibilityAdjustableAction { direction in
                guard canSeek else { return }
                let step = direction == .increment ? Self.seekStep : -Self.seekStep
                let target = min(max(state.position + step, 0), duration)
                Task { await playback.seek(to: target) }
            }
    }

    private static func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.time(pattern: .minuteSecond))
    }

    private static func position(at x: Double, width: Double, duration: TimeInterval) -> TimeInterval {
        guard width > 0 else { return 0 }
        return min(max(x / width, 0), 1) * duration
    }

    @ViewBuilder
    private func waveform(progress: Double, size: CGSize) -> some View {
        let accent = Color.minidiscAccent
        if let levels = envelope?.levels, !levels.isEmpty {
            Canvas { context, canvasSize in
                let count = levels.count
                let step = canvasSize.width / Double(count)
                let barWidth = max(step * 0.62, 1)
                let middle = canvasSize.height / 2
                let playedX = canvasSize.width * progress
                for (index, level) in levels.enumerated() {
                    let x = Double(index) * step + (step - barWidth) / 2
                    let barHeight = max(Double(level) * canvasSize.height, 1.5)
                    let bar = Path(roundedRect: CGRect(x: x, y: middle - barHeight / 2, width: barWidth, height: barHeight),
                                   cornerRadius: barWidth / 2)
                    context.fill(bar, with: .color(x + barWidth / 2 <= playedX ? accent : Self.unplayed))
                }
                let playhead = Path(CGRect(x: min(max(playedX - 0.75, 0), canvasSize.width - 1.5), y: 0,
                                           width: 1.5, height: canvasSize.height))
                context.fill(playhead, with: .color(.white))
            }
        } else {
            ZStack(alignment: .leading) {
                Capsule().fill(Self.unplayed)
                Capsule().fill(accent)
                    .frame(width: max(size.width * progress, 0))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
        }
    }
}
