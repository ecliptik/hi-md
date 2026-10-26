import SwiftUI

/// Settings > Playback > Quality: when streaming converts music, and to what.
struct QualitySettingsView: View {
    @Bindable var settings: StreamSettings

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    StreamThresholdPicker(title: "Wi-Fi", selection: $settings.wifiThreshold)
                } label: {
                    SettingsValueRow(
                        title: "Wi-Fi",
                        subtitle: "Music above this bitrate is converted on Wi-Fi and wired networks.",
                        value: Text(settings.wifiThreshold.title)
                    )
                }
                NavigationLink {
                    StreamThresholdPicker(title: "Cellular", selection: $settings.cellularThreshold)
                } label: {
                    SettingsValueRow(
                        title: "Cellular",
                        subtitle: "Music above this bitrate is converted on cellular data.",
                        value: Text(settings.cellularThreshold.title)
                    )
                }
                NavigationLink {
                    ConversionBitratePicker(selection: $settings.conversionBitrate)
                } label: {
                    SettingsValueRow(
                        title: "Conversion Bitrate",
                        subtitle: "What converted music streams at.",
                        value: Text(settings.conversionBitrate.title)
                    )
                }
                Toggle(isOn: $settings.downmixToStereo) {
                    SettingsRowLabel(title: "Downmix to Stereo", subtitle: "Fold surround recordings down to two channels.")
                }
            } footer: {
                Text("Converted music streams as \(ConversionCodec.preferred.displayName). Formats this device can't play are always converted. Changes apply from the next song.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Quality")
        .navigationBarTitleDisplayModeInline()
    }
}

/// The bitrate above which music converts on one kind of network.
struct StreamThresholdPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: StreamThreshold

    var body: some View {
        Form {
            Section {
                ForEach(StreamThreshold.allCases) { threshold in
                    SettingsChoiceRow(
                        title: Text(threshold.title),
                        subtitle: threshold == .maximum ? Text("Always the original file, unless this device can't play its format.") : nil,
                        isSelected: selection == threshold
                    ) {
                        selection = threshold
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayModeInline()
    }
}

/// The bitrate converted music streams at.
struct ConversionBitratePicker: View {
    @Binding var selection: ConversionBitrate

    var body: some View {
        Form {
            Section {
                ForEach(ConversionBitrate.allCases) { bitrate in
                    SettingsChoiceRow(
                        title: Text(bitrate.title),
                        subtitle: bitrate == .recommended ? Text("Recommended") : nil,
                        isSelected: selection == bitrate
                    ) {
                        selection = bitrate
                    }
                }
            } footer: {
                Text("Higher bitrates sound closer to the original and use more data.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Conversion Bitrate")
        .navigationBarTitleDisplayModeInline()
    }
}
