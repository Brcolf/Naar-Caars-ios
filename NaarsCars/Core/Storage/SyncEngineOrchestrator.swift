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
    private var modelContext: ModelContext?

    private init() {}

    func register(_ engine: SyncEngineProtocol) {
        let incomingId = ObjectIdentifier(engine)
        guard !engines.contains(where: { ObjectIdentifier($0) == incomingId }) else {
            return
        }
        engines.append(engine)
    }

    func setupAll(modelContext: ModelContext) {
        self.modelContext = modelContext
        for engine in engines {
            engine.setup(modelContext: modelContext)
        }
    }

    func startAll() {
        guard !AuthService.shared.isSigningOut else {
            AppLogger.warning("sync", "startAll() blocked — sign-out in progress")
            return
        }
        for engine in engines {
            AppLogger.info("sync", "Starting \(engine.engineName)")
            engine.startSync()
        }
    }

    func pauseAll() async {
        for engine in engines {
            AppLogger.info("sync", "Pausing \(engine.engineName)")
            await engine.pauseSync()
        }
    }

    func resumeAll() async {
        for engine in engines {
            AppLogger.info("sync", "Resuming \(engine.engineName)")
            await engine.resumeSync()
        }
    }

    func teardownAll() async {
        for engine in engines {
            AppLogger.info("sync", "Tearing down \(engine.engineName)")
            await engine.teardown()
        }
    }

    /// Deletes all SwiftData records to prevent cross-user data leakage on sign-out.
    /// Deletes leaves before parents to respect cascade relationships.
    func wipeSwiftDataCache() throws {
        guard let modelContext else {
            AppLogger.warning("sync", "wipeSwiftDataCache called but modelContext is nil")
            return
        }
        try modelContext.delete(model: SDDeletedMessage.self)
        try modelContext.delete(model: SDMessage.self)
        try modelContext.delete(model: SDConversation.self)
        try modelContext.delete(model: SDRide.self)
        try modelContext.delete(model: SDFavor.self)
        try modelContext.delete(model: SDNotification.self)
        try modelContext.delete(model: SDTownHallComment.self)
        try modelContext.delete(model: SDTownHallPost.self)
        try modelContext.save()
    }
}
