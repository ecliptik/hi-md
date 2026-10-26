import SwiftUI

/// Settings > Playback > Equalizer: a ten-band curve, the on/off switch, presets and a preamp.
struct EqualizerView: View {
    @Bindable private var settings = EqualizerSettings.shared

    var body: some View {
        Form {
            Section {
                EqualizerCurveEditor(gains: settings.gains, isEnabled: settings.isEnabled) { gain, band in
                    settings.setGain(gain, band: band)
                }
                .padding(.vertical, MinidiscSpacing.s)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } footer: {
                if let profileName = settings.profileName {
                    Text("AutoEQ: \(profileName)")
                }
            }

            Section {
                Toggle("Enable Equalizer", isOn: $settings.isEnabled)
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

            Section {
                LabeledContent("Preamp") {
                    Text(Self.decibels(settings.preamp)).monospacedDigit()
                }
                Slider(value: Binding(get: { settings.preamp }, set: { settings.setPreamp($0) }),
                       in: EqualizerSettings.preampRange, step: 0.5)
                    .accessibilityLabel("Preamp")
                    .accessibilityValue(EqualizerCurveEditor.gainSpoken(settings.preamp))
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

    static func decibels(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false))) + " dB"
    }
}
