import SwiftUI

/// The Mac app's menu commands: the Controls menu, Go to Current Song, the inspector items in the
/// View menu, and New Playlist in the File menu.
///
/// Play/Pause has no key equivalent: a menu shortcut would take the space bar from text fields.
/// MacSpaceKeyMonitor handles the space bar instead.
struct MacCommands: Commands {
    let container: AppContainer?
    let interface: MacInterface

    var body: some Commands {
        let playback = container.map(interface.playback(for:))
        let playlists = container.map(interface.playlists(for:))
        let navigator = interface.navigator
        let commands = playback?.commands
        let state = container?.playerState
        // Read here, not only inside bindings, so the menus update when these change.
        let shownPane = navigator.inspector
        let isShuffled = state?.isShuffled == true
        let repeatMode = state?.repeatMode ?? .off

        CommandGroup(replacing: .newItem) {
            Button("New Playlist…") { playlists?.requestNewPlaylist() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(playlists?.canEdit != true)
        }

        CommandMenu("Controls") {
            Button(state?.wantsPlayback == true ? "Pause" : "Play") { playback?.togglePlayPause() }
                .disabled(commands?.canTogglePlayback != true)
            Button("Next") { playback?.skipToNext() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(commands?.canSkip != true)
            Button("Previous") { playback?.skipToPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(commands?.canSkip != true)

            Divider()

            Button("Go to Current Song") {
                guard let track = state?.currentTrack else { return }
                navigator.showAlbum(of: track, highlighting: true)
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(commands?.canGoToCurrentSong != true)

            Divider()

            Button("Increase Volume") { playback?.changeVolume(steps: 1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(playback == nil)
            Button("Decrease Volume") { playback?.changeVolume(steps: -1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(playback == nil)

            Divider()

            Toggle("Shuffle", isOn: Binding(get: { isShuffled }, set: { _ in playback?.toggleShuffle() }))
                .disabled(commands?.canShuffle != true)
            Picker("Repeat", selection: Binding(get: { repeatMode }, set: { playback?.setRepeatMode($0) })) {
                Text("Off").tag(RepeatMode.off)
                Text("All").tag(RepeatMode.all)
                Text("One").tag(RepeatMode.one)
            }
            .disabled(commands?.canRepeat != true)
        }

        CommandGroup(before: .sidebar) {
            Toggle("Lyrics", isOn: inspectorBinding(.lyrics, shown: shownPane, navigator: navigator))
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(commands?.canShowLyrics != true && shownPane != .lyrics)
            Toggle("Playing Next", isOn: inspectorBinding(.queue, shown: shownPane, navigator: navigator))
                .keyboardShortcut("u", modifiers: [.command, .option])
            Divider()
        }
    }

    private func inspectorBinding(_ pane: MacInspectorPane, shown: MacInspectorPane?, navigator: MacNavigator) -> Binding<Bool> {
        Binding {
            shown == pane
        } set: { isOn in
            navigator.inspector = isOn ? pane : nil
        }
    }
}
