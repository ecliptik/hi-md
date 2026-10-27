import AppIntents
import Foundation

/// Something a widget, control or Live Activity asks the app to do.
nonisolated enum WidgetCommand: Sendable, Equatable {
    case setPlaying(Bool)
    case togglePlayPause
    case next
    case smartShuffle
    case playMood(String)
    case playCollection(kind: String, id: String)
    case cancelDownload(String)
}

/// Hands widget and control actions to the app.
///
/// Audio playback and Live Activity intents run in the app's process even when tapped in a widget,
/// so only the app ever performs them. It registers the handler while it launches; an intent that
/// arrives first waits briefly for it.
@MainActor
final class WidgetCommandRelay {
    static let shared = WidgetCommandRelay()
    var handler: ((WidgetCommand) async throws -> Void)?

    func perform(_ command: WidgetCommand) async throws {
        for _ in 0..<50 where handler == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let handler else { throw WidgetCommandError.appUnavailable }
        try await handler(command)
    }
}

nonisolated enum WidgetCommandError: Error, CustomLocalizedStringResourceConvertible {
    case appUnavailable

    var localizedStringResource: LocalizedStringResource { "Hi-MD isn't ready yet. Try again in a moment." }
}

/// The five Mood playlists, in a form widgets and controls can offer as a choice.
nonisolated enum MinidiscMood: String, AppEnum, CaseIterable, Sendable {
    case night, energetic, workout, chill, focus

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [MinidiscMood: DisplayRepresentation] = [
        .night: DisplayRepresentation(title: "Night", image: .init(systemName: "moon.stars")),
        .energetic: DisplayRepresentation(title: "Energetic", image: .init(systemName: "bolt")),
        .workout: DisplayRepresentation(title: "Workout", image: .init(systemName: "figure.run")),
        .chill: DisplayRepresentation(title: "Chill", image: .init(systemName: "leaf")),
        .focus: DisplayRepresentation(title: "Focus", image: .init(systemName: "headphones")),
    ]
}

// The intents below back widget and control buttons only. They are hidden from Shortcuts and
// Spotlight because the app's own intents already offer the same actions there.

struct SetMinidiscPlayingIntent: SetValueIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let isDiscoverable = false
    @Parameter(title: "Playing") var value: Bool

    func perform() async throws -> some IntentResult {
        try await WidgetCommandRelay.shared.perform(.setPlaying(value))
        return .result()
    }
}

struct ToggleMinidiscPlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try await WidgetCommandRelay.shared.perform(.togglePlayPause)
        return .result()
    }
}

struct SkipMinidiscTrackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try await WidgetCommandRelay.shared.perform(.next)
        return .result()
    }
}

struct StartMinidiscSmartShuffleIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Smart Shuffle"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try await WidgetCommandRelay.shared.perform(.smartShuffle)
        return .result()
    }
}

struct PlayMinidiscMoodWidgetIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play a Mood"
    static let isDiscoverable = false
    @Parameter(title: "Mood") var mood: MinidiscMood

    init() {}
    init(mood: MinidiscMood) { self.mood = mood }

    func perform() async throws -> some IntentResult {
        try await WidgetCommandRelay.shared.perform(.playMood(mood.rawValue))
        return .result()
    }
}

struct PlayMinidiscCollectionIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play"
    static let isDiscoverable = false
    @Parameter(title: "Kind") var kind: String
    @Parameter(title: "Identifier") var collectionID: String

    init() {}
    init(kind: String, id: String) {
        self.kind = kind
        collectionID = id
    }

    func perform() async throws -> some IntentResult {
        try await WidgetCommandRelay.shared.perform(.playCollection(kind: kind, id: collectionID))
        return .result()
    }
}

/// Chooses which Mood a "Play a Mood" control plays.
struct MoodControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Play a Mood"
    static let isDiscoverable = false
    @Parameter(title: "Mood", default: .chill) var mood: MinidiscMood
}
