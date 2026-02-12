//
//  SyncEngineProtocol.swift
//  NaarsCars
//
//  Common lifecycle protocol for realtime sync engines
//

import SwiftData

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
