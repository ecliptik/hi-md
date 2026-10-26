import Foundation

/// UI and headless audio intents must share one initialization and one playback engine.
@MainActor
final class MinidiscRuntime {
    static let shared = MinidiscRuntime()
    let diagnostics = PlaybackDiagnostics()
    /// Exists before the container, so a widget or Spotlight link from a cold launch is kept.
    let linkRouter = LinkRouter()
    private var initialization: Task<AppContainer, Error>?
    private let load: (@MainActor () async throws -> AppContainer)?

    init(load: (@MainActor () async throws -> AppContainer)? = nil) {
        self.load = load
    }

    func container() async throws -> AppContainer {
        if let initialization { return try await initialization.value }
        let task = Task {
            if let load { return try await load() }
            #if os(macOS)
            return try await MinidiscMacApp.makeContainer(diagnostics: diagnostics, linkRouter: linkRouter)
            #else
            return try await MinidiscApp.makeContainer(diagnostics: diagnostics, linkRouter: linkRouter)
            #endif
        }
        initialization = task
        do {
            return try await task.value
        } catch {
            initialization = nil
            throw error
        }
    }
}
