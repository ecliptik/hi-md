import CoreGraphics
import Foundation

/// The skin Winamp mode draws with.
nonisolated enum WinampSkinChoice: Sendable, Hashable {
    /// Minidisc Gold, bundled with the app.
    case bundled
    /// A `.wsz` the listener opened. `bookmark` locates it again after a relaunch; it is
    /// security-scoped when `isSecurityScoped`, or a plain bookmark to a copy in the container.
    case custom(name: String, bookmark: Data, isSecurityScoped: Bool)
}

/// Winamp mode's zoom levels, in skin pixels per point. Double Size is 2×.
nonisolated enum WinampZoom {
    static let levels = 1...4

    static func clamped(_ level: Int) -> Int {
        min(max(level, levels.lowerBound), levels.upperBound)
    }

    /// The clutter bar's D: normal size goes to Double Size, and any zoom goes back to 1×.
    static func toggledDoubleSize(from level: Int) -> Int {
        level == 1 ? 2 : 1
    }

    /// "1×" to "4×", the same in every language.
    static func title(_ level: Int) -> String {
        "\(level)×"
    }
}

/// Winamp mode's window and skin settings, kept in user defaults between launches.
final class WinampPreferences {
    enum Key {
        /// Shared with the menu's `@AppStorage` toggle.
        static let isOpen = "minidisc.winamp.isOpen"
        static let windowTopLeft = "minidisc.winamp.windowTopLeft"
        /// Double Size from before zoom levels: still written, so an older build keeps its size.
        static let isDoubleSize = "minidisc.winamp.doubleSize"
        /// Shared with the View menu's `@AppStorage` zoom items.
        static let zoom = "minidisc.winamp.zoom"
        static let isAlwaysOnTop = "minidisc.winamp.alwaysOnTop"
        static let visualizerMode = "minidisc.winamp.visualizerMode"
        static let timeMode = "minidisc.winamp.timeMode"
        static let skinName = "minidisc.winamp.skin.name"
        static let skinBookmark = "minidisc.winamp.skin.bookmark"
        static let skinIsSecurityScoped = "minidisc.winamp.skin.securityScoped"
        static let isMainShaded = "minidisc.winamp.main.shaded"
        static let isEqualizerOpen = "minidisc.winamp.equalizer.isOpen"
        static let equalizerTopLeft = "minidisc.winamp.equalizer.topLeft"
        static let isEqualizerShaded = "minidisc.winamp.equalizer.shaded"
        static let isEqualizerAuto = "minidisc.winamp.equalizer.auto"
        static let equalizerPresets = "minidisc.winamp.equalizer.presets"
        static let isPlaylistOpen = "minidisc.winamp.playlist.isOpen"
        static let playlistTopLeft = "minidisc.winamp.playlist.topLeft"
        static let isPlaylistShaded = "minidisc.winamp.playlist.shaded"
        static let playlistSize = "minidisc.winamp.playlist.size"
    }

    /// Winamp mode's three windows.
    enum Window: CaseIterable, Sendable {
        case main
        case equalizer
        case playlist
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Double Size from before zoom levels becomes 2×, so the View menu's items show it.
        if defaults.object(forKey: Key.zoom) == nil, defaults.bool(forKey: Key.isDoubleSize) {
            defaults.set(2, forKey: Key.zoom)
        }
    }

    var isOpen: Bool {
        get { defaults.bool(forKey: Key.isOpen) }
        set { defaults.set(newValue, forKey: Key.isOpen) }
    }

    /// The window's top-left corner in screen coordinates, so it stays put when the size doubles.
    var windowTopLeft: CGPoint? {
        get {
            guard let values = defaults.array(forKey: Key.windowTopLeft) as? [Double], values.count == 2,
                  values.allSatisfy(\.isFinite) else { return nil }
            return CGPoint(x: values[0], y: values[1])
        }
        set {
            if let newValue, newValue.x.isFinite, newValue.y.isFinite {
                defaults.set([Double(newValue.x), Double(newValue.y)], forKey: Key.windowTopLeft)
            } else {
                defaults.removeObject(forKey: Key.windowTopLeft)
            }
        }
    }

    /// A window's top-left corner in screen coordinates; the main window's is `windowTopLeft`.
    func topLeft(of window: Window) -> CGPoint? {
        switch window {
        case .main: windowTopLeft
        case .equalizer: point(forKey: Key.equalizerTopLeft)
        case .playlist: point(forKey: Key.playlistTopLeft)
        }
    }

    func setTopLeft(_ point: CGPoint?, of window: Window) {
        switch window {
        case .main: windowTopLeft = point
        case .equalizer: setPoint(point, forKey: Key.equalizerTopLeft)
        case .playlist: setPoint(point, forKey: Key.playlistTopLeft)
        }
    }

    /// Whether the equaliser or playlist window is shown while Winamp mode is on. The main
    /// window's is `isOpen`.
    func isVisible(_ window: Window) -> Bool {
        switch window {
        case .main: isOpen
        case .equalizer: defaults.bool(forKey: Key.isEqualizerOpen)
        case .playlist: defaults.bool(forKey: Key.isPlaylistOpen)
        }
    }

    func setVisible(_ visible: Bool, _ window: Window) {
        switch window {
        case .main: isOpen = visible
        case .equalizer: defaults.set(visible, forKey: Key.isEqualizerOpen)
        case .playlist: defaults.set(visible, forKey: Key.isPlaylistOpen)
        }
    }

    func isShaded(_ window: Window) -> Bool {
        defaults.bool(forKey: shadeKey(window))
    }

    func setShaded(_ shaded: Bool, _ window: Window) {
        defaults.set(shaded, forKey: shadeKey(window))
    }

    private func shadeKey(_ window: Window) -> String {
        switch window {
        case .main: Key.isMainShaded
        case .equalizer: Key.isEqualizerShaded
        case .playlist: Key.isPlaylistShaded
        }
    }

    var playlistSize: WinampPlaylistSize {
        get {
            guard let values = defaults.array(forKey: Key.playlistSize) as? [Int], values.count == 2 else { return .standard }
            return WinampPlaylistSize(widthSteps: values[0], heightSteps: values[1])
        }
        set { defaults.set([newValue.widthSteps, newValue.heightSteps], forKey: Key.playlistSize) }
    }

    var isEqualizerAuto: Bool {
        get { defaults.bool(forKey: Key.isEqualizerAuto) }
        set { defaults.set(newValue, forKey: Key.isEqualizerAuto) }
    }

    /// Presets saved or imported in the equaliser window, by name.
    var equalizerPresets: [WinampEqualizerPreset] {
        get {
            guard let data = defaults.data(forKey: Key.equalizerPresets),
                  let presets = try? JSONDecoder().decode([WinampEqualizerPreset].self, from: data) else { return [] }
            return presets
        }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: Key.equalizerPresets)
            } else if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.equalizerPresets)
            }
        }
    }

    /// Adds `preset`, replacing one with the same name.
    func saveEqualizerPreset(_ preset: WinampEqualizerPreset) {
        var presets = equalizerPresets.filter { $0.name.caseInsensitiveCompare(preset.name) != .orderedSame }
        presets.append(preset)
        equalizerPresets = presets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func deleteEqualizerPreset(named name: String) {
        equalizerPresets = equalizerPresets.filter { $0.name != name }
    }

    private func point(forKey key: String) -> CGPoint? {
        guard let values = defaults.array(forKey: key) as? [Double], values.count == 2,
              values.allSatisfy(\.isFinite) else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    private func setPoint(_ point: CGPoint?, forKey key: String) {
        if let point, point.x.isFinite, point.y.isFinite {
            defaults.set([Double(point.x), Double(point.y)], forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Skin pixels per point for every Winamp window: 1× to 4×.
    var zoom: Int {
        get {
            guard let level = defaults.object(forKey: Key.zoom) as? Int else {
                return defaults.bool(forKey: Key.isDoubleSize) ? 2 : 1
            }
            return WinampZoom.clamped(level)
        }
        set {
            let level = WinampZoom.clamped(newValue)
            defaults.set(level, forKey: Key.zoom)
            defaults.set(level > 1, forKey: Key.isDoubleSize)
        }
    }

    /// The clutter bar's D is lit at any zoom above 1×.
    var isDoubleSize: Bool { zoom > 1 }

    var isAlwaysOnTop: Bool {
        get { defaults.bool(forKey: Key.isAlwaysOnTop) }
        set { defaults.set(newValue, forKey: Key.isAlwaysOnTop) }
    }

    /// Spectrum unless the listener picked another mode.
    var visualizerMode: WinampVisualizerMode {
        get { defaults.string(forKey: Key.visualizerMode).flatMap(WinampVisualizerMode.init(rawValue:)) ?? .spectrum }
        set { defaults.set(newValue.rawValue, forKey: Key.visualizerMode) }
    }

    var timeMode: WinampTimeMode {
        get { defaults.string(forKey: Key.timeMode).flatMap(WinampTimeMode.init(rawValue:)) ?? .elapsed }
        set { defaults.set(newValue.rawValue, forKey: Key.timeMode) }
    }

    var skin: WinampSkinChoice {
        get {
            guard let bookmark = defaults.data(forKey: Key.skinBookmark), !bookmark.isEmpty else { return .bundled }
            return .custom(
                name: defaults.string(forKey: Key.skinName) ?? "",
                bookmark: bookmark,
                isSecurityScoped: defaults.object(forKey: Key.skinIsSecurityScoped) as? Bool ?? true
            )
        }
        set {
            switch newValue {
            case .bundled:
                defaults.removeObject(forKey: Key.skinBookmark)
                defaults.removeObject(forKey: Key.skinName)
                defaults.removeObject(forKey: Key.skinIsSecurityScoped)
            case .custom(let name, let bookmark, let isSecurityScoped):
                defaults.set(bookmark, forKey: Key.skinBookmark)
                defaults.set(name, forKey: Key.skinName)
                defaults.set(isSecurityScoped, forKey: Key.skinIsSecurityScoped)
            }
        }
    }
}
