import Foundation
import Testing
import UIKit
@testable import Minidisc

@Suite("Watch messages")
struct WatchMessagesTests {
    @Test func nowPlayingRoundTrips() throws {
        var state = WatchNowPlaying()
        state.title = "Matin tranquille"
        state.artist = "Atelier Minidisc"
        state.isPlaying = true
        state.canFavorite = true
        state.moods = [WatchMood(id: "chill", title: "Chill", symbolName: "leaf")]
        let data = try #require(state.encoded)
        #expect(WatchNowPlaying.decode(data) == state)
        #expect(!WatchNowPlaying().hasTrack)
    }

    @Test func commandsRoundTrip() throws {
        for command in [WatchCommand.togglePlayPause, .next, .previous, .toggleFavorite, .playMood("focus")] {
            let data = try #require(command.encoded)
            #expect(WatchCommand.decode(data) == command)
        }
        #expect(WatchCommand.decode(Data("nonsense".utf8)) == nil)
    }

    @Test func thumbnailsStaySmall() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
        }
        let data = try #require(PhoneWatchBridge.thumbnail(image))
        #expect(data.count < 20_000)
    }
}
