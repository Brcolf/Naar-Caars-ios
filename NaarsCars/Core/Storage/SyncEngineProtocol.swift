//
//  SyncEngineProtocol.swift
//  NaarsCars
//
//  Common lifecycle protocol for realtime sync engines
//

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

/// Shared lifecycle interface for all realtime sync engines.
@MainActor
protocol SyncEngineProtocol: AnyObject {
    var engineName: String { get }
    func setup(modelContext: ModelContext)
    func startSync()
    func pauseSync() async
    func resumeSync() async
    func teardown() async
}
