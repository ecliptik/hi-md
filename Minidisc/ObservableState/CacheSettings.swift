import Foundation
import Observation

@Observable
@MainActor
final class CacheSettings {
    // MARK: - Storage (observation ignored)

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var _capacityMegabytes: Int
    @ObservationIgnored private var _cacheFormat: CacheFormat
    @ObservationIgnored private var _cacheOverCellular: Bool
    @ObservationIgnored private var _cacheWhilePlaying: Bool
    @ObservationIgnored private var _cacheArtwork: Bool
    @ObservationIgnored private var _keepFavoritesOffline: Bool
    @ObservationIgnored private var _keepRecentlyPlayedOffline: Bool
    @ObservationIgnored private var _keepPinnedOffline: Bool
    @ObservationIgnored private var _cacheUpcomingSongs: Bool
    @ObservationIgnored private var _wifiLookahead: CacheLookahead
    @ObservationIgnored private var _cellularLookahead: CacheLookahead

    // MARK: - Visible properties (manual observation hooks)

    var capacityMegabytes: Int {
        get {
            access(keyPath: \.capacityMegabytes)
            return _capacityMegabytes
        }
        set {
            let normalized = Self.normalizedCapacity(newValue)
            withMutation(keyPath: \.capacityMegabytes) {
                _capacityMegabytes = normalized
            }
            defaults.set(normalized, forKey: Self.capacityMegabytesKey)
        }
    }

    var capacityBytes: Int64 {
        Int64(capacityMegabytes) * 1_000_000
    }

    var cacheFormat: CacheFormat {
        get {
            access(keyPath: \.cacheFormat)
            return _cacheFormat
        }
        set {
            withMutation(keyPath: \.cacheFormat) {
                _cacheFormat = newValue
            }
            defaults.set(newValue.rawValue, forKey: Self.cacheFormatKey)
        }
    }

    var cacheOverCellular: Bool {
        get {
            access(keyPath: \.cacheOverCellular)
            return _cacheOverCellular
        }
        set {
            withMutation(keyPath: \.cacheOverCellular) {
                _cacheOverCellular = newValue
            }
            defaults.set(newValue, forKey: Self.cacheOverCellularKey)
        }
    }

    /// Whether cover art fetched from the server is persisted to disk (memory caching always runs).
    var cacheArtwork: Bool {
        get {
            access(keyPath: \.cacheArtwork)
            return _cacheArtwork
        }
        set {
            withMutation(keyPath: \.cacheArtwork) {
                _cacheArtwork = newValue
            }
            defaults.set(newValue, forKey: Self.cacheArtworkKey)
        }
    }

    var keepFavoritesOffline: Bool {
        get {
            access(keyPath: \.keepFavoritesOffline)
            return _keepFavoritesOffline
        }
        set {
            withMutation(keyPath: \.keepFavoritesOffline) { _keepFavoritesOffline = newValue }
            defaults.set(newValue, forKey: Self.keepFavoritesOfflineKey)
        }
    }

    /// Auto-caching: the most recently played albums.
    var keepRecentlyPlayedOffline: Bool {
        get {
            access(keyPath: \.keepRecentlyPlayedOffline)
            return _keepRecentlyPlayedOffline
        }
        set {
            withMutation(keyPath: \.keepRecentlyPlayedOffline) { _keepRecentlyPlayedOffline = newValue }
            defaults.set(newValue, forKey: Self.keepRecentlyPlayedOfflineKey)
        }
    }

    /// Downloads a streamed song in full from its first second, on cellular too, so a stall can
    /// switch to the complete copy and replays are instant. Skipped in Low Data Mode.
    var cacheWhilePlaying: Bool {
        get {
            access(keyPath: \.cacheWhilePlaying)
            return _cacheWhilePlaying
        }
        set {
            withMutation(keyPath: \.cacheWhilePlaying) { _cacheWhilePlaying = newValue }
            defaults.set(newValue, forKey: Self.cacheWhilePlayingKey)
        }
    }

    /// Auto-caching: albums and playlists pinned to Home and Library.
    var keepPinnedOffline: Bool {
        get {
            access(keyPath: \.keepPinnedOffline)
            return _keepPinnedOffline
        }
        set {
            withMutation(keyPath: \.keepPinnedOffline) { _keepPinnedOffline = newValue }
            defaults.set(newValue, forKey: Self.keepPinnedOfflineKey)
        }
    }

    /// Auto-caching: the next songs in the queue, saved into the stream cache ahead of time.
    /// `wifiLookahead` and `cellularLookahead` set how many.
    var cacheUpcomingSongs: Bool {
        get {
            access(keyPath: \.cacheUpcomingSongs)
            return _cacheUpcomingSongs
        }
        set {
            withMutation(keyPath: \.cacheUpcomingSongs) { _cacheUpcomingSongs = newValue }
            defaults.set(newValue, forKey: Self.cacheUpcomingSongsKey)
        }
    }

    /// How far down the queue to cache on Wi-Fi. The stream cache size limit always applies.
    var wifiLookahead: CacheLookahead {
        get {
            access(keyPath: \.wifiLookahead)
            return _wifiLookahead
        }
        set {
            withMutation(keyPath: \.wifiLookahead) { _wifiLookahead = newValue }
            defaults.set(newValue.storedValue, forKey: Self.wifiLookaheadKey)
        }
    }

    /// How far down the queue to cache on cellular data, including over a VPN on cellular.
    var cellularLookahead: CacheLookahead {
        get {
            access(keyPath: \.cellularLookahead)
            return _cellularLookahead
        }
        set {
            withMutation(keyPath: \.cellularLookahead) { _cellularLookahead = newValue }
            defaults.set(newValue.storedValue, forKey: Self.cellularLookaheadKey)
        }
    }

    /// The look-ahead for the current network. Low Data Mode is handled by the callers.
    func lookahead(isCellular: Bool) -> CacheLookahead {
        isCellular ? cellularLookahead : wifiLookahead
    }

    /// Whether any automatic copy is kept in the offline store.
    var keepsAnythingOffline: Bool { keepFavoritesOffline || keepRecentlyPlayedOffline || keepPinnedOffline }

    // MARK: - Defaults & keys

    static let defaultCapacityMegabytes = 512
    static let minCapacityMegabytes = 128
    static let maxCapacityMegabytes = 2_048
    static let capacityStepMegabytes = 128
    static let defaultFormat: CacheFormat = .matchStream
    static let defaultCacheOverCellular: Bool = false
    static let defaultCacheArtwork: Bool = true
    static let defaultWifiLookahead: CacheLookahead = .entireQueue
    static let defaultCellularLookahead: CacheLookahead = .songs(3)
    static let wifiLookaheadChoices: [CacheLookahead] = [.songs(0), .songs(1), .songs(3), .songs(5), .songs(10), .songs(25), .entireQueue]
    static let cellularLookaheadChoices: [CacheLookahead] = [.songs(0), .songs(1), .songs(3), .songs(5), .songs(10)]

    private static let capacityMegabytesKey = "minidisc.cache.capacityMegabytes"
    private static let legacyMaxTracksKey = "minidisc.cache.maxTracks"
    private static let cacheFormatKey = "minidisc.cache.format"
    private static let cacheOverCellularKey = "minidisc.cache.cellular"
    private static let cacheWhilePlayingKey = "minidisc.cache.whilePlaying"
    private static let keepFavoritesOfflineKey = "minidisc.cache.favoritesOffline"
    private static let keepRecentlyPlayedOfflineKey = "minidisc.cache.recentlyPlayedOffline"
    private static let keepPinnedOfflineKey = "minidisc.cache.pinnedOffline"
    private static let cacheUpcomingSongsKey = "minidisc.cache.upcomingSongs"
    private static let cacheArtworkKey = "minidisc.cache.artwork"
    private static let wifiLookaheadKey = "minidisc.cache.wifiLookahead"
    private static let cellularLookaheadKey = "minidisc.cache.cellularLookahead"

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self._keepFavoritesOffline = defaults.object(forKey: Self.keepFavoritesOfflineKey) as? Bool ?? true
        self._keepRecentlyPlayedOffline = defaults.object(forKey: Self.keepRecentlyPlayedOfflineKey) as? Bool ?? true
        self._keepPinnedOffline = defaults.object(forKey: Self.keepPinnedOfflineKey) as? Bool ?? true
        self._cacheUpcomingSongs = defaults.object(forKey: Self.cacheUpcomingSongsKey) as? Bool ?? true
        self._wifiLookahead = (defaults.object(forKey: Self.wifiLookaheadKey) as? Int).map(CacheLookahead.init(storedValue:))
            ?? Self.defaultWifiLookahead
        self._cellularLookahead = (defaults.object(forKey: Self.cellularLookaheadKey) as? Int).map(CacheLookahead.init(storedValue:))
            ?? Self.defaultCellularLookahead

        if defaults.object(forKey: Self.capacityMegabytesKey) != nil {
            self._capacityMegabytes = Self.normalizedCapacity(
                defaults.integer(forKey: Self.capacityMegabytesKey)
            )
        } else if defaults.object(forKey: Self.legacyMaxTracksKey) != nil {
            // The former count limit had no byte meaning. Sixty-four MB per track keeps the
            // user's relative choice while moving to a predictable storage budget.
            let migratedCapacity = Self.normalizedCapacity(
                defaults.integer(forKey: Self.legacyMaxTracksKey) * 64
            )
            self._capacityMegabytes = migratedCapacity
            defaults.set(migratedCapacity, forKey: Self.capacityMegabytesKey)
        } else {
            self._capacityMegabytes = Self.defaultCapacityMegabytes
        }

        let loadedFormatRaw = defaults.string(forKey: Self.cacheFormatKey)
        self._cacheFormat = CacheFormat(rawValue: loadedFormatRaw ?? "") ?? Self.defaultFormat

        self._cacheOverCellular = defaults.bool(forKey: Self.cacheOverCellularKey)
        self._cacheWhilePlaying = defaults.object(forKey: Self.cacheWhilePlayingKey) as? Bool ?? true
        // object(forKey:) so the default is true — bool(forKey:) would silently default to false.
        self._cacheArtwork = defaults.object(forKey: Self.cacheArtworkKey) as? Bool ?? Self.defaultCacheArtwork
    }

    private static func normalizedCapacity(_ value: Int) -> Int {
        let clamped = max(minCapacityMegabytes, min(maxCapacityMegabytes, value))
        let rounded = ((clamped + capacityStepMegabytes / 2) / capacityStepMegabytes)
            * capacityStepMegabytes
        return max(minCapacityMegabytes, min(maxCapacityMegabytes, rounded))
    }
}
