// MeasureMeSchema.swift
//
// **MeasureMeSchema**
// The single description of the SwiftData store on disk, and the one way to open it.
//
// **Why one place:**
// Opening the store with a schema that leaves out a model makes SwiftData migrate that model's table
// away. The App Intents container listed three of the four models, so every measurement added from
// Shortcuts or Siri deleted all custom metric definitions. The app, background tasks and App Intents
// now all open the store through `MeasureMeModelContainer.makePersistent()`.
//
// **Changing a model:**
// `MeasureMeSchemaV1` lists the live model classes, which is only right while V1 is the current
// version. Before changing a model in a way lightweight migration cannot handle:
// 1. Copy today's model classes into `MeasureMeSchemaV1` as nested types, so V1 keeps describing the
//    stores already on devices.
// 2. Add `MeasureMeSchemaV2` listing the changed models and append it to `MeasureMeMigrationPlan.schemas`.
// 3. Add a `MigrationStage` from V1 to V2 to `MeasureMeMigrationPlan.stages`.
// 4. Extend `MeasureMeSchemaTests` with a V1 store that must open under V2.
//
import Foundation
import SwiftData

nonisolated enum MeasureMeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MetricSample.self, MetricGoal.self, PhotoEntry.self, CustomMetricDefinition.self]
    }
}

nonisolated enum MeasureMeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MeasureMeSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum MeasureMeModelContainer {
    enum StorageError: LocalizedError {
        case applicationSupportDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationSupportDirectoryUnavailable:
                return "Application Support directory is unavailable."
            }
        }
    }

    static var schema: Schema {
        Schema(versionedSchema: MeasureMeSchemaV1.self)
    }

    /// Opens the store on disk. `url` is for tests; the app always uses the default store in
    /// Application Support. CloudKit sync stays off — the app has its own iCloud backup.
    static func makePersistent(url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            let fileManager = FileManager.default
            guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw StorageError.applicationSupportDirectoryUnavailable
            }
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: MeasureMeMigrationPlan.self, configurations: [configuration])
    }
}
