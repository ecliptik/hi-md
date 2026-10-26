import SwiftSonic
import SwiftUI

/// The menu bar mini player: the playing song's artwork, title and artist, the transport controls
/// and the scrubber. Settings > Appearance shows or hides it.
struct MacMenuBarPlayer: View {
    let container: AppContainer
    let interface: MacInterface

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let playback = interface.playback(for: container)
        let state = container.playerState
        VStack(spacing: 12) {
            Group {
                if let track = state.currentTrack {
                    CoverArtView(id: track.coverArtId ?? track.id, size: 480, cornerRadius: 8)
                } else if let radio = state.currentRadio {
                    CoverArtView(id: radio.coverArt ?? radio.id, size: 480, cornerRadius: 8,
                                 placeholderSystemImage: "dot.radiowaves.left.and.right")
                } else {
                    MinidiscLogoView(isSpinning: false)
                        .padding(24)
                }
            }
            .frame(width: 240, height: 240)
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)

            VStack(spacing: 2) {
                Text(state.currentTrack?.title ?? state.currentRadio?.name ?? String(localized: "Not Playing"))
                    .font(.headline)
                    .lineLimit(1)
                if let artist = state.currentTrack?.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            MacScrubber()
            MacTransportControls(commands: playback.commands)
            MacVolumeSlider()

            Divider()

            HStack {
                Button("Show Minidisc") {
                    NSApp.activate()
                    if !NSApp.windows.contains(where: { $0.canBecomeMain && $0.isVisible }) {
                        openWindow(id: Self.mainWindowID)
                    }
                    NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                }
                Spacer()
                Button("Quit Minidisc") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 280)
        .environment(playback)
        .environment(interface.navigator)
        .tint(Color.minidiscAccent)
    }

    /// The id of the app's main WindowGroup, so the menu bar player can reopen a closed window.
    static let mainWindowID = "main"
}
