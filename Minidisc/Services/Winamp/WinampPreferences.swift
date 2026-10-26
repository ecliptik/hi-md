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

/// Winamp mode's window and skin settings, kept in user defaults between launches.
final class WinampPreferences {
    enum Key {
        /// Shared with the menu's `@AppStorage` toggle.
        static let isOpen = "minidisc.winamp.isOpen"
        static let windowTopLeft = "minidisc.winamp.windowTopLeft"
        static let isDoubleSize = "minidisc.winamp.doubleSize"
        static let isAlwaysOnTop = "minidisc.winamp.alwaysOnTop"
        static let visualizerMode = "minidisc.winamp.visualizerMode"
        static let timeMode = "minidisc.winamp.timeMode"
        static let skinName = "minidisc.winamp.skin.name"
        static let skinBookmark = "minidisc.winamp.skin.bookmark"
        static let skinIsSecurityScoped = "minidisc.winamp.skin.securityScoped"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    var isDoubleSize: Bool {
        get { defaults.bool(forKey: Key.isDoubleSize) }
        set { defaults.set(newValue, forKey: Key.isDoubleSize) }
    }

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
