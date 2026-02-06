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
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        [] // No migrations needed yet — this is the initial version
    }
}
