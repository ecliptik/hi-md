import SwiftUI

/// A Controls menu with keyboard shortcuts. It appears in the Mac menu bar and in the iPad
/// keyboard shortcut overlay; media keys are handled separately by the Now Playing commands.
struct PlaybackCommands: Commands {
    let container: AppContainer?

    var body: some Commands {
        CommandMenu("Controls") {
            Button(container?.playerState.wantsPlayback == true ? "Pause" : "Play") {
                Task { await container?.playerService.togglePlayPause() }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(container?.playerState.currentTrack == nil)

            Button("Next") {
                Task { await container?.toastService.perform { try await container?.playerService.skipToNext() } }
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(container?.playerState.queue.isEmpty != false)

            Button("Previous") {
                Task { await container?.toastService.perform { try await container?.playerService.skipToPrevious() } }
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(container?.playerState.queue.isEmpty != false)
        }
    }
}
