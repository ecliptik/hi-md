import SwiftUI

/// The app's logo: the photographed MiniDisc with its hand-written label. While `isSpinning`, the
/// printed ring around the spindle turns behind the shell, as the disc would in a player; the
/// reflections stay put, as real ones do.
struct MinidiscLogoView: View {
    var isSpinning = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = SpinClock()

    /// The spindle, as a fraction of the logo images, which share one canvas.
    private static let hubAnchor = UnitPoint(x: 0.5257, y: 0.4983)
    private static let aspectRatio: CGFloat = 1280.0 / 1232.0

    var body: some View {
        let spinning = isSpinning && !reduceMotion
        TimelineView(.animation(paused: !spinning)) { context in
            ZStack {
                Image(.minidiscLogo)
                    .resizable()
                Image(.minidiscLogoHub)
                    .resizable()
                    .rotationEffect(.degrees(clock.degrees(at: context.date)), anchor: Self.hubAnchor)
                Image(.minidiscLogoFront)
                    .resizable()
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .onChange(of: spinning, initial: true) { _, running in
            clock.setRunning(running, at: .now)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hi-MD"))
    }
}

/// Keeps the ring where it stopped, so pausing and resuming doesn't snap it back.
private struct SpinClock {
    private static let secondsPerTurn: Double = 3

    private var restingDegrees: Double = 0
    private var startedAt: Date?

    func degrees(at date: Date) -> Double {
        guard let startedAt else { return restingDegrees }
        return restingDegrees + date.timeIntervalSince(startedAt) / Self.secondsPerTurn * 360
    }

    mutating func setRunning(_ running: Bool, at date: Date) {
        if running {
            if startedAt == nil { startedAt = date }
        } else {
            restingDegrees = degrees(at: date).truncatingRemainder(dividingBy: 360)
            startedAt = nil
        }
    }
}
