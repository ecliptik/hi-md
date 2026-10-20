import AppIntents
import SwiftUI
import WidgetKit

struct PlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.minidisc.control.playPause", provider: PlayingValueProvider()) { isPlaying in
            ControlWidgetToggle("Minidisc", isOn: isPlaying, action: SetMinidiscPlayingIntent()) { playing in
                Label(playing ? "Playing" : "Paused", systemImage: playing ? "pause.fill" : "play.fill")
            }
        }
        .displayName("Play or Pause")
        .description("Play or pause Minidisc.")
    }
}

/// Reads the last published state; the app reloads controls whenever playback starts or stops.
struct PlayingValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetSnapshotStore.load()?.nowPlaying?.isPlaying ?? false
    }
}

struct NextTrackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.minidisc.control.next") {
            ControlWidgetButton(action: SkipMinidiscTrackIntent()) {
                Label("Next Track", systemImage: "forward.fill")
            }
        }
        .displayName("Next Track")
        .description("Skip to the next song in Minidisc.")
    }
}

struct SmartShuffleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.minidisc.control.smartShuffle") {
            ControlWidgetButton(action: StartMinidiscSmartShuffleIntent()) {
                Label("Smart Shuffle", systemImage: "shuffle")
            }
        }
        .displayName("Smart Shuffle")
        .description("Shuffle your library, or your downloads when offline.")
    }
}

struct PlayMoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "app.minidisc.control.mood", intent: MoodControlConfiguration.self) { configuration in
            ControlWidgetButton(action: PlayMinidiscMoodWidgetIntent(mood: configuration.mood)) {
                Label {
                    Text(configuration.mood.localizedStringResource)
                } icon: {
                    Image(systemName: configuration.mood.symbolName)
                }
            }
        }
        .displayName("Play a Mood")
        .description("Play one of your Mood playlists.")
        .promptsForUserConfiguration()
    }
}

extension MinidiscMood {
    var symbolName: String {
        switch self {
        case .night: "moon.stars"
        case .energetic: "bolt"
        case .workout: "figure.run"
        case .chill: "leaf"
        case .focus: "headphones"
        }
    }
}
