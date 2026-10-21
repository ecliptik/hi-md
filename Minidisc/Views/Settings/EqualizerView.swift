import SwiftUI

/// Settings > Equalizer: an on/off switch, presets, ten band sliders and a preamp.
struct EqualizerView: View {
    @Bindable private var settings = EqualizerSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Equalizer", isOn: $settings.isEnabled)
                Picker("Preset", selection: Binding(
                    get: { settings.preset },
                    set: { if let preset = $0 { settings.apply(preset) } }
                )) {
                    if settings.preset == nil {
                        Text("Custom").tag(EqualizerPreset?.none)
                    }
                    ForEach(EqualizerPreset.allCases) { preset in
                        Text(preset.title).tag(EqualizerPreset?.some(preset))
                    }
                }
                .tint(.primary)
            } footer: {
                Text("Applies to streamed and downloaded music, including crossfades.")
            }

            Section("Bands") {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<Equalizer.bandCount, id: \.self) { band in
                        EqualizerBandSlider(
                            label: Self.frequencyLabel(Equalizer.frequencies[band]),
                            value: Binding(get: { settings.gains[band] }, set: { settings.setGain($0, band: band) })
                        )
                    }
                }
                .padding(.vertical, MinidiscSpacing.s)
                .disabled(!settings.isEnabled)
                .opacity(settings.isEnabled ? 1 : 0.45)
            }

            Section {
                LabeledContent("Preamp") {
                    Text(Self.decibels(settings.preamp)).monospacedDigit()
                }
                Slider(value: Binding(get: { settings.preamp }, set: { settings.setPreamp($0) }),
                       in: Equalizer.gainRange.lowerBound...0, step: 0.5)
                    .accessibilityLabel("Preamp")
                    .accessibilityValue(Self.decibels(settings.preamp))
                Button("Reset to Flat") { settings.apply(.flat) }
            } footer: {
                Text("Lower the preamp if boosted bands sound distorted.")
            }
            .disabled(!settings.isEnabled)
        }
        .formStyle(.grouped)
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayModeInline()
    }

    static func frequencyLabel(_ frequency: Float) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }

    static func decibels(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false))) + " dB"
    }
}

/// One band: its gain above a vertical slider, and the frequency below.
private struct EqualizerBandSlider: View {
    let label: String
    @Binding var value: Float
    private let height: CGFloat = 160

    var body: some View {
        VStack(spacing: MinidiscSpacing.xs) {
            Text(value.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: $value, in: Equalizer.gainRange, step: 0.5)
                .frame(width: height)
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: height)
                .accessibilityLabel(Text("\(label)Hz"))
                .accessibilityValue(EqualizerView.decibels(value))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
