import Foundation

protocol AudioStreamCacheProtocol: AnyObject, Sendable {
    var usedBytes: Int64 { get async }
    var trackCount: Int { get async }
    /// The size limit the least-recently-used eviction keeps the cache under.
    var maxBytes: Int64 { get async }

    func cachedURL(forSongId songId: String, serverId: UUID) async -> URL?

    /// The best complete copy of a song, with the quality it was fetched at.
    func cachedEntry(forSongId songId: String, serverId: UUID) async -> CachedAudioEntry?

    /// Moves a completed download into the cache without materialising the whole track in RAM.
    func store(fileAt sourceURL: URL, forSongId songId: String, serverId: UUID, mimeType: String) async throws -> URL

    /// Stores a copy fetched at `quality`. A lower-quality copy never replaces a better one: the
    /// new file is discarded and the URL of the existing copy is returned.
    func store(
        fileAt sourceURL: URL, forSongId songId: String, serverId: UUID, mimeType: String,
        quality: CachedAudioQuality
    ) async throws -> URL

    /// Songs still ahead in the queue. Eviction never removes them to make room.
    func setProtectedSongIDs(_ songIDs: Set<String>, serverId: UUID) async

    /// Bytes the cache already holds for these songs.
    func cachedBytes(forSongIds songIDs: Set<String>, serverId: UUID) async -> Int64

    func setMaxBytes(_ value: Int64) async

    func invalidate(songId: String, serverId: UUID) async

    func clearAll() async

    func clearAllForServer(_ serverId: UUID) async
}

/// Defaults for test doubles. `AudioStreamCache` declares each of these itself as `async`: in an
/// async context Swift would otherwise pick these over a synchronous actor method of the same name.
extension AudioStreamCacheProtocol {
    func cachedEntry(forSongId songId: String, serverId: UUID) async -> CachedAudioEntry? {
        await cachedURL(forSongId: songId, serverId: serverId).map { CachedAudioEntry(url: $0, quality: .unrecorded) }
    }

    func store(
        fileAt sourceURL: URL, forSongId songId: String, serverId: UUID, mimeType: String,
        quality: CachedAudioQuality
    ) async throws -> URL {
        try await store(fileAt: sourceURL, forSongId: songId, serverId: serverId, mimeType: mimeType)
    }

    func setProtectedSongIDs(_ songIDs: Set<String>, serverId: UUID) async {}

    func cachedBytes(forSongIds songIDs: Set<String>, serverId: UUID) async -> Int64 { 0 }
}
