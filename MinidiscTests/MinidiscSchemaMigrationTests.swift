import Foundation
import SwiftData
import Testing
@testable import Minidisc

@Suite("Main store schema versioning")
@MainActor
struct MinidiscSchemaMigrationTests {
    private func temporaryStoreURL() throws -> URL {
        let directory = URL.temporaryDirectory.appendingPathComponent("schema-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("store.sqlite")
    }

    @Test("A store written before schemas were versioned opens through the migration plan")
    func unversionedStoreOpensWithPlan() throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // Shape of the container shipped before `MinidiscSchemaV1` existed.
        do {
            let legacySchema = Schema(MinidiscSchemaV1.models)
            let legacy = try ModelContainer(
                for: legacySchema,
                configurations: ModelConfiguration(schema: legacySchema, url: url)
            )
            let context = ModelContext(legacy)
            context.insert(ServerConfig(displayName: "Home", baseURL: "https://example.invalid", username: "alice"))
            try context.save()
        }

        let upgraded = try ModelContainer.minidisc(url: url)
        let servers = try ModelContext(upgraded).fetch(FetchDescriptor<ServerConfig>())
        #expect(servers.map(\.displayName) == ["Home"])
    }

    @Test("The migration plan lists the current schema last")
    func planEndsAtCurrentSchema() {
        #expect(MinidiscMigrationPlan.schemas.last.map(ObjectIdentifier.init) == ObjectIdentifier(MinidiscSchemaV1.self))
        #expect(MinidiscMigrationPlan.stages.count == MinidiscMigrationPlan.schemas.count - 1)
    }
}
