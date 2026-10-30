import SwiftUI

/// What the player's artwork shows. Tapping or clicking the artwork moves to the next, and the
/// choice is remembered: the cover, the spinning MiniDisc, spectrum bars, an oscilloscope, then
/// on the Mac MilkDrop.
enum PlayerArtworkMode: String, CaseIterable {
    case artwork, disc, spectrum, scope, milkDrop

    /// MilkDrop needs projectM, which only the Mac app has.
    static var available: [PlayerArtworkMode] {
        #if os(macOS)
        allCases
        #else
        allCases.filter { $0 != .milkDrop }
        #endif
    }

    var next: PlayerArtworkMode {
        let all = Self.available
        guard let index = all.firstIndex(of: self) else { return .artwork }
        return all[(index + 1) % all.count]
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

    static let storageKey = "minidisc.artworkMode"
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
struct SpectrumArtwork: View {
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
struct ScopeArtwork: View {
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

