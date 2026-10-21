import Foundation
import Observation
import WatchConnectivity

/// The watch's view of the phone: the last Now Playing state it published, and a way to send
/// commands back.
@Observable
@MainActor
final class WatchSessionModel {
    private(set) var nowPlaying = WatchNowPlaying()
    private(set) var isReachable = false
    @ObservationIgnored private var delegate: Delegate?

    func activate() {
        guard WCSession.isSupported(), delegate == nil else { return }
        let delegate = Delegate(model: self)
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    func send(_ command: WatchCommand) {
        guard let data = command.encoded, WCSession.default.isReachable else { return }
        // Show the change at once; the phone's next update confirms it.
        switch command {
        case .togglePlayPause: nowPlaying.isPlaying.toggle()
        case .toggleFavorite: nowPlaying.isFavorite.toggle()
        default: break
        }
        WCSession.default.sendMessage([WatchMessageKey.command: data], replyHandler: nil)
    }

    fileprivate func receive(_ context: [String: Any]) {
        guard let data = context[WatchMessageKey.nowPlaying] as? Data,
              let value = WatchNowPlaying.decode(data) else { return }
        nowPlaying = value
    }

    fileprivate func setReachable(_ reachable: Bool) { isReachable = reachable }

    /// WatchConnectivity calls back on its own queue; this hops each update to the main actor.
    private final class Delegate: NSObject, WCSessionDelegate, @unchecked Sendable {
        private weak var model: WatchSessionModel?

        init(model: WatchSessionModel) { self.model = model }

        nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
            let context = session.receivedApplicationContext[WatchMessageKey.nowPlaying] as? Data
            let reachable = session.isReachable
            Task { @MainActor [weak self] in
                if let context { self?.model?.receive([WatchMessageKey.nowPlaying: context]) }
                self?.model?.setReachable(reachable)
            }
        }

        nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
            guard let data = applicationContext[WatchMessageKey.nowPlaying] as? Data else { return }
            Task { @MainActor [weak self] in self?.model?.receive([WatchMessageKey.nowPlaying: data]) }
        }

        nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
            let reachable = session.isReachable
            Task { @MainActor [weak self] in self?.model?.setReachable(reachable) }
        }
    }
}
