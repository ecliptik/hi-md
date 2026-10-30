import Foundation

/// The order MilkDrop plays presets in: a shuffled pass through all of them before any repeats,
/// with a history so Previous goes back to what was actually on screen. Indexes are positions in
/// the preset list it was made for.
nonisolated struct MilkDropPresetOrder: Sendable, Equatable {
    private(set) var count: Int
    private var bag: [Int] = []
    private var history: [Int] = []
    /// Where in `history` the current preset is.
    private var position = -1

    init(count: Int) {
        self.count = max(0, count)
    }

    var current: Int? { history.indices.contains(position) ? history[position] : nil }

    /// Forward through the history after going back, then a fresh preset from the shuffled pass.
    mutating func next<R: RandomNumberGenerator>(using random: inout R) -> Int? {
        guard count > 0 else { return nil }
        if position + 1 < history.count {
            position += 1
            return history[position]
        }
        if bag.isEmpty {
            bag = Array(0..<count).shuffled(using: &random)
            // Never the same preset twice in a row across passes.
            if count > 1, bag.last == current { bag.swapAt(bag.count - 1, 0) }
        }
        let index = bag.removeLast()
        history.append(index)
        // Keep the history bounded; MilkDrop sessions can run for hours.
        if history.count > 500 { history.removeFirst(history.count - 500) }
        position = history.count - 1
        return index
    }

    mutating func previous() -> Int? {
        guard position > 0 else { return current }
        position -= 1
        return history[position]
    }

    mutating func next() -> Int? {
        var random = SystemRandomNumberGenerator()
        return next(using: &random)
    }
}
