//
//  Throttler.swift
//  NaarsCars
//
//  Coalescing throttler for async work
//

import Foundation

/// Actor-based throttler that coalesces repeated calls into a trailing run.
actor Throttler {
    static let shared = Throttler()

    private var lastRun: [String: Date] = [:]
    private var pendingTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    /// Run an async operation immediately if allowed; otherwise schedule a trailing run.
    /// Multiple calls within the interval coalesce into a single trailing run.
    func run(
        key: String,
        minimumInterval: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) async {
        let now = Date()
        if let last = lastRun[key] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minimumInterval {
                if pendingTasks[key] != nil {
                    return
                }
                let delay = minimumInterval - elapsed
                let task = Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await execute(key: key, operation: operation)
                }
                pendingTasks[key] = task
                return
            }
        }

        await execute(key: key, operation: operation)
    }

    func cancel(key: String) {
        pendingTasks[key]?.cancel()
        pendingTasks[key] = nil
    }

    func reset(key: String) {
        cancel(key: key)
        lastRun[key] = nil
    }

    private func execute(key: String, operation: @escaping @Sendable () async -> Void) async {
        pendingTasks[key] = nil
        lastRun[key] = Date()
        Task {
            await operation()
        }
    }
}
