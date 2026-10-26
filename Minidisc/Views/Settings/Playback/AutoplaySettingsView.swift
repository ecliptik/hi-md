import SwiftUI

/// Settings > Playback > Autoplay: what happens when the queue runs out.
struct AutoplaySettingsView: View {
    @Environment(\.appContainer) private var container
    @AppStorage(PlaybackPreferences.Key.autoplayAlbumDirection) private var albumDirection: AutoplayAlbumDirection = .similar
    @AppStorage(PlaybackPreferences.Key.autoplayCountsAsPlays) private var countsAsPlays = true

    var body: some View {
        Form {
            Section {
                if let container {
                    Toggle(isOn: Binding(
                        get: { container.playerState.isAutoExtendEnabled },
                        set: { enabled in Task { await container.playerService.setAutoExtendEnabled(enabled) } }
                    )) {
                        SettingsRowLabel(title: "Enabled", subtitle: "Play related music when your queue ends.")
                    }
                }
                NavigationLink {
                    AlbumDirectionPicker(selection: $albumDirection)
                } label: {
                    SettingsValueRow(
                        title: "Album Direction",
                        subtitle: "What plays after an album you chose ends.",
                        value: Text(albumDirection.title)
                    )
                }
                Toggle(isOn: $countsAsPlays) {
                    SettingsRowLabel(title: "Add to Recent Plays", subtitle: "Autoplay songs count as plays: scrobbles, ListenBrainz and Recently Played.")
                }
            } footer: {
                Text("Turning Autoplay on also turns off Repeat and Shuffle.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Autoplay")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct AlbumDirectionPicker: View {
    @Binding var selection: AutoplayAlbumDirection

    var body: some View {
        Form {
            Section {
                ForEach(AutoplayAlbumDirection.allCases) { direction in
                    SettingsChoiceRow(
                        title: Text(direction.title),
                        subtitle: Text(Self.explanation(direction)),
                        isSelected: selection == direction
                    ) {
                        selection = direction
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Album Direction")
        .navigationBarTitleDisplayModeInline()
    }

    private static func explanation(_ direction: AutoplayAlbumDirection) -> LocalizedStringKey {
        switch direction {
        case .similar: "Related songs from your library follow, as after any other queue."
        case .stop: "The album ends the session. Playlists and mixes still continue."
        }
    }
}
