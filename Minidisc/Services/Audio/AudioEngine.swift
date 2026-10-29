import AVFoundation
import Foundation

nonisolated enum AudioEngineState: Equatable, Sendable {
    case buffering
    case playing
    case paused
    case stopped
    case error
}

/// Per-load identity rejects late callbacks, including when the same song is loaded again.
nonisolated struct AudioEnginePlaybackToken: Hashable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// Safe diagnostics copied before AVPlayer releases a failed item. Never retain userInfo,
/// localized descriptions, error-log URLs, headers, or server-provided comments.
nonisolated struct AudioEngineFailure: Sendable, Equatable {
    struct Code: Sendable, Equatable {
        enum Domain: String, Sendable {
            case avFoundation, url, coreMedia, osStatus, other

            init(_ domain: String) {
                self = switch domain {
                case "AVFoundationErrorDomain": .avFoundation
                case NSURLErrorDomain: .url
                case "CoreMediaErrorDomain": .coreMedia
                case NSOSStatusErrorDomain: .osStatus
                default: .other
                }
            }
        }

        let domain: Domain
        let value: Int

        init(domain: String, value: Int) {
            self.domain = Domain(domain)
            self.value = value
        }
    }

    private(set) var codes: [Code]

    init(error: (any Error)?, logCode: Code? = nil) {
        var codes: [Code] = []
        var current = error as NSError?
        // A malformed NSError can even contain a cycle in its underlying-error chain.
        for _ in 0..<5 {
            guard let error = current else { break }
            codes.append(Code(domain: error.domain, value: error.code))
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        if let logCode, !codes.contains(logCode) { codes.append(logCode) }
        self.codes = codes
    }

    /// The same failure with the item's last error-log code added, when it is new.
    func adding(logCode: Code?) -> AudioEngineFailure {
        guard let logCode, !codes.contains(logCode) else { return self }
        var copy = self
        copy.codes.append(logCode)
        return copy
    }

    /// AVFoundation could not identify the container. Servers and proxies often label FLAC
    /// `audio/x-flac` or `application/octet-stream`, and a URL without a file extension then
    /// gives it nothing else to go on.
    var isUnidentifiedMedia: Bool {
        codes.contains {
            ($0.domain == .avFoundation && $0.value == AVError.Code.fileFormatNotRecognized.rawValue)
                || ($0.domain == .osStatus && $0.value == -12847)
        }
    }

    /// This invalidates the player objects, not the media URL. Network retries on the
    /// same objects cannot recover, even when a different track is selected.
    var isMediaServicesReset: Bool {
        #if os(iOS)
        codes.contains {
            $0.domain == .avFoundation && $0.value == AVError.Code.mediaServicesWereReset.rawValue
        }
        #else
        // Only iOS resets media services; the Mac never reports this error.
        false
        #endif
    }

    var diagnosticDescription: String {
        codes.isEmpty ? "unknown" : codes.map { "\($0.domain.rawValue):\($0.value)" }.joined(separator: ",")
    }
}

/// A standby item that the engine has already promoted to the active output.
///
/// The orchestration layer uses this snapshot to adopt the exact physical playback without
/// resolving the media URL again at the network-sensitive transition boundary.
nonisolated struct AudioEnginePromotedPlayback: Sendable, Equatable {
    let playbackToken: AudioEnginePlaybackToken
    let trackID: String
    let sourceURL: URL
    let sourceHeaders: [String: String]
    /// Wall-clock instant at which the incoming deck became audible.
    let startedAt: Date
    /// Current position in the promoted item, including any lead-in seek.
    let position: TimeInterval
    /// Audio from the promoted item that has already been heard during an overlap.
    let audibleDuration: TimeInterval
}

/// Everything known at a natural track boundary, captured before deck roles change.
nonisolated struct AudioEngineTrackEnd: Sendable, Equatable {
    let endedPlaybackToken: AudioEnginePlaybackToken
    let endedPosition: TimeInterval
    let promotedPlayback: AudioEnginePromotedPlayback?
}

/// Events an `AudioEngine` reports back. Called on the engine's callback thread; a consumer that is an
/// actor hops to its executor itself (as `PlayerService` does today).
nonisolated protocol AudioEngineDelegate: AnyObject, Sendable {
    func audioEngineDidChangeState(_ state: AudioEngineState, playbackToken: AudioEnginePlaybackToken)
    /// The current track finished on its own (end of file), not by a user stop/skip.
    func audioEngineDidReachEndOfTrack(_ transition: AudioEngineTrackEnd)
    func audioEngineDidError(_ failure: AudioEngineFailure, playbackToken: AudioEnginePlaybackToken)
    /// The standby deck for `trackID` failed to load, seek past its lead-in or preroll, and was
    /// dropped. The active track is unaffected; without a new preload the next track starts cold.
    func audioEngineStandbyPreloadDidFail(trackID: String)
}

/// Synchronous, internally locked audio engine. PlayerService owns queue and session orchestration.
/// volume controls user gain; ReplayGain uses a separate path.
nonisolated protocol AudioEngine: AnyObject, Sendable {
    var delegate: AudioEngineDelegate? { get set }

    /// Starts or adopts an item and returns the identity attached to all callbacks for that load.
    @discardableResult
    func play(trackID: String, url: URL, headers: [String: String]) -> AudioEnginePlaybackToken
    func pause()
    func resume()
    func stop()
    /// Disposes invalid system audio objects. Preserves volume and monotonically increasing
    /// playback tokens, but leaves playback stopped until the caller starts a fresh item.
    func resetAfterMediaServicesReset()
    /// Repositions the active deck and returns only after AVPlayer has completed (or rejected) the seek.
    /// `false` also covers a deck transition that made the request stale while it was in flight.
    func seek(to seconds: Double) async -> Bool

    var volume: Float { get set }
    var progress: Double { get }
    var duration: Double { get }
    var isSeekable: Bool { get }
    /// True when idle and ready to start a source (the cold-restore path checks this).
    var isReady: Bool { get }
    /// Seconds of the active item that are loaded. Growth while playback waits means data is
    /// still arriving, so a stall is worth waiting out rather than rebuilding.
    var bufferedDuration: TimeInterval { get }

    /// Applies a ReplayGain loudness adjustment in dB for the current track (0 = no change).
    func applyReplayGain(dB: Float)

    /// Hints that `url` will very likely be the next `play` target, so the engine can pre-buffer it
    /// for a seamless hand-off. `crossfadeDuration` == 0 asks for a gapless butt-splice; > 0 asks the
    /// engine to blend the two tracks over that window. A later `play` with the same stable track ID
    /// adopts the pre-buffered source; any other ID discards it.
    /// `leadInTrim` skips that many seconds of silence at the start of the preloaded track, so a
    /// gapless pair butts together instead of playing the encoder's padding.
    /// `expectedCurrentTrackID` is the track the preload follows. A preload resolved while the engine
    /// was already promoting that standby deck arrives late; the engine ignores it.
    func preloadNext(
        trackID: String,
        url: URL,
        headers: [String: String],
        crossfadeDuration: Double,
        leadInTrim: Double,
        replayGainDB: Float,
        expectedCurrentTrackID: String
    )

    /// Drops a pending standby deck without touching the active track.
    func cancelPreload()

    /// Ends the CURRENT track `seconds` early, cutting its trailing silence. 0 restores the full
    /// length. Only meaningful ahead of a gapless hand-off; a crossfade wants the real tail.
    /// Ignored unless `expectedCurrentTrackID` is still the active track.
    func setTrackEndTrim(_ seconds: Double, expectedCurrentTrackID: String)

    /// Ends the CURRENT remote item no later than `seconds`, its exact length as measured from a
    /// complete local copy, so a stream that runs past its real end finishes there instead. An
    /// earlier end trim still wins. Ignored for local files and unless `expectedCurrentTrackID` is
    /// still the active track.
    func capPlayback(atExactDuration seconds: Double, expectedCurrentTrackID: String)

    /// The authoritative length of the current track from library metadata, for engines whose own
    /// duration estimate drifts (transcoded/VBR streams) and would mistime transitions.
    func setTrackDuration(_ seconds: Double)
}

nonisolated extension AudioEngine {
    /// Engines that cannot report loading never delay a rebuild.
    var bufferedDuration: TimeInterval { 0 }

    /// Engines without a separate end cap ignore it.
    func capPlayback(atExactDuration seconds: Double, expectedCurrentTrackID: String) {}
}
