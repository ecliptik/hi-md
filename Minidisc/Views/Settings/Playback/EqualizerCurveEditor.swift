import SwiftUI

/// Ten draggable points on a ±12 dB grid, each band's gain above it and its frequency below.
/// Dragging anywhere moves the nearest band; VoiceOver adjusts each band in 1 dB steps.
struct EqualizerCurveEditor: View {
    let gains: [Float]
    let isEnabled: Bool
    let setGain: (_ gain: Float, _ band: Int) -> Void

    @ScaledMetric(relativeTo: .body) private var curveHeight: CGFloat = 220
    @State private var draggedBand: Int?

    private static let dragStep: Float = 0.5
    private static let accessibilityStep: Float = 1

    var body: some View {
        VStack(spacing: MinidiscSpacing.s) {
            labelRow { band in
                Text(Self.gainLabel(gains[band]))
                    .foregroundStyle(draggedBand == band ? MinidiscColors.accent : .primary)
            }
            GeometryReader { proxy in
                ZStack {
                    grid(in: proxy.size)
                    curve(in: proxy.size)
                    points(in: proxy.size)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(in: proxy.size), isEnabled: isEnabled)
                .overlay { accessibilityBands(in: proxy.size) }
            }
            .frame(height: curveHeight)
            labelRow { band in
                Text(Self.frequencyLabel(Equalizer.frequencies[band]))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.snappy(duration: 0.15), value: isEnabled)
    }

    // MARK: - Layout

    private func labelRow<Label: View>(@ViewBuilder _ label: @escaping (Int) -> Label) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<Equalizer.bandCount, id: \.self) { band in
                label(band)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func x(for band: Int, width: CGFloat) -> CGFloat {
        let column = width / CGFloat(Equalizer.bandCount)
        return column * (CGFloat(band) + 0.5)
    }

    private func y(for gain: Float, height: CGFloat) -> CGFloat {
        let range = Equalizer.gainRange
        let fraction = CGFloat((range.upperBound - gain) / (range.upperBound - range.lowerBound))
        return pointRadius + fraction * (height - 2 * pointRadius)
    }

    private func gain(at y: CGFloat, height: CGFloat) -> Float {
        let range = Equalizer.gainRange
        let usable = max(1, height - 2 * pointRadius)
        let fraction = Float(min(max((y - pointRadius) / usable, 0), 1))
        let raw = range.upperBound - fraction * (range.upperBound - range.lowerBound)
        return (raw / Self.dragStep).rounded() * Self.dragStep
    }

    private var pointRadius: CGFloat { 8 }

    // MARK: - Drawing

    private func grid(in size: CGSize) -> some View {
        Path { path in
            for gain: Float in [-12, -6, 0, 6, 12] {
                let y = y(for: gain, height: size.height)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(MinidiscColors.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        .accessibilityHidden(true)
    }

    private func curve(in size: CGSize) -> some View {
        Path { path in
            for band in 0..<Equalizer.bandCount {
                let point = CGPoint(x: x(for: band, width: size.width), y: y(for: gains[band], height: size.height))
                if band == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        .stroke(MinidiscColors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> some View {
        ForEach(0..<Equalizer.bandCount, id: \.self) { band in
            Circle()
                .fill(draggedBand == band ? MinidiscColors.accent : Color.primary)
                .overlay(Circle().strokeBorder(MinidiscColors.accent, lineWidth: 2))
                .frame(width: pointRadius * 2, height: pointRadius * 2)
                .scaleEffect(draggedBand == band ? 1.3 : 1)
                .position(x: x(for: band, width: size.width), y: y(for: gains[band], height: size.height))
        }
        .accessibilityHidden(true)
    }

    // MARK: - Interaction

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let band = draggedBand ?? nearestBand(to: value.startLocation.x, width: size.width)
                if draggedBand == nil {
                    draggedBand = band
                    HapticFeedback.light.trigger()
                }
                let newGain = gain(at: value.location.y, height: size.height)
                if newGain != gains[band] { setGain(newGain, band) }
            }
            .onEnded { _ in draggedBand = nil }
    }

    private func nearestBand(to x: CGFloat, width: CGFloat) -> Int {
        let column = width / CGFloat(Equalizer.bandCount)
        return min(max(Int(x / max(column, 1)), 0), Equalizer.bandCount - 1)
    }

    /// One adjustable element per band, laid over its column.
    private func accessibilityBands(in size: CGSize) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<Equalizer.bandCount, id: \.self) { band in
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel(Text(Self.frequencySpoken(Equalizer.frequencies[band])))
                    .accessibilityValue(Text(Self.gainSpoken(gains[band])))
                    .accessibilityAdjustableAction { direction in
                        guard isEnabled else { return }
                        let step: Float = direction == .increment ? Self.accessibilityStep : -Self.accessibilityStep
                        setGain(gains[band] + step, band)
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Labels

    static func gainLabel(_ gain: Float) -> String {
        gain.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
    }

    static func frequencyLabel(_ frequency: Float) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }

    static func gainSpoken(_ gain: Float) -> String {
        let number = gain.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
        return String(localized: "\(number) decibels")
    }

    static func frequencySpoken(_ frequency: Float) -> String {
        frequency >= 1000
            ? String(localized: "\(Int(frequency / 1000)) kilohertz")
            : String(localized: "\(Int(frequency)) hertz")
    }
}
