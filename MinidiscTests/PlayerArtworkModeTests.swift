import Testing
@testable import Minidisc

@Suite("Player artwork modes")
struct PlayerArtworkModeTests {
    @Test func theIPhoneCyclesWithoutMilkDrop() {
        var mode = PlayerArtworkMode.artwork
        var seen: [PlayerArtworkMode] = []
        for _ in 0..<4 {
            mode = mode.next
            seen.append(mode)
        }
        #expect(seen == [.disc, .spectrum, .scope, .artwork])
        #expect(!PlayerArtworkMode.available.contains(.milkDrop))
        #expect(PlayerArtworkMode.milkDrop.next == .artwork, "a Mac setting of MilkDrop falls back to the cover")
    }
}
