import CoreGraphics
import Foundation

/// Winamp's window docking, as rectangle maths: windows snap to each other and to screen edges
/// within 10 points, windows touching the main window move with it, and resizing or scaling
/// keeps the stack together. Works in any coordinate space whose axes match the screens'.
nonisolated enum WinampDocking {
    static let snapDistance: CGFloat = 10
    /// Edges this close count as touching, to absorb rounding.
    static let tolerance: CGFloat = 0.5

    // MARK: Snapping

    /// `frame` moved by the smallest offset on each axis that lines one of its edges up with an
    /// edge of another window or the inside of a screen's visible frame, if that offset is within
    /// `snapDistance`.
    static func snap(_ frame: CGRect, to others: [CGRect], screens: [CGRect] = []) -> CGRect {
        var bestX: CGFloat?
        var bestY: CGFloat?
        func consider(_ delta: CGFloat, _ best: inout CGFloat?) {
            guard abs(delta) <= snapDistance else { return }
            if best == nil || abs(delta) < abs(best!) { best = delta }
        }
        for other in others where other != frame {
            // Side by side: only when they overlap or nearly overlap vertically.
            if spans(frame.minY, frame.maxY, nearly: other.minY, other.maxY) {
                consider(other.maxX - frame.minX, &bestX)   // to the right of it
                consider(other.minX - frame.maxX, &bestX)   // to the left of it
                consider(other.minX - frame.minX, &bestX)   // left edges lined up
                consider(other.maxX - frame.maxX, &bestX)   // right edges lined up
            }
            if spans(frame.minX, frame.maxX, nearly: other.minX, other.maxX) {
                consider(other.maxY - frame.minY, &bestY)
                consider(other.minY - frame.maxY, &bestY)
                consider(other.minY - frame.minY, &bestY)
                consider(other.maxY - frame.maxY, &bestY)
            }
        }
        for screen in screens {
            consider(screen.minX - frame.minX, &bestX)
            consider(screen.maxX - frame.maxX, &bestX)
            consider(screen.minY - frame.minY, &bestY)
            consider(screen.maxY - frame.maxY, &bestY)
        }
        return frame.offsetBy(dx: bestX ?? 0, dy: bestY ?? 0)
    }

    private static func spans(_ aMin: CGFloat, _ aMax: CGFloat, nearly bMin: CGFloat, _ bMax: CGFloat) -> Bool {
        aMin <= bMax + snapDistance && bMin <= aMax + snapDistance
    }

    // MARK: Docked groups

    /// Whether two windows share part of an edge.
    static func areDocked(_ a: CGRect, _ b: CGRect) -> Bool {
        let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX) > tolerance
        let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY) > tolerance
        let sideBySide = abs(a.maxX - b.minX) <= tolerance || abs(b.maxX - a.minX) <= tolerance
        let stacked = abs(a.maxY - b.minY) <= tolerance || abs(b.maxY - a.minY) <= tolerance
        return (sideBySide && verticalOverlap) || (stacked && horizontalOverlap)
    }

    /// The windows docked to `root` directly or through other docked windows, not including it.
    static func dockedGroup(root: Int, frames: [CGRect]) -> Set<Int> {
        guard frames.indices.contains(root) else { return [] }
        var group: Set<Int> = [root]
        var queue = [root]
        while let current = queue.popLast() {
            for index in frames.indices where !group.contains(index) && areDocked(frames[current], frames[index]) {
                group.insert(index)
                queue.append(index)
            }
        }
        group.remove(root)
        return group
    }

    /// Frames after the window at `root` moves by `delta`: the windows in `followers` move with
    /// it and the rest stay. A window dragged on its own has no followers, which undocks it.
    static func move(_ frames: [CGRect], root: Int, followers: Set<Int>, by delta: CGVector) -> [CGRect] {
        frames.enumerated().map { index, frame in
            index == root || followers.contains(index) ? frame.offsetBy(dx: delta.dx, dy: delta.dy) : frame
        }
    }

    // MARK: Resizing

    /// Frames after the window at `index` changes to `newFrame` (as for windowshade or a playlist
    /// resize), keeping its top-left corner. Windows docked below or to the right of it, and
    /// those docked to them, move by the change of its bottom or right edge, so the stack keeps
    /// touching. The coordinate space has y growing upwards, as AppKit's screens do.
    static func resize(_ frames: [CGRect], index: Int, to newFrame: CGRect) -> [CGRect] {
        guard frames.indices.contains(index) else { return frames }
        let old = frames[index]
        var result = frames
        result[index] = newFrame
        let dropY = newFrame.minY - old.minY        // bottom edge moves down by -dropY
        let pushX = newFrame.maxX - old.maxX
        var moved: Set<Int> = [index]
        var queue: [(Int, CGRect)] = [(index, old)]
        while let (current, before) = queue.popLast() {
            for other in frames.indices where !moved.contains(other) {
                let frame = frames[other]
                let horizontalOverlap = min(before.maxX, frame.maxX) - max(before.minX, frame.minX) > tolerance
                let verticalOverlap = min(before.maxY, frame.maxY) - max(before.minY, frame.minY) > tolerance
                let below = abs(frame.maxY - before.minY) <= tolerance && horizontalOverlap
                let right = abs(frame.minX - before.maxX) <= tolerance && verticalOverlap
                guard below || right else { continue }
                moved.insert(other)
                // Followers of the resized window take its edge change; theirs follow them.
                let dx = current == index ? (right ? pushX : 0) : result[current].minX - frames[current].minX
                let dy = current == index ? (below ? dropY : 0) : result[current].minY - frames[current].minY
                result[other] = frame.offsetBy(dx: dx, dy: dy)
                queue.append((other, frame))
            }
        }
        return result
    }

    /// Frames scaled by `factor` about the top-left corner of the window at `anchor`, for Double
    /// Size: every window doubles or halves and docked windows stay docked.
    static func scale(_ frames: [CGRect], anchor: Int, by factor: CGFloat) -> [CGRect] {
        guard frames.indices.contains(anchor), factor > 0 else { return frames }
        let origin = CGPoint(x: frames[anchor].minX, y: frames[anchor].maxY)
        return frames.map { frame in
            let left = origin.x + (frame.minX - origin.x) * factor
            let top = origin.y + (frame.maxY - origin.y) * factor
            let size = CGSize(width: frame.width * factor, height: frame.height * factor)
            return CGRect(x: left, y: top - size.height, width: size.width, height: size.height)
        }
    }
}
