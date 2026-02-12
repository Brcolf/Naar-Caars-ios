//
//  SyncEngineOrchestrator.swift
//  NaarsCars
//
//  Coordinates lifecycle operations across all sync engines
//

import SwiftData

/// Lifecycle orchestrator for realtime sync engines.
@MainActor
final class SyncEngineOrchestrator {
    static let shared = SyncEngineOrchestrator()

    private var engines: [SyncEngineProtocol] = []

    private init() {}

    func register(_ engine: SyncEngineProtocol) {
        let incomingId = ObjectIdentifier(engine)
        guard !engines.contains(where: { ObjectIdentifier($0) == incomingId }) else {
            return
        }
        engines.append(engine)
    }

    func setupAll(modelContext: ModelContext) {
        for engine in engines {
            engine.setup(modelContext: modelContext)
        }
    }

    func startAll() {
        for engine in engines {
            engine.startSync()
        }
    }

    func pauseAll() async {
        for engine in engines {
            await engine.pauseSync()
        }
    }

    func resumeAll() async {
        for engine in engines {
            await engine.resumeSync()
        }
    }

    func teardownAll() async {
        for engine in engines {
            await engine.teardown()
        }
    }
}
