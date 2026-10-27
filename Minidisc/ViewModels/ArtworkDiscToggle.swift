import CoreGraphics
import Foundation

/// Where a click on the Mac player's artwork swaps it for the spinning MiniDisc (and back): a
/// circle in the middle of the artwork, a little over half its side, and never within reach of the
/// controls over it, the MiniPlayer's traffic lights and glass capsule at the top and its song,
/// scrubber and transport at the bottom. A click near a control, or anywhere around the edges where
/// the window is dragged from, leaves the artwork alone.
nonisolated struct ArtworkDiscHitArea: Equatable, Sendable {
    /// The circle's diameter as a share of the artwork's shorter side.
    static let fraction = 0.58
    /// How far a click stays from any control.
    static let controlClearance = 12.0

    /// The artwork's size.
    var size: CGSize
    /// The controls laid over the artwork, in its own coordinates (top-left origin).
    var controls: [CGRect] = []
    /// Other parts of the artwork that don't take the click, kept clear without the margin: the
    /// scrim fading in above the controls.
    var covered: [CGRect] = []

    var diameter: Double { max(Double(min(size.width, size.height)), 0) * Self.fraction }

    /// The circle's bounding square, centred on the artwork.
    var circle: CGRect {
        let side = diameter
        return CGRect(x: (Double(size.width) - side) / 2, y: (Double(size.height) - side) / 2, width: side, height: side)
    }

    /// Everything the click keeps out of: the controls with their margin, and the covered parts.
    var excluded: [CGRect] {
        controls.filter { !$0.isNull && !$0.isEmpty }
            .map { $0.insetBy(dx: -Self.controlClearance, dy: -Self.controlClearance) }
            + covered.filter { !$0.isNull && !$0.isEmpty }
    }

    func contains(_ point: CGPoint) -> Bool {
        let radius = diameter / 2
        guard radius > 0 else { return false }
        let dx = Double(point.x) - Double(size.width) / 2
        let dy = Double(point.y) - Double(size.height) / 2
        guard dx * dx + dy * dy <= radius * radius else { return false }
        return !excluded.contains { $0.contains(point) }
    }

    /// The part of the circle's square clear of the controls above and below its middle, for the
    /// tooltip; empty when the controls leave no room.
    var clearRect: CGRect {
        var rect = circle
        let middle = rect.midY
        for control in excluded where control.intersects(rect) {
            if control.midY < middle {
                let top = max(rect.minY, control.maxY)
                rect = CGRect(x: rect.minX, y: top, width: rect.width, height: max(rect.maxY - top, 0))
            } else {
                rect.size.height = max(control.minY - rect.minY, 0)
            }
        }
        return rect.height > 0 ? rect : .zero
    }
}

/// Whether a press on the artwork was a click that swaps it for the disc, rather than a drag of the
/// window (the MiniPlayer moves by its background) or part of a double-click. The window moves with
/// the pointer, so the pointer is compared on screen, and the window's frame as well.
nonisolated struct ArtworkDiscClick: Equatable, Sendable {
    /// How far the pointer may move between press and release and still count as a click.
    static let dragTolerance = 3.0

    /// Where the press happened, in screen coordinates.
    let screenLocation: CGPoint
    /// The window's frame at the press.
    let windowFrame: CGRect
    /// 1 for a single click; the second click of a double-click is 2.
    let clickCount: Int
    /// The press was inside the `ArtworkDiscHitArea`.
    let isInArea: Bool

    /// Whether the press moved past the tolerance, so it's a drag rather than a click.
    func isDrag(to screenLocation: CGPoint, windowFrame: CGRect) -> Bool {
        let dx = Double(screenLocation.x - self.screenLocation.x)
        let dy = Double(screenLocation.y - self.screenLocation.y)
        if dx * dx + dy * dy > Self.dragTolerance * Self.dragTolerance { return true }
        return Self.moved(self.windowFrame, windowFrame)
    }

    /// A single click that began and ended in the area, without moving the pointer or the window,
    /// toggles. A double-click toggles once, on its first click.
    func toggles(releasedAt screenLocation: CGPoint, windowFrame: CGRect, isInArea releasedInArea: Bool) -> Bool {
        clickCount == 1 && isInArea && releasedInArea && !isDrag(to: screenLocation, windowFrame: windowFrame)
    }

    private static func moved(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) > 0.5 || abs(a.minY - b.minY) > 0.5
            || abs(a.width - b.width) > 0.5 || abs(a.height - b.height) > 0.5
    }
}
