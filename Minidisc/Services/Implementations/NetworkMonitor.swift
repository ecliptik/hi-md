import Foundation
import Network
import OSLog
import Synchronization
import SwiftSonic

/// Reduces callback-thread `NWPath` values before the buffering AsyncStream boundary.
///
/// Advancing the generation here means a quick Wi-Fi → offline → Wi-Fi sequence still arrives on
/// the MainActor as generation +2 even when `.bufferingNewest(1)` coalesces the middle snapshot.
nonisolated final class NetworkPathEventReducer: Sendable {
    private struct State: Sendable {
        var path: NetworkPathDescriptor?
        var serverReachable = true
        var descriptor: NetworkPathDescriptor?
        var generation: UInt64 = 0
    }

    private let state = Mutex(State())

    func reduce(_ descriptor: NetworkPathDescriptor) -> NetworkPathEvent {
        state.withLock { state in
            state.path = descriptor
            return Self.publish(&state)
        }
    }

    /// Folds whether the media server answers into the path. A satisfied path with an unreachable
    /// server is offline for this app, for example Wi-Fi up while the VPN to the server is down.
    /// Returns nil when nothing changed or no path has been observed yet.
    func reduceServerReachability(_ reachable: Bool) -> NetworkPathEvent? {
        state.withLock { state in
            guard state.path != nil, state.serverReachable != reachable else { return nil }
            state.serverReachable = reachable
            return Self.publish(&state)
        }
    }

    private static func publish(_ state: inout State) -> NetworkPathEvent {
        let path = state.path ?? .unknown
        let effective = path.withOnline(path.isOnline && state.serverReachable)
        if let previous = state.descriptor, previous != effective {
            state.generation &+= 1
        }
        state.descriptor = effective
        return NetworkPathEvent(generation: state.generation, descriptor: effective)
    }
}

/// Whether the active server answered a lightweight request.
nonisolated enum ServerReachability: Sendable {
    case reachable
    case unreachable
    /// No server is configured, so there is nothing to reach.
    case notApplicable

    /// Pings the active server. Only failures to reach it count; an HTTP or Subsonic error means
    /// the server answered.
    static func probe(_ serverService: any ServerServiceProtocol) async -> ServerReachability {
        guard let connection = try? await serverService.activeConnection() else { return .notApplicable }
        do {
            try await connection.makeSwiftSonicClient(requestTimeout: 6, retryPolicy: .none).ping()
            return .reachable
        } catch {
            return isUnreachable(error) ? .unreachable : .reachable
        }
    }

    static func isUnreachable(_ error: any Error) -> Bool {
        if let error = error as? SwiftSonicError, case .network = error { return true }
        return error is URLError
    }
}

@MainActor
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.minidisc.network", qos: .utility)
    private let reducer = NetworkPathEventReducer()
    private let playbackDiagnostics: PlaybackDiagnostics
    private var updateTask: Task<Void, Never>?
    private var updateContinuation: AsyncStream<NetworkPathEvent>.Continuation?
    private var serverProbe: (@Sendable () async -> ServerReachability)?
    private var reachabilityTask: Task<Void, Never>?
    private var physicalPathIsOnline = true
    /// How often an unreachable server is checked again while the network itself stays up.
    static let unreachableRecheckInterval: Duration = .seconds(60)

    init(playbackDiagnostics: PlaybackDiagnostics = PlaybackDiagnostics()) {
        self.playbackDiagnostics = playbackDiagnostics
    }

    func start(
        serverState: ServerState,
        streamSettings: StreamSettings,
        playerService: any PlayerServiceProtocol,
        serverProbe: (@Sendable () async -> ServerReachability)? = nil
    ) {
        guard updateTask == nil else { return }
        self.serverProbe = serverProbe
        let channel = AsyncStream<NetworkPathEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        updateContinuation = channel.continuation
        updateTask = Task { @MainActor in
            var lastEvent: NetworkPathEvent?
            for await event in channel.stream {
                guard !Task.isCancelled else { break }
                // Cellular monitors can repeat the identical path every few seconds.
                // Preserve the bounded diagnostic timeline for actual playback events.
                guard event != lastEvent else { continue }
                lastEvent = event
                playbackDiagnostics.record(
                    .networkPathChanged(PlaybackDiagnostics.NetworkPath(event))
                )
                streamSettings.networkPathDidChange(isCellular: event.descriptor.isCellular)
                // Publish the coherent event after its matching online/expensive/quality state.
                // The final flag then permits automatic index work using that known path.
                serverState.applyNetworkPath(event)
                // Playback recovery must not depend on a SwiftUI view task being mounted or surviving
                // cancellation. Deliver every post-baseline path transition directly to the actor.
                let effectiveEvent = serverState.networkPathEvent
                if effectiveEvent.generation > 0 {
                    await playerService.handleNetworkPathChanged(effectiveEvent)
                }
            }
        }

        let continuation = channel.continuation
        let reducer = reducer
        monitor.pathUpdateHandler = { [weak self] path in
            let descriptor = Self.descriptor(for: path)
            continuation.yield(reducer.reduce(descriptor))
            Task { @MainActor in self?.physicalPathDidChange(isOnline: descriptor.isOnline) }
        }
        monitor.start(queue: queue)
        Logger.network.debug("NetworkMonitor started.")
    }

    func stop() {
        reachabilityTask?.cancel()
        reachabilityTask = nil
        updateContinuation?.finish()
        updateContinuation = nil
        updateTask?.cancel()
        updateTask = nil
        monitor.cancel()
    }

    // MARK: - Server reachability

    private func physicalPathDidChange(isOnline: Bool) {
        physicalPathIsOnline = isOnline
        if isOnline {
            // Give a VPN such as Tailscale a moment to bring its tunnel up on the new path.
            checkServerReachability(after: .seconds(1))
        } else {
            reachabilityTask?.cancel()
            reachabilityTask = nil
        }
    }

    /// Checks that the active server answers and publishes the result as part of the network path.
    /// Called on path changes, when the app becomes active and when the active server changes.
    /// Two failed pings in a row mark the server unreachable; it is then rechecked periodically.
    func checkServerReachability(after delay: Duration = .zero) {
        guard let serverProbe, updateContinuation != nil else { return }
        reachabilityTask?.cancel()
        reachabilityTask = Task { [weak self] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            var failures = 0
            while !Task.isCancelled {
                guard self?.physicalPathIsOnline == true else { return }
                let result = await serverProbe()
                guard !Task.isCancelled, let self else { return }
                switch result {
                case .reachable, .notApplicable:
                    self.publishServerReachable(true)
                    return
                case .unreachable:
                    failures += 1
                    if failures >= 2 { self.publishServerReachable(false) }
                }
                let wait: Duration = failures >= 2 ? Self.unreachableRecheckInterval : .seconds(3)
                do { try await Task.sleep(for: wait) } catch { return }
            }
        }
    }

    private func publishServerReachable(_ reachable: Bool) {
        guard let event = reducer.reduceServerReachability(reachable) else { return }
        Logger.network.info("Server \(reachable ? "reachable again" : "unreachable", privacy: .public); path generation \(event.generation, privacy: .public)")
        updateContinuation?.yield(event)
    }

    private nonisolated static func descriptor(for path: NWPath) -> NetworkPathDescriptor {
        var interfaces: NetworkPathDescriptor.Interfaces = []
        if path.usesInterfaceType(.wifi) { interfaces.insert(.wifi) }
        if path.usesInterfaceType(.cellular) { interfaces.insert(.cellular) }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.insert(.wiredEthernet) }
        if path.usesInterfaceType(.other) { interfaces.insert(.other) }
        let available = path.availableInterfaces.reduce(into: NetworkPathDescriptor.Interfaces()) {
            $0.formUnion(Self.interfaces(for: $1.type))
        }

        return NetworkPathDescriptor(
            isOnline: path.status == .satisfied,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            supportsDNS: path.supportsDNS,
            supportsIPv4: path.supportsIPv4,
            supportsIPv6: path.supportsIPv6,
            interfaces: interfaces,
            gateways: path.gateways.map { String(describing: $0) }.sorted(),
            underlyingInterfaces: underlyingInterfaces(path: interfaces, available: available)
        )
    }

    private nonisolated static func interfaces(for type: NWInterface.InterfaceType) -> NetworkPathDescriptor.Interfaces {
        switch type {
        case .wifi: .wifi
        case .cellular: .cellular
        case .wiredEthernet: .wiredEthernet
        case .other: .other
        default: []
        }
    }

    /// A VPN such as Tailscale routes the path through a tunnel whose type is "other". The
    /// physical interfaces it can run over still tell Wi-Fi apart from cellular data.
    nonisolated static func underlyingInterfaces(
        path: NetworkPathDescriptor.Interfaces,
        available: NetworkPathDescriptor.Interfaces
    ) -> NetworkPathDescriptor.Interfaces {
        guard path.contains(.other), path.isDisjoint(with: [.wifi, .cellular, .wiredEthernet]) else { return [] }
        return available.intersection([.wifi, .cellular, .wiredEthernet])
    }
}
