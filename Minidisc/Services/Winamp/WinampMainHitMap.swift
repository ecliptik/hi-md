import CoreGraphics
import Foundation

/// Something in the main window that reacts to the mouse.
nonisolated enum WinampMainControl: Sendable, Hashable {
    case options
    case minimize
    case shade
    case close
    /// The rest of the title bar, which drags the window.
    case titleBar
    case clutter(WinampClutterButton)
    case time
    case visualizer
    case songTitle
    case volume
    case balance
    case equalizer
    case playlist
    case seek
    case previous
    case play
    case pause
    case stop
    case next
    case eject
    case shuffle
    case repeatToggle

    /// Controls that act on release and draw pressed while held.
    var isButton: Bool {
        switch self {
        case .options, .minimize, .shade, .close, .clutter, .equalizer, .playlist,
             .previous, .play, .pause, .stop, .next, .eject, .shuffle, .repeatToggle:
            true
        case .titleBar, .time, .visualizer, .songTitle, .volume, .balance, .seek:
            false
        }
    }
}

/// Which control is under a point of the 275×116 main window, built from `WinampMainLayout`
/// and the sprite sizes. Earlier regions win where two overlap, so the title-bar buttons come
/// before the title bar they sit on.
nonisolated struct WinampMainHitMap: Sendable {
    struct Region: Sendable, Hashable {
        let control: WinampMainControl
        let rect: CGRect
    }

    let regions: [Region]

    static let classic = WinampMainHitMap(regions: classicRegions())

    func control(at point: CGPoint) -> WinampMainControl? {
        regions.first { $0.rect.contains(point) }?.control
    }

    func rect(for control: WinampMainControl) -> CGRect? {
        regions.first { $0.control == control }?.rect
    }

    private static func classicRegions() -> [Region] {
        typealias Layout = WinampMainLayout
        func at(_ origin: CGPoint, _ sprite: WinampSprite) -> CGRect {
            CGRect(x: origin.x, y: origin.y, width: CGFloat(sprite.width), height: CGFloat(sprite.height))
        }
        var regions: [Region] = [
            Region(control: .options, rect: at(Layout.options, WinampSprites.options.normal)),
            Region(control: .minimize, rect: at(Layout.minimize, WinampSprites.minimize.normal)),
            Region(control: .shade, rect: at(Layout.shade, WinampSprites.shade.normal)),
            Region(control: .close, rect: at(Layout.close, WinampSprites.close.normal)),
            Region(control: .titleBar, rect: Layout.titleBar),
        ]
        for button in WinampClutterButton.allCases {
            let rows = button.rows
            regions.append(Region(control: .clutter(button), rect: CGRect(
                x: Layout.clutterBar.x, y: Layout.clutterBar.y + CGFloat(rows.top),
                width: CGFloat(WinampSprites.clutterBar.width), height: CGFloat(rows.height)
            )))
        }
        let firstDigit = Layout.timeMinus.x
        let lastDigit = Layout.timeDigits[Layout.timeDigits.count - 1]
        regions += [
            Region(control: .time, rect: CGRect(x: firstDigit, y: lastDigit.y,
                                                width: lastDigit.x + 9 - firstDigit, height: 13)),
            Region(control: .visualizer, rect: Layout.visualizer),
            Region(control: .songTitle, rect: Layout.title.insetBy(dx: 0, dy: -3)),
            Region(control: .volume, rect: Layout.volume),
            Region(control: .balance, rect: Layout.balance),
            Region(control: .equalizer, rect: at(Layout.equalizerToggle, WinampSprites.equalizerToggle.off.normal)),
            Region(control: .playlist, rect: at(Layout.playlistToggle, WinampSprites.playlistToggle.off.normal)),
            Region(control: .seek, rect: Layout.seekBar),
            Region(control: .previous, rect: at(Layout.previous, WinampSprites.previous.normal)),
            Region(control: .play, rect: at(Layout.play, WinampSprites.play.normal)),
            Region(control: .pause, rect: at(Layout.pause, WinampSprites.pause.normal)),
            Region(control: .stop, rect: at(Layout.stop, WinampSprites.stop.normal)),
            Region(control: .next, rect: at(Layout.next, WinampSprites.next.normal)),
            Region(control: .eject, rect: at(Layout.eject, WinampSprites.eject.normal)),
            Region(control: .repeatToggle, rect: at(Layout.repeatToggle, WinampSprites.repeatToggle.off.normal)),
            Region(control: .shuffle, rect: at(Layout.shuffle, WinampSprites.shuffleToggle.off.normal)),
        ]
        return regions
    }
}

/// A skin's `region.txt` outline for the main window, as a hit test and a clip path.
nonisolated struct WinampWindowShape: Sendable {
    /// Even-odd polygons in window pixels; empty means the whole rectangle.
    let polygons: [[CGPoint]]

    init(polygons: [[CGPoint]]) {
        self.polygons = polygons.filter { $0.count >= 3 }
    }

    /// The `normal` section of a skin's regions.
    init(skin: WinampSkin) {
        self.init(polygons: skin.regions["normal"] ?? [])
    }

    var isRectangular: Bool { polygons.isEmpty }

    /// A path in the window's top-left coordinates.
    var path: CGPath? {
        guard !isRectangular else { return nil }
        let path = CGMutablePath()
        for polygon in polygons {
            path.addLines(between: polygon)
            path.closeSubpath()
        }
        return path
    }

    /// Whether a point in the window's top-left coordinates is inside the shape.
    func contains(_ point: CGPoint) -> Bool {
        guard let path else { return true }
        return path.contains(point, using: .evenOdd)
    }
}
