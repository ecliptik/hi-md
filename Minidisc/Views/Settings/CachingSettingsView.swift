import SwiftUI

/// Settings > Caching: how many upcoming songs are saved before they play, per network, and the
/// full download of the song that is playing. A standalone page so any settings screen can link it.
struct CachingSettingsView: View {
    let settings: CacheSettings

    var body: some View {
        Form {
            Section {
                Toggle("Upcoming Songs", isOn: Binding(
                    get: { settings.cacheUpcomingSongs },
                    set: { settings.cacheUpcomingSongs = $0 }
                ))
                .accessibilityIdentifier("caching-upcoming-toggle")

                Picker("On Wi-Fi", selection: Binding(
                    get: { settings.wifiLookahead },
                    set: { settings.wifiLookahead = $0 }
                )) {
                    ForEach(CacheSettings.wifiLookaheadChoices) { choice in
                        Self.label(for: choice).tag(choice)
                    }
                }
                .accessibilityIdentifier("caching-wifi-lookahead")
                .disabled(!settings.cacheUpcomingSongs)

                Picker("On cellular", selection: Binding(
                    get: { settings.cellularLookahead },
                    set: { settings.cellularLookahead = $0 }
                )) {
                    ForEach(CacheSettings.cellularLookaheadChoices) { choice in
                        Self.label(for: choice).tag(choice)
                    }
                }
                .accessibilityIdentifier("caching-cellular-lookahead")
                .disabled(!settings.cacheUpcomingSongs)
            } footer: {
                Text("Songs coming up in the queue are saved before they play, so the music keeps going through a weak signal. On Wi-Fi this stops at the stream cache size limit. It waits until the playing song has downloaded, and Low Data Mode turns it off.")
            }

            Section {
                Toggle("Save songs as they play", isOn: Binding(
                    get: { settings.cacheWhilePlaying },
                    set: { settings.cacheWhilePlaying = $0 }
                ))
                .accessibilityIdentifier("caching-while-playing-toggle")
            } footer: {
                Text("The playing song downloads in full from its first second, on cellular too. If the connection drops, playback switches to the downloaded copy. Low Data Mode streams only.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Caching")
        .navigationBarTitleDisplayModeInline()
    }

    static func label(for lookahead: CacheLookahead) -> Text {
        switch lookahead {
        case .entireQueue: Text("Entire queue")
        case .songs(0): Text("Off")
        case .songs(let count): Text("\(count) songs")
        }
    }
}
