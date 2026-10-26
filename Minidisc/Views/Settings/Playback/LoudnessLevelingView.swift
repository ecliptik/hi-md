import SwiftUI

/// Settings > Playback > Loudness Leveling: ReplayGain, its preamp and the limiter.
struct LoudnessLevelingView: View {
    @Environment(\.appContainer) private var container
    @Bindable var settings: ReplayGainSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: binding(\.enabled)) {
                    SettingsRowLabel(title: "Loudness Leveling", subtitle: "Plays every song at a similar volume, using its ReplayGain tags.")
                }
                Picker(selection: binding(\.mode)) {
                    Text("Track").tag(ReplayGainMode.track)
                    Text("Album").tag(ReplayGainMode.album)
                } label: {
                    Text("Mode")
                        .foregroundStyle(.primary)
                }
                .pickerStyle(.menu)
                .tint(.secondary)
                .disabled(!settings.enabled)
                Stepper(
                    value: binding(\.preAmp),
                    in: ReplayGainSettings.minPreAmp...ReplayGainSettings.maxPreAmp,
                    step: ReplayGainSettings.preAmpStep
                ) {
                    SettingsValueRow(
                        title: "Preamp",
                        subtitle: "Raises or lowers everything from the ReplayGain reference of -18 LUFS.",
                        value: Text(Self.decibels(settings.preAmp))
                    )
                }
                .accessibilityValue(Text(Self.decibelsSpoken(settings.preAmp)))
                .disabled(!settings.enabled)
            } footer: {
                Text("Evens out the volume between tracks. Track mode levels each song on its own, and Album mode keeps an album's dynamics.")
            }

            Section {
                Toggle(isOn: binding(\.limiter)) {
                    SettingsRowLabel(title: "Limiter", subtitle: "Holds peaks below full scale, so the preamp, ReplayGain and the equalizer never clip.")
                }
            } footer: {
                Text("With the limiter off, ReplayGain stops at each song's peak instead, which can leave quiet songs quieter.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Loudness Leveling")
        .navigationBarTitleDisplayModeInline()
    }

    /// Writes the setting, then has the player apply it to the current and preloaded songs.
    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ReplayGainSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                Task { await container?.playerService.replayGainSettingsDidChange() }
            }
        )
    }

    static func decibels(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false))) + " dB"
    }

    static func decibelsSpoken(_ value: Double) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))) decibels")
    }
}
