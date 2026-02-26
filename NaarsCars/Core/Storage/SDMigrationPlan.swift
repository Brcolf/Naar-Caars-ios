//
//  SDMigrationPlan.swift
//  NaarsCars
//
//  Migration plan for SwiftData schema evolution
//

import Foundation
import SwiftData

enum NaarsCarsModelMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // Lightweight migration: identical model list, no custom logic needed.
    // When indexes are added in SchemaV2 (iOS 18+), this stage will
    // automatically apply them.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}
