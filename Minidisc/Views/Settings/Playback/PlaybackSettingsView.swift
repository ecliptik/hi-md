import SwiftUI

/// Settings > Playback: everything about how music sounds and keeps playing, one row each.
struct PlaybackSettingsView: View {
    @Environment(\.appContainer) private var container
    @Bindable private var equalizer = EqualizerSettings.shared

    var body: some View {
        Form {
            if let container {
                section(container)
                LyricsSettingsSection(settings: container.lyricsSettings)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Playback")
        .navigationBarTitleDisplayModeInline()
    }

    @ViewBuilder
    private func section(_ container: AppContainer) -> some View {
        @Bindable var stream = container.streamSettings
        Section {
            #if canImport(UIKit)
            AudioOutputRow()
            #endif
            NavigationLink {
                QualitySettingsView(settings: container.streamSettings)
            } label: {
                SettingsRowLabel(title: "Quality", subtitle: "Choose between the original files and saving data.")
            }
            NavigationLink {
                LoudnessLevelingView(settings: container.replayGainSettings)
            } label: {
                SettingsValueRow(
                    title: "Loudness Leveling",
                    subtitle: "Every song at a similar volume, without clipping.",
                    value: Self.onOff(container.replayGainSettings.enabled)
                )
            }
            NavigationLink {
                Form { CrossfadeSettingsSection() }
                    .formStyle(.grouped)
                    .navigationTitle("Crossfade")
                    .navigationBarTitleDisplayModeInline()
            } label: {
                SettingsValueRow(
                    title: "Crossfade",
                    subtitle: "Blend the end of each song into the next.",
                    value: Self.crossfadeValue(container.crossfadeSettings.duration)
                )
            }
            Toggle(isOn: $stream.downmixToStereo) {
                SettingsRowLabel(title: "Downmix to Stereo", subtitle: "When a recording has more than two channels, mix them down to two.")
            }
            NavigationLink {
                EqualizerView()
            } label: {
                SettingsValueRow(
                    title: "Equalizer",
                    subtitle: "Shape the sound, or match it to your headphones.",
                    value: Self.onOff(equalizer.isEnabled)
                )
            }
            NavigationLink {
                AutoplaySettingsView()
            } label: {
                SettingsValueRow(
                    title: "Autoplay",
                    subtitle: "Keep the music going when the queue runs out.",
                    value: Self.onOff(container.playerState.isAutoExtendEnabled)
                )
            }
            NavigationLink {
                CachingSettingsView(settings: container.cacheSettings)
            } label: {
                SettingsRowLabel(title: "Caching", subtitle: "How much music is kept on this device for smooth playback.")
            }
        }
    }

    private static func onOff(_ isOn: Bool) -> Text {
        isOn ? Text("On") : Text("Off")
    }

    private static func crossfadeValue(_ seconds: Double) -> Text {
        seconds == 0 ? Text("Off") : Text(verbatim: String(format: "%.1f s", seconds))
    }
}

struct LyricsSettingsSection: View {
    @Bindable var settings: LyricsSettings

    var body: some View {
        Section {
            Picker(selection: $settings.source) {
                ForEach(LyricsSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            } label: {
                Text("Lyrics source")
                    .foregroundStyle(.primary)
            }
            .pickerStyle(.menu)
            .tint(.secondary)
        } header: {
            Text("Lyrics")
        } footer: {
            Text("Auto checks Navidrome first and falls back to LRCLIB. LRCLIB requests include the track title, artist, album, and duration.")
        }
    }
}
