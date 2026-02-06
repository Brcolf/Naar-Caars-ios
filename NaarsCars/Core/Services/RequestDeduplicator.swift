//
//  RequestDeduplicator.swift
//  NaarsCars
//
//  Actor for deduplicating concurrent network requests
//  Prevents cache stampede by tracking in-flight requests
//

import Foundation

/// Actor that deduplicates concurrent requests for the same resource
/// Prevents multiple simultaneous network calls for the same data
actor RequestDeduplicator {
    
    /// Type-erased wrapper for tasks
    private final class TaskWrapper {
        private let _cancel: () -> Void
        let task: Any // Store the original task
        
        init<T>(_ task: Task<T, Error>) {
            self.task = task
            self._cancel = { task.cancel() }
        }
        
        func cancel() {
            _cancel()
        }
    }
    
    /// In-flight requests keyed by unique identifier
    private var inflightRequests: [String: TaskWrapper] = [:]
    
    /// Fetch or deduplicate a request for a given key
    /// - Parameters:
    ///   - key: Unique identifier for the request
    ///   - operation: The async operation to perform if not already in-flight
    /// - Returns: The result of the operation (from cache or newly executed)
    func fetch<T>(
        key: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        // Check if request is already in-flight
        if let existingWrapper = inflightRequests[key],
           let existingTask = existingWrapper.task as? Task<T, Error> {
            AppLogger.info("network", "Request already in-flight for key: \(key)")
            return try await existingTask.value
        }
        
        // Create new task
        let task = Task<T, Error> {
            do {
                let result = try await operation()
                // Clean up when done
                await self.removeTask(for: key)
                return result
            } catch {
                // Clean up on error too
                await self.removeTask(for: key)
                throw error
            }
        }
        
        // Store the task wrapped
        inflightRequests[key] = TaskWrapper(task)
        
        AppLogger.info("network", "Started new request for key: \(key)")
        return try await task.value
    }
    
    /// Remove a task from the in-flight requests
    private func removeTask(for key: String) {
        inflightRequests[key] = nil
    }
    
    /// Cancel all in-flight requests
    func cancelAll() {
        for (key, task) in inflightRequests {
            task.cancel()
            AppLogger.warning("network", "Cancelled request for key: \(key)")
        }
        inflightRequests.removeAll()
    }
    
    /// Cancel a specific request
    func cancel(key: String) {
        if let wrapper = inflightRequests[key] {
            wrapper.cancel()
            inflightRequests[key] = nil
            AppLogger.warning("network", "Cancelled request for key: \(key)")
        }
    }
    
    /// Get count of in-flight requests
    var inflightCount: Int {
        inflightRequests.count
    }
}
