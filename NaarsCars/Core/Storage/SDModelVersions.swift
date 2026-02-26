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

// MARK: - Schema V2 (Indexes — placeholder)
//
// Index declarations require the #Index macro which is only available on
// iOS 18+ / macOS 15+.  The current deployment target is iOS 17, so we
// define SchemaV2 with the same model list as V1 for now.  When the
// deployment target is raised to iOS 18, add #Index entries for:
//   - SDMessage.conversationId
//   - SDNotification.rideId
//   - SDNotification.favorId
//
// The lightweight V1→V2 migration is a no-op that bumps the version number,
// which is the correct infrastructure for future schema changes.

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

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
