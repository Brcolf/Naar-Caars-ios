//
//  SyncEngineProtocol.swift
//  NaarsCars
//
//  Common lifecycle protocol for realtime sync engines
//

import Foundation
import SwiftData

/// Observable sync health metrics for each engine.
@MainActor
final class SyncHealthMetrics {
    var lastSuccessAt: Date?
    var lastErrorAt: Date?
    var lastError: String?
    var consecutiveFailures: Int = 0

    func recordSuccess() {
        lastSuccessAt = Date()
        lastError = nil
        consecutiveFailures = 0
    }

    func recordFailure(_ error: Error) {
        lastErrorAt = Date()
        lastError = error.localizedDescription
        consecutiveFailures += 1
    }
}

/// Shared lifecycle interface for all sync engines.
@MainActor
protocol SyncEngineProtocol: AnyObject {
    var engineName: String { get }
    func setup(modelContext: ModelContext)
    /// Session-start hook run by `SyncEngineOrchestrator.startAll()` after sign-in/launch.
    /// Setup only (e.g. start workers). MUST NOT fetch or write SwiftData — initial
    /// hydration is issued by the launch path through `RefreshCoordinator.refreshIfNeeded`,
    /// and all engine fetches are dispatched only from the coordinator.
    func startSync()
    func teardown() async
    func performFullSync() async throws -> RefreshMetrics
    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics
    func setupBackgroundActor(container: ModelContainer)
}

extension SyncEngineProtocol {
    func performFullSync() async throws -> RefreshMetrics { .empty }
    func performTargetedSync(entityId: UUID) async throws -> RefreshMetrics { .empty }
    func setupBackgroundActor(container: ModelContainer) {}
}
