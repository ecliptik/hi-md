import Foundation
import Observation

/// The equalizer as chosen in Settings, saved in UserDefaults and pushed to
/// `EqualizerParameters` for the audio taps.
@Observable
@MainActor
final class EqualizerSettings {
    static let shared = EqualizerSettings(defaults: .standard)

    private enum Key {
        static let enabled = "equalizer.enabled"
        static let gains = "equalizer.gains"
        static let preamp = "equalizer.preamp"
        static let preset = "equalizer.preset"
        static let profile = "equalizer.autoEQProfile"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let parameters: EqualizerParameters

    var isEnabled: Bool { didSet { save() } }
    /// Ten gains in dB, 31 Hz to 16 kHz.
    private(set) var gains: [Float]
    private(set) var preamp: Float
    /// The preset the curve came from, or nil once a band was moved by hand.
    private(set) var preset: EqualizerPreset?
    /// The AutoEQ profile the curve came from, or nil.
    private(set) var profileName: String?

    static let preampRange: ClosedRange<Float> = Equalizer.gainRange.lowerBound...0

    init(defaults: UserDefaults, parameters: EqualizerParameters = .shared) {
        self.defaults = defaults
        self.parameters = parameters
        isEnabled = defaults.bool(forKey: Key.enabled)
        // Curves are stored as ten Doubles; any saved before the bands moved to 31 and 62 Hz load
        // unchanged, clamped in case an older build allowed more.
        let stored = (defaults.array(forKey: Key.gains) as? [Double])?.map { Self.clampedGain(Float($0)) } ?? []
        gains = stored.count == Equalizer.bandCount ? stored : EqualizerPreset.flat.gains
        preamp = Self.clampedPreamp(Float(defaults.double(forKey: Key.preamp)))
        preset = defaults.string(forKey: Key.preset).flatMap(EqualizerPreset.init(rawValue:))
            ?? (defaults.object(forKey: Key.gains) == nil ? .flat : nil)
        profileName = preset == nil ? defaults.string(forKey: Key.profile) : nil
        publish()
    }

    func apply(_ preset: EqualizerPreset) {
        gains = preset.gains
        preamp = preset.preamp
        self.preset = preset
        profileName = nil
        save()
    }

    /// Applies a curve from elsewhere, such as an AutoEQ profile, and remembers its name.
    func apply(gains newGains: [Float], preamp newPreamp: Float, profileName: String) {
        guard newGains.count == Equalizer.bandCount else { return }
        gains = newGains.map(Self.clampedGain)
        preamp = Self.clampedPreamp(newPreamp)
        preset = nil
        self.profileName = profileName
        save()
    }

    func setGain(_ gain: Float, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = Self.clampedGain(gain)
        preset = nil
        profileName = nil
        save()
    }

    func setPreamp(_ value: Float) {
        preamp = Self.clampedPreamp(value)
        save()
    }

    nonisolated static func clampedGain(_ gain: Float) -> Float {
        guard gain.isFinite else { return 0 }
        return min(max(gain, Equalizer.gainRange.lowerBound), Equalizer.gainRange.upperBound)
    }

    nonisolated static func clampedPreamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, Equalizer.gainRange.lowerBound), 0)
    }

    private func save() {
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(gains.map(Double.init), forKey: Key.gains)
        defaults.set(Double(preamp), forKey: Key.preamp)
        defaults.set(preset?.rawValue, forKey: Key.preset)
        defaults.set(profileName, forKey: Key.profile)
        publish()
    }

    /// Sends the current curve to the audio taps.
    func publish() {
        var snapshot = EqualizerParameters.Snapshot()
        snapshot.isEnabled = isEnabled
        snapshot.preampDB = preamp
        for (band, gain) in gains.prefix(Equalizer.bandCount).enumerated() { snapshot.gainsDB[band] = gain }
        parameters.update(snapshot)
    }
}
