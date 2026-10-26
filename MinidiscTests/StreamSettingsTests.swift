import Foundation
import Testing
@testable import Minidisc

@Suite("Stream settings")
@MainActor
struct StreamSettingsTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "test.stream-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    @Test("New installs start at Maximum on Wi-Fi, 320 kbps on cellular, converting to 128 kbps with downmix on")
    func defaults() {
        withDefaults { defaults in
            let downmix = DownmixParameters()
            downmix.isEnabled = false
            let settings = StreamSettings(defaults: defaults, downmix: downmix)
            #expect(settings.wifiThreshold == .maximum)
            #expect(settings.cellularThreshold == .kbps320)
            #expect(settings.conversionBitrate == .kbps128)
            #expect(settings.downmixToStereo)
            #expect(downmix.isEnabled)
        }
    }

    @Test("The active threshold follows the app-wide network path")
    func currentThresholdFollowsNetworkPath() {
        withDefaults { defaults in
            let settings = StreamSettings(defaults: defaults, downmix: DownmixParameters())
            settings.wifiThreshold = .maximum
            settings.cellularThreshold = .kbps192

            settings.networkPathDidChange(isCellular: false)
            #expect(settings.currentThreshold == .maximum)
            #expect(settings.currentPolicy.threshold == .maximum)

            settings.networkPathDidChange(isCellular: true)
            #expect(settings.currentThreshold == .kbps192)
            #expect(settings.currentPolicy.conversion == settings.conversionBitrate)
        }
    }

    @Test("Choices persist independently")
    func choicesPersist() {
        withDefaults { defaults in
            let downmix = DownmixParameters()
            let settings = StreamSettings(defaults: defaults, downmix: downmix)
            settings.wifiThreshold = .mbps1
            settings.cellularThreshold = .kbps128
            settings.conversionBitrate = .kbps96
            settings.downmixToStereo = false
            #expect(!downmix.isEnabled)

            let restored = StreamSettings(defaults: defaults, downmix: downmix)
            #expect(restored.wifiThreshold == .mbps1)
            #expect(restored.cellularThreshold == .kbps128)
            #expect(restored.conversionBitrate == .kbps96)
            #expect(!restored.downmixToStereo)
        }
    }

    @Test("Presets map to the nearest threshold and conversion bitrate")
    func presetMapping() {
        #expect(StreamSettings.migrated(preset: "original")?.threshold == .maximum)
        #expect(StreamSettings.migrated(preset: "original")?.conversion == nil)
        #expect(StreamSettings.migrated(preset: "mp3_320")?.threshold == .kbps320)
        #expect(StreamSettings.migrated(preset: "mp3_320")?.conversion == .kbps256)
        #expect(StreamSettings.migrated(preset: "mp3_192")?.threshold == .kbps192)
        #expect(StreamSettings.migrated(preset: "mp3_192")?.conversion == .kbps192)
        #expect(StreamSettings.migrated(preset: "flac") == nil)
    }

    @Test("Stored per-network presets migrate once and are removed")
    func migratesPerNetworkPresets() {
        withDefaults { defaults in
            defaults.set("original", forKey: "minidisc.stream.wifiQuality")
            defaults.set("mp3_192", forKey: "minidisc.stream.cellularQuality")
            let settings = StreamSettings(defaults: defaults, downmix: DownmixParameters())
            #expect(settings.wifiThreshold == .maximum)
            #expect(settings.cellularThreshold == .kbps192)
            #expect(settings.conversionBitrate == .kbps192)
            #expect(defaults.object(forKey: "minidisc.stream.wifiQuality") == nil)
            #expect(defaults.object(forKey: "minidisc.stream.cellularQuality") == nil)

            // A later change sticks; the old keys are gone, so nothing migrates again.
            settings.cellularThreshold = .kbps256
            #expect(StreamSettings(defaults: defaults, downmix: DownmixParameters()).cellularThreshold == .kbps256)
        }
    }

    @Test("Two converting presets keep the lower conversion bitrate")
    func lowerConversionWins() {
        withDefaults { defaults in
            defaults.set("mp3_320", forKey: "minidisc.stream.wifiQuality")
            defaults.set("mp3_192", forKey: "minidisc.stream.cellularQuality")
            let settings = StreamSettings(defaults: defaults, downmix: DownmixParameters())
            #expect(settings.wifiThreshold == .kbps320)
            #expect(settings.cellularThreshold == .kbps192)
            #expect(settings.conversionBitrate == .kbps192)
        }
    }

    @Test("The single pre-split preset seeds both networks")
    func migratesSinglePreset() {
        withDefaults { defaults in
            defaults.set("mp3_320", forKey: "minidisc.stream.quality")
            let settings = StreamSettings(defaults: defaults, downmix: DownmixParameters())
            #expect(settings.wifiThreshold == .kbps320)
            #expect(settings.cellularThreshold == .kbps320)
            #expect(settings.conversionBitrate == .kbps256)
            #expect(defaults.object(forKey: "minidisc.stream.quality") == nil)
        }
    }

    @Test("An only-Wi-Fi preset leaves cellular and the conversion at their defaults")
    func partialMigration() {
        withDefaults { defaults in
            defaults.set("original", forKey: "minidisc.stream.wifiQuality")
            let settings = StreamSettings(defaults: defaults, downmix: DownmixParameters())
            #expect(settings.wifiThreshold == .maximum)
            #expect(settings.cellularThreshold == StreamSettings.defaultCellularThreshold)
            #expect(settings.conversionBitrate == StreamSettings.defaultConversionBitrate)
        }
    }
}
