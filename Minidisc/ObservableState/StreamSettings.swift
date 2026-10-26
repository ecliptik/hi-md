import Foundation
import Observation

/// Streaming quality: a bitrate threshold for Wi-Fi and one for cellular, the bitrate songs above
/// it are converted to, and whether multichannel audio is folded down to stereo.
@Observable
@MainActor
final class StreamSettings {
    @ObservationIgnored private var _wifiThreshold: StreamThreshold
    @ObservationIgnored private var _cellularThreshold: StreamThreshold
    @ObservationIgnored private var _conversionBitrate: ConversionBitrate
    @ObservationIgnored private var _downmixToStereo: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let downmix: DownmixParameters
    @ObservationIgnored private var isCellular = false

    var wifiThreshold: StreamThreshold {
        get {
            access(keyPath: \.wifiThreshold)
            return _wifiThreshold
        }
        set {
            withMutation(keyPath: \.wifiThreshold) { _wifiThreshold = newValue }
            defaults.set(newValue.rawValue, forKey: Key.wifiThreshold)
        }
    }

    var cellularThreshold: StreamThreshold {
        get {
            access(keyPath: \.cellularThreshold)
            return _cellularThreshold
        }
        set {
            withMutation(keyPath: \.cellularThreshold) { _cellularThreshold = newValue }
            defaults.set(newValue.rawValue, forKey: Key.cellularThreshold)
        }
    }

    var conversionBitrate: ConversionBitrate {
        get {
            access(keyPath: \.conversionBitrate)
            return _conversionBitrate
        }
        set {
            withMutation(keyPath: \.conversionBitrate) { _conversionBitrate = newValue }
            defaults.set(newValue.rawValue, forKey: Key.conversionBitrate)
        }
    }

    var downmixToStereo: Bool {
        get {
            access(keyPath: \.downmixToStereo)
            return _downmixToStereo
        }
        set {
            withMutation(keyPath: \.downmixToStereo) { _downmixToStereo = newValue }
            defaults.set(newValue, forKey: Key.downmixToStereo)
            downmix.isEnabled = newValue
        }
    }

    var currentThreshold: StreamThreshold { isCellular ? cellularThreshold : wifiThreshold }

    /// The rule for the network in use now.
    var currentPolicy: StreamQualityPolicy {
        StreamQualityPolicy(threshold: currentThreshold, conversion: conversionBitrate, codec: .preferred)
    }

    static let defaultWifiThreshold: StreamThreshold = .maximum
    static let defaultCellularThreshold: StreamThreshold = .kbps320
    static let defaultConversionBitrate: ConversionBitrate = .recommended
    static let defaultDownmixToStereo = true

    private enum Key {
        static let wifiThreshold = "minidisc.stream.wifiThreshold"
        static let cellularThreshold = "minidisc.stream.cellularThreshold"
        static let conversionBitrate = "minidisc.stream.conversionBitrate"
        static let downmixToStereo = "minidisc.stream.downmixToStereo"
        /// Presets from before thresholds: "original", "mp3_320" or "mp3_192" per network.
        static let legacyWifi = "minidisc.stream.wifiQuality"
        static let legacyCellular = "minidisc.stream.cellularQuality"
        /// The single preset from before the Wi-Fi and cellular split.
        static let legacySingle = "minidisc.stream.quality"
    }

    init(defaults: UserDefaults = .standard, downmix: DownmixParameters = .shared) {
        self.defaults = defaults
        self.downmix = downmix
        Self.migrateLegacyPresets(in: defaults)
        _wifiThreshold = defaults.string(forKey: Key.wifiThreshold).flatMap(StreamThreshold.init(rawValue:))
            ?? Self.defaultWifiThreshold
        _cellularThreshold = defaults.string(forKey: Key.cellularThreshold).flatMap(StreamThreshold.init(rawValue:))
            ?? Self.defaultCellularThreshold
        _conversionBitrate = defaults.object(forKey: Key.conversionBitrate) == nil
            ? Self.defaultConversionBitrate
            : ConversionBitrate(rawValue: defaults.integer(forKey: Key.conversionBitrate)) ?? Self.defaultConversionBitrate
        _downmixToStereo = defaults.object(forKey: Key.downmixToStereo) == nil
            ? Self.defaultDownmixToStereo
            : defaults.bool(forKey: Key.downmixToStereo)
        downmix.isEnabled = _downmixToStereo
    }

    /// Fed by the app-wide NetworkMonitor so connectivity is observed by a single system monitor.
    func networkPathDidChange(isCellular: Bool) {
        self.isCellular = isCellular
    }

    // MARK: - Migration

    /// Maps a preset to the nearest threshold and conversion bitrate. MP3 320 becomes a 320 kbps
    /// threshold converting to 256 kbps, the highest conversion offered; MP3 192 keeps 192 for both.
    nonisolated static func migrated(preset: String) -> (threshold: StreamThreshold, conversion: ConversionBitrate?)? {
        switch preset {
        case "original": (.maximum, nil)
        case "mp3_320": (.kbps320, .kbps256)
        case "mp3_192": (.kbps192, .kbps192)
        default: nil
        }
    }

    /// Converts stored presets once, then removes them. Settings that were never changed were
    /// never stored, so those users get the new defaults.
    private static func migrateLegacyPresets(in defaults: UserDefaults) {
        let single = defaults.string(forKey: Key.legacySingle)
        let wifi = (defaults.string(forKey: Key.legacyWifi) ?? single).flatMap(migrated(preset:))
        let cellular = (defaults.string(forKey: Key.legacyCellular) ?? single).flatMap(migrated(preset:))
        defer {
            for key in [Key.legacyWifi, Key.legacyCellular, Key.legacySingle] { defaults.removeObject(forKey: key) }
        }
        guard wifi != nil || cellular != nil else { return }
        if let wifi, defaults.object(forKey: Key.wifiThreshold) == nil {
            defaults.set(wifi.threshold.rawValue, forKey: Key.wifiThreshold)
        }
        if let cellular, defaults.object(forKey: Key.cellularThreshold) == nil {
            defaults.set(cellular.threshold.rawValue, forKey: Key.cellularThreshold)
        }
        // One conversion bitrate now serves both networks; the lower one keeps data use where it was.
        let conversions = [wifi?.conversion, cellular?.conversion].compactMap { $0 }
        if let conversion = conversions.min(by: { $0.kbps < $1.kbps }), defaults.object(forKey: Key.conversionBitrate) == nil {
            defaults.set(conversion.rawValue, forKey: Key.conversionBitrate)
        }
    }
}
