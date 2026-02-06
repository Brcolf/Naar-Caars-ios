//
//  RetryableOperation.swift
//  NaarsCars
//
//  Utility for retrying failed async operations with configurable backoff
//

import Foundation

/// Wraps an async throwing operation with retry logic and exponential backoff
enum RetryableOperation {
    
    /// Execute an async operation with retry support
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default: 3)
    ///   - initialDelay: Initial delay between retries in seconds (default: 1.0)
    ///   - backoffMultiplier: Multiplier applied to delay after each retry (default: 2.0)
    ///   - maxDelay: Maximum delay between retries in seconds (default: 10.0)
    ///   - shouldRetry: Optional closure to determine if a specific error should trigger a retry
    ///   - operation: The async throwing operation to execute
    /// - Returns: The result of the operation
    static func execute<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        backoffMultiplier: Double = 2.0,
        maxDelay: TimeInterval = 10.0,
        shouldRetry: ((Error) -> Bool)? = nil,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var currentDelay = initialDelay
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Check if we should retry this specific error
                if let shouldRetry, !shouldRetry(error) {
                    throw error
                }
                
                // Don't delay after the last attempt
                if attempt < maxAttempts {
                    AppLogger.warning("retry", "Attempt \(attempt)/\(maxAttempts) failed, retrying in \(String(format: "%.1f", currentDelay))s: \(error.localizedDescription)")
                    
                    try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                    currentDelay = min(currentDelay * backoffMultiplier, maxDelay)
                } else {
                    AppLogger.error("retry", "All \(maxAttempts) attempts failed: \(error.localizedDescription)")
                }
            }
        }
        
        throw lastError ?? AppError.processingError("Operation failed after \(maxAttempts) attempts")
    }
    
    /// Execute an async operation with retry, returning nil on final failure instead of throwing
    static func executeOrNil<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @Sendable () async throws -> T
    ) async -> T? {
        try? await execute(
            maxAttempts: maxAttempts,
            initialDelay: initialDelay,
            operation: operation
        )
    }
}
