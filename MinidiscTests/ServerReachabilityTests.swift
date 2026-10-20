import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Server reachability")
struct ServerReachabilityTests {
    private let wifi = NetworkPathDescriptor(
        isOnline: true, isExpensive: false, isConstrained: false,
        supportsDNS: true, supportsIPv4: true, supportsIPv6: true,
        interfaces: [.wifi], gateways: ["gateway-a"]
    )

    @Test("An unreachable server makes a satisfied path offline, and its return is a new generation")
    func reachabilityIsFoldedIntoThePath() throws {
        let reducer = NetworkPathEventReducer()
        #expect(reducer.reduce(wifi).isOnline)

        let lost = try #require(reducer.reduceServerReachability(false))
        #expect(!lost.isOnline)
        #expect(lost.generation == 1)

        let back = try #require(reducer.reduceServerReachability(true))
        #expect(back.isOnline)
        #expect(back.generation == 2)
    }

    @Test("Repeating the same reachability publishes nothing")
    func unchangedReachabilityIsSilent() {
        let reducer = NetworkPathEventReducer()
        _ = reducer.reduce(wifi)
        #expect(reducer.reduceServerReachability(true) == nil)
        _ = reducer.reduceServerReachability(false)
        #expect(reducer.reduceServerReachability(false) == nil)
    }

    @Test("Reachability before any path is observed is ignored")
    func reachabilityWaitsForAPath() {
        #expect(NetworkPathEventReducer().reduceServerReachability(false) == nil)
    }

    @Test("A path change keeps an unreachable server offline until it answers")
    func pathChangeKeepsServerState() {
        let reducer = NetworkPathEventReducer()
        _ = reducer.reduce(wifi)
        _ = reducer.reduceServerReachability(false)
        let cellular = NetworkPathDescriptor(
            isOnline: true, isExpensive: true, isConstrained: false,
            supportsDNS: true, supportsIPv4: true, supportsIPv6: true,
            interfaces: [.cellular], gateways: []
        )
        #expect(!reducer.reduce(cellular).isOnline)
    }

    @Test("Only failures to reach the server count as unreachable")
    func errorClassification() {
        #expect(ServerReachability.isUnreachable(URLError(.timedOut)))
        #expect(ServerReachability.isUnreachable(SwiftSonicError.network(URLError(.cannotFindHost))))
        #expect(!ServerReachability.isUnreachable(SwiftSonicError.httpError(statusCode: 502, endpoint: "ping", serverHost: nil)))
        #expect(!ServerReachability.isUnreachable(CocoaError(.fileReadCorruptFile)))
    }
}

@Suite("Tailscale server addresses")
@MainActor
struct TailscaleServerAddressTests {
    private func service() throws -> ServerService {
        ServerService(state: ServerState(), keychain: MockKeychain(),
                      modelContainer: try ModelContainer.minidisc(inMemory: true),
                      audioStreamCache: MockAudioStreamCache())
    }

    @Test("An IPv6 literal is refused with its own error before any request")
    func ipv6LiteralIsRefused() async throws {
        await #expect(throws: ConnectionTestError.ipv6Unsupported) {
            try await service().testConnection(url: "http://[fd7a:115c:a1e0::1234]:4533", username: "u", password: "p", customHeaders: [:])
        }
    }

    @Test("A pasted trailing newline does not make the address invalid")
    func trailingNewlineIsTrimmed() async throws {
        do {
            try await service().testConnection(url: "http://127.0.0.1:9\n", username: "u", password: "p", customHeaders: [:])
        } catch let error as ConnectionTestError {
            #expect(error != .invalidURL)
        } catch {}
    }

    @Test("The server-not-found message mentions the VPN")
    func dnsMessageMentionsVPN() {
        let description = String(localized: ConnectionTestError.dnsFailure.presentation.description)
        #expect(description.contains("Tailscale"))
    }
}

@Suite("Pending scrobbles")
struct PendingScrobbleQueueTests {
    private func fileURL() -> URL {
        URL.temporaryDirectory.appendingPathComponent("scrobbles-\(UUID()).json")
    }

    @Test("Queued plays survive a relaunch and stay with their server")
    func queueSurvivesRelaunch() async {
        let url = fileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let home = UUID(), other = UUID()
        let first = PendingScrobble(songId: "a", serverId: home, playedAt: Date(timeIntervalSince1970: 100))
        let second = PendingScrobble(songId: "b", serverId: home, playedAt: Date(timeIntervalSince1970: 200))

        let queue = PendingScrobbleQueue(fileURL: url)
        await queue.enqueue(first)
        await queue.enqueue(PendingScrobble(songId: "x", serverId: other, playedAt: Date()))
        await queue.enqueue(second)

        let relaunched = PendingScrobbleQueue(fileURL: url)
        #expect(await relaunched.pending(serverId: home) == [first, second])
        await relaunched.remove(first)
        #expect(await PendingScrobbleQueue(fileURL: url).pending(serverId: home) == [second])
        #expect(await relaunched.count == 2)
    }

    @Test("The oldest plays are dropped once the queue is full")
    func queueIsBounded() async {
        let url = fileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = PendingScrobbleQueue(fileURL: url)
        let server = UUID()
        for index in 0..<(PendingScrobbleQueue.capacity + 3) {
            await queue.enqueue(PendingScrobble(songId: "\(index)", serverId: server, playedAt: Date()))
        }
        let pending = await queue.pending(serverId: server)
        #expect(pending.count == PendingScrobbleQueue.capacity)
        #expect(pending.first?.songId == "3")
    }

    // A Subsonic `.api` refusal is the one case that is not retried; SubsonicAPIError has no public
    // initializer, so that branch is covered by reading LibraryService.isWorthRetrying.
    @Test("Unreachable and temporarily failing servers are retried")
    func retryClassification() {
        #expect(LibraryService.isWorthRetrying(URLError(.notConnectedToInternet)))
        #expect(LibraryService.isWorthRetrying(SwiftSonicError.network(URLError(.timedOut))))
        #expect(LibraryService.isWorthRetrying(SwiftSonicError.httpError(statusCode: 503, endpoint: "scrobble", serverHost: nil)))
    }
}

private actor ScriptedProbe {
    private var result: ServerReachability = .unreachable
    private(set) var calls = 0
    func set(_ result: ServerReachability) { self.result = result }
    func next() -> ServerReachability { calls += 1; return result }
}

@Suite("Network monitor with an unreachable server", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct NetworkMonitorReachabilityTests {
    @Test("Two failed pings take the app offline; an answer brings it back")
    func unreachableServerTogglesOnlineState() async throws {
        let probe = ScriptedProbe()
        let serverState = ServerState()
        let monitor = NetworkMonitor()
        monitor.start(serverState: serverState, streamSettings: StreamSettings(), playerService: MockPlayerService(),
                      serverProbe: { await probe.next() })
        defer { monitor.stop() }

        #expect(await pollUntil(timeout: .seconds(20)) { !serverState.isOnline })
        #expect(await probe.calls >= 2)
        let offlineGeneration = serverState.networkPathEvent.generation

        await probe.set(.reachable)
        monitor.checkServerReachability()

        #expect(await pollUntil(timeout: .seconds(10)) { serverState.isOnline })
        #expect(serverState.networkPathEvent.generation > offlineGeneration)
    }
}
