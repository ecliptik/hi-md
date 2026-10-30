import AppKit
import SwiftUI

/// What the player's artwork shows. Clicking the artwork moves to the next, and the choice is
/// remembered: the cover, the spinning MiniDisc, spectrum bars, an oscilloscope, then MilkDrop.
enum MacArtworkMode: String, CaseIterable {
    case artwork, disc, spectrum, scope, milkDrop

    var next: MacArtworkMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// What clicking shows next, for the help tag and VoiceOver.
    var nextTitle: Text {
        switch next {
        case .artwork: Text("Show Artwork")
        case .disc: Text("Show Spinning Disc")
        case .spectrum: Text("Show Spectrum")
        case .scope: Text("Show Oscilloscope")
        case .milkDrop: Text("Show MilkDrop")
        }
    }

    static let storageKey = "minidisc.mac.artworkMode"
}

extension AudioAnalyzerConfiguration {
    /// Enough bars and trace points for an artwork-sized view.
    static let artwork = AudioAnalyzerConfiguration(
        bandCount: 40, fftSize: 2048, waveformLength: 240,
        minimumFrequency: 40, maximumFrequency: 16_000, floorDecibels: -70
    )
}

/// Spectrum bars in the accent colour on black, in place of the artwork. The analyser runs only
/// while the view is on screen.
struct MacSpectrumArtwork: View {
    var cornerRadius: Double
    @Environment(\.minidiscPlayingAccent) private var accent
    @State private var visualizer = PlaybackVisualizer(configuration: .artwork)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / Double(PlaybackVisualizer.framesPerSecond))) { _ in
            Canvas { context, size in
                let bands = visualizer.latestFrame.spectrum
                guard !bands.isEmpty else { return }
                let gap = max(1.5, size.width * 0.006)
                let width = (size.width - gap * CGFloat(bands.count + 1)) / CGFloat(bands.count)
                let floor = size.height * 0.92
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [accent.opacity(0.55), accent, .white.opacity(0.9)]),
                    startPoint: CGPoint(x: 0, y: floor), endPoint: CGPoint(x: 0, y: size.height * 0.08))
                for (index, level) in bands.enumerated() {
                    let height = max(2, CGFloat(level) * floor * 0.9)
                    let rect = CGRect(x: gap + CGFloat(index) * (width + gap), y: floor - height, width: width, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: min(2, width / 3)), with: shading)
                }
            }
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear { visualizer.start() }
        .onDisappear { visualizer.stop() }
    }
}

/// The waveform as an oscilloscope trace, glowing in the accent colour on black.
struct MacScopeArtwork: View {
    var cornerRadius: Double
    @Environment(\.minidiscPlayingAccent) private var accent
    @State private var visualizer = PlaybackVisualizer(configuration: .artwork)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / Double(PlaybackVisualizer.framesPerSecond))) { _ in
            Canvas { context, size in
                let samples = visualizer.latestFrame.waveform
                guard samples.count > 1 else { return }
                let middle = size.height / 2
                var trace = Path()
                for (index, sample) in samples.enumerated() {
                    let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(samples.count - 1),
                                        y: middle - CGFloat(sample) * middle * 0.85)
                    if index == 0 { trace.move(to: point) } else { trace.addLine(to: point) }
                }
                let line = max(1.5, size.width / 240)
                context.stroke(trace, with: .color(accent.opacity(0.25)), style: StrokeStyle(lineWidth: line * 5, lineJoin: .round))
                context.stroke(trace, with: .color(accent), style: StrokeStyle(lineWidth: line, lineJoin: .round))
            }
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear { visualizer.start() }
        .onDisappear { visualizer.stop() }
    }
}

/// MilkDrop in place of the artwork, with its own projectM and the presets of the MilkDrop
/// window. Clicks go through to the artwork, which moves on to the cover.
struct MacMilkDropArtwork: NSViewRepresentable {
    var cornerRadius: Double

    @MainActor
    final class Coordinator {
        let driver = MilkDropDriver(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MilkDropCanvas {
        let canvas = context.coordinator.driver.canvas
        canvas.wantsLayer = true
        canvas.layer?.cornerRadius = cornerRadius
        canvas.layer?.cornerCurve = .continuous
        canvas.layer?.masksToBounds = true
        context.coordinator.driver.start()
        return canvas
    }

    func updateNSView(_ canvas: MilkDropCanvas, context: Context) {
        canvas.layer?.cornerRadius = cornerRadius
    }

    static func dismantleNSView(_ canvas: MilkDropCanvas, coordinator: Coordinator) {
        coordinator.driver.stop()
    }
}
