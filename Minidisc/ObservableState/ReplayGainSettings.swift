import Foundation
import Observation

nonisolated enum ReplayGainMode: String, CaseIterable, Sendable, Codable {
    case track
    case album
}

nonisolated struct ReplayGainConfig: Sendable {
    let enabled: Bool
    let mode: ReplayGainMode
    /// dB added on top of the ReplayGain reference (-18 LUFS).
    let preAmp: Double
    /// With the limiter in the audio chain, gain may push peaks past full scale and the limiter
    /// holds them. Without it, gain is capped by the track's peak so nothing clips.
    let limiter: Bool

    /// Whether ReplayGain itself must stay below the track's peak.
    var capsGainAtPeak: Bool { !limiter }
}

/// Loudness Leveling: ReplayGain, a preamp and the peak limiter.
@Observable
@MainActor
final class ReplayGainSettings {
    // MARK: - Storage (observation ignored)

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let limiterParameters: LimiterParameters
    @ObservationIgnored private var _enabled: Bool
    @ObservationIgnored private var _mode: ReplayGainMode
    @ObservationIgnored private var _preAmp: Double
    @ObservationIgnored private var _limiter: Bool

    // MARK: - Visible properties (manual observation hooks)

    var enabled: Bool {
        get {
            access(keyPath: \.enabled)
            return _enabled
        }
        set {
            withMutation(keyPath: \.enabled) {
                _enabled = newValue
            }
            defaults.set(newValue, forKey: Self.enabledKey)
        }
    }

    var mode: ReplayGainMode {
        get {
            access(keyPath: \.mode)
            return _mode
        }
        set {
            withMutation(keyPath: \.mode) {
                _mode = newValue
            }
            defaults.set(newValue.rawValue, forKey: Self.modeKey)
        }
    }

    /// Whole decibels from -15 to +15.
    var preAmp: Double {
        get {
            access(keyPath: \.preAmp)
            return _preAmp
        }
        set {
            let clamped = Self.normalizedPreAmp(newValue)
            withMutation(keyPath: \.preAmp) {
                _preAmp = clamped
            }
            defaults.set(clamped, forKey: Self.preAmpKey)
        }
    }

    var limiter: Bool {
        get {
            access(keyPath: \.limiter)
            return _limiter
        }
        set {
            withMutation(keyPath: \.limiter) {
                _limiter = newValue
            }
            defaults.set(newValue, forKey: Self.limiterKey)
            limiterParameters.isEnabled = newValue
        }
    }

    // MARK: - Defaults, bounds & keys

    static let defaultEnabled: Bool = false
    static let defaultMode: ReplayGainMode = .track
    nonisolated static let defaultPreAmp: Double = 0
    static let defaultLimiter: Bool = true
    nonisolated static let minPreAmp: Double = -15
    nonisolated static let maxPreAmp: Double = 15
    nonisolated static let preAmpStep: Double = 1

    private static let enabledKey = "minidisc.replayGain.enabled"
    private static let modeKey = "minidisc.replayGain.mode"
    private static let preAmpKey = "minidisc.replayGain.preAmp"
    private static let limiterKey = "minidisc.replayGain.limiter"
    /// "Prevent clipping" capped gain at the peak. The limiter replaces it and is on for everyone:
    /// with it on, a track is never quieter than before and still never clips.
    private static let legacyPreventClippingKey = "minidisc.replayGain.preventClipping"

    /// Clamps to the range and rounds to whole decibels; a preamp saved in half steps rounds away from zero.
    nonisolated static func normalizedPreAmp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPreAmp }
        return max(minPreAmp, min(maxPreAmp, value.rounded(.toNearestOrAwayFromZero)))
    }

    // MARK: - Derived

    var config: ReplayGainConfig {
        ReplayGainConfig(enabled: _enabled, mode: _mode, preAmp: _preAmp, limiter: _limiter)
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard, limiterParameters: LimiterParameters = .shared) {
        self.defaults = defaults
        self.limiterParameters = limiterParameters
        _enabled = defaults.bool(forKey: Self.enabledKey)

        let modeRaw = defaults.string(forKey: Self.modeKey)
        _mode = ReplayGainMode(rawValue: modeRaw ?? "") ?? Self.defaultMode

        if defaults.object(forKey: Self.preAmpKey) != nil {
            _preAmp = Self.normalizedPreAmp(defaults.double(forKey: Self.preAmpKey))
        } else {
            _preAmp = Self.defaultPreAmp
        }

        defaults.removeObject(forKey: Self.legacyPreventClippingKey)
        if defaults.object(forKey: Self.limiterKey) != nil {
            _limiter = defaults.bool(forKey: Self.limiterKey)
        } else {
            _limiter = Self.defaultLimiter
        }
        limiterParameters.isEnabled = _limiter
    }
}
