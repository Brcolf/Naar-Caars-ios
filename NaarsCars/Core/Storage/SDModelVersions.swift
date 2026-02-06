//
//  SDModelVersions.swift
//  NaarsCars
//
//  Versioned schema definitions for SwiftData migration support
//

import Foundation
import SwiftData

// MARK: - Schema V1 (Initial Version)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SDConversation.self,
            SDMessage.self,
            SDRide.self,
            SDFavor.self,
            SDNotification.self,
            SDTownHallPost.self,
            SDTownHallComment.self
        ]
    }
}
