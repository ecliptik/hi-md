import SwiftUI

@main
struct MinidiscWatchApp: App {
    @State private var session = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                NowPlayingWatchView(session: session)
            }
            .onAppear { session.activate() }
        }
    }
}
