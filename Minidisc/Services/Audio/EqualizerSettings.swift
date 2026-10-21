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
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let parameters: EqualizerParameters

    var isEnabled: Bool { didSet { save() } }
    /// Ten gains in dB, 32 Hz to 16 kHz.
    private(set) var gains: [Float]
    private(set) var preamp: Float
    /// The preset the curve came from, or nil once a band was moved by hand.
    private(set) var preset: EqualizerPreset?

    init(defaults: UserDefaults, parameters: EqualizerParameters = .shared) {
        self.defaults = defaults
        self.parameters = parameters
        isEnabled = defaults.bool(forKey: Key.enabled)
        let stored = (defaults.array(forKey: Key.gains) as? [Double])?.map(Float.init) ?? []
        gains = stored.count == Equalizer.bandCount ? stored : EqualizerPreset.flat.gains
        preamp = Float(defaults.double(forKey: Key.preamp))
        preset = defaults.string(forKey: Key.preset).flatMap(EqualizerPreset.init(rawValue:))
            ?? (defaults.object(forKey: Key.gains) == nil ? .flat : nil)
        publish()
    }

    func apply(_ preset: EqualizerPreset) {
        gains = preset.gains
        preamp = preset.preamp
        self.preset = preset
        save()
    }

    func setGain(_ gain: Float, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = min(max(gain, Equalizer.gainRange.lowerBound), Equalizer.gainRange.upperBound)
        preset = nil
        save()
    }

    func setPreamp(_ value: Float) {
        preamp = min(max(value, Equalizer.gainRange.lowerBound), 0)
        save()
    }

    private func save() {
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(gains.map(Double.init), forKey: Key.gains)
        defaults.set(Double(preamp), forKey: Key.preamp)
        defaults.set(preset?.rawValue, forKey: Key.preset)
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
