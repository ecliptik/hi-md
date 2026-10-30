import Testing
@testable import Minidisc

@Suite("MilkDrop preset order")
struct MilkDropPresetOrderTests {
    @Test func everyPresetPlaysOnceBeforeAnyRepeats() {
        var order = MilkDropPresetOrder(count: 7)
        var random = SeededRandom(seed: 42)
        let pass = (0..<7).compactMap { _ in order.next(using: &random) }
        #expect(Set(pass) == Set(0..<7))
    }

    @Test func previousGoesBackThroughWhatPlayedAndNextReplaysIt() {
        var order = MilkDropPresetOrder(count: 5)
        var random = SeededRandom(seed: 7)
        let played = (0..<3).compactMap { _ in order.next(using: &random) }
        #expect(order.previous() == played[1])
        #expect(order.previous() == played[0])
        #expect(order.previous() == played[0], "nothing before the first")
        #expect(order.next(using: &random) == played[1])
        #expect(order.next(using: &random) == played[2])
    }

    @Test func aNewPassNeverRepeatsTheLastPreset() {
        for seed in 0..<200 {
            var order = MilkDropPresetOrder(count: 3)
            var random = SeededRandom(seed: UInt64(seed))
            var last: Int?
            for _ in 0..<12 {
                let next = order.next(using: &random)
                #expect(next != last)
                last = next
            }
        }
    }

    @Test func noPresetsMeansNothingToPlay() {
        var order = MilkDropPresetOrder(count: 0)
        #expect(order.next() == nil)
        #expect(order.previous() == nil)
        #expect(order.current == nil)
    }
}
