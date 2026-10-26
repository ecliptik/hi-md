import Foundation
import OSLog

let instantMixSymbol = "sparkles"

/// Awaits playback startup. Empty mixes produce an informational toast; other failures show an error.
@MainActor
func runInstantMix(
    from seed: InstantMixSeed,
    using container: AppContainer?,
    startingWith seedTrack: DisplayableSong? = nil,
    context: PlaybackContext? = nil
) async {
    guard let container else { return }
    do {
        try await container.playerService.playInstantMix(from: seed, startingWith: seedTrack, context: context)
    } catch MinidiscError.instantMixEmpty {
        container.toastService.show(
            "No similar tracks found for an Instant Mix yet.",
            style: .info,
            duration: 4.0
        )
    } catch {
        Logger.player.error("[INSTANT-MIX] failed: \(error, privacy: .public)")
        container.toastService.showError("Couldn't start Instant Mix.")
    }
}

/// Fire-and-forget Instant Mix for menu items (the menu dismisses on tap, so there is no spam risk and no
/// need for a spinner). Persistent buttons should instead `await runInstantMix` behind their own loading state.
@MainActor
func startInstantMix(
    from seed: InstantMixSeed,
    using container: AppContainer?,
    startingWith seedTrack: DisplayableSong? = nil,
    context: PlaybackContext? = nil
) {
    Task { await runInstantMix(from: seed, using: container, startingWith: seedTrack, context: context) }
}

/// The song Instant Mix's "Playing from" context.
func songMixContext(_ song: DisplayableSong) -> PlaybackContext {
    .instantMix(seed: .song, id: song.id, name: song.title)
}
