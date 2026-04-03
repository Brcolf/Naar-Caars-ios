//
//  RefreshMetrics.swift
//  NaarsCars
//

import Foundation

/// Refresh domain — defined here so NotificationType can reference it before RefreshCoordinator exists.
/// RefreshCoordinator.Domain is a typealias to this.
enum RefreshDomain: String, CaseIterable, Hashable {
    case dashboard      // rides + favors + notifications
    case townHall       // posts + comments
    case conversations  // conversation list metadata
    case badges         // badge counts (not in SwiftData)
}

struct RefreshMetrics: Equatable {
    let recordsEvaluated: Int
    let recordsMutated: Int
    let recordsInserted: Int
    let recordsDeleted: Int
    let savedToStore: Bool
    let durationMs: Int

    static let empty = RefreshMetrics(recordsEvaluated: 0, recordsMutated: 0, recordsInserted: 0, recordsDeleted: 0, savedToStore: false, durationMs: 0)
    static let badgeOnly = RefreshMetrics(recordsEvaluated: 0, recordsMutated: 0, recordsInserted: 0, recordsDeleted: 0, savedToStore: false, durationMs: 0)
}

enum RefreshResult {
    case completed(RefreshMetrics)
    case skipped(SkipReason)
    case joined(inFlightTrigger: String)
    case failed(Error, partial: RefreshMetrics?)
}

enum SkipReason: String {
    case fresh
    case backoff
    case guestMode
    case domainNotStarted
}

struct DomainSnapshot {
    let domain: RefreshDomain
    let stateDescription: String
    let lastSync: Date?
    let hasLocalData: Bool
    let isInFlight: Bool
    let lastTrigger: String?
    let lastResultDescription: String?
}

struct RefreshDiagnostics {
    let timestamp: Date
    let domains: [DomainSnapshot]
    let activeConversation: UUID?
    let visibleDomain: RefreshDomain?
}
