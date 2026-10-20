import SwiftData

/// The user-data store as first shipped. Every change to a persisted model needs a new version
/// here, with a stage in `MinidiscMigrationPlan`, before it can reach upgrading users.
///
/// When adding V2, snapshot the models that change as nested types inside `MinidiscSchemaV1` so
/// the old shape stays described; the live types always describe the newest version.
nonisolated enum MinidiscSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            ServerConfig.self,
            CachedTrack.self,
            DownloadedTrack.self,
            DownloadedAlbum.self,
            DownloadedPlaylist.self,
            QueueSnapshot.self,
            FavoriteRecord.self,
            PinnedItem.self,
            PlaybackSession.self, // kept so stores written before the session split still open
            PlaybackEvent.self,
            CachedLyrics.self,
            SearchHistoryEntry.self,
            PlaylistCoverChoice.self
        ]
    }
}

nonisolated enum MinidiscMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MinidiscSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
