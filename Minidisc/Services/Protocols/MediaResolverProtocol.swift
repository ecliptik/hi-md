import Foundation
import SwiftSonic

nonisolated enum MediaAvailability: String, Sendable, Equatable {
    case available
    case missing
    /// Connectivity, authentication, or an unsupported endpoint cannot prove a deletion.
    case unknown
}

/// Resolves playable media in order: permanent download, cache, remote stream.
nonisolated protocol MediaResolverProtocol: AnyObject, Sendable {
    /// Looks for completed local audio without contacting the server, even while offline.
    func localSource(songId: String, serverId: UUID) async -> MediaSource?
    func resolve(songId: String, serverId: UUID) async throws -> MediaSource
    /// Resolves with the song's file metadata, so a stream can keep the original or convert it.
    func resolve(songId: String, serverId: UUID, traits: StreamSourceTraits?) async throws -> MediaSource
    func resolveRadio(_ station: InternetRadioStation) async throws -> MediaSource
    /// Checks the authoritative server only after playback fails; local audio remains playable.
    func availability(songId: String, serverId: UUID) async -> MediaAvailability
}

extension MediaResolverProtocol {
    /// Resolvers that don't choose a stream quality ignore the metadata.
    func resolve(songId: String, serverId: UUID, traits: StreamSourceTraits?) async throws -> MediaSource {
        try await resolve(songId: songId, serverId: serverId)
    }
}
