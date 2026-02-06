//
//  NetworkRetryHelper.swift
//  NaarsCars
//
//  Helper for retrying failed network requests with exponential backoff
//

import Foundation

/// Network retry helper with exponential backoff
enum NetworkRetryHelper {
    
    /// Retry an async operation with exponential backoff
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default: 3)
    ///   - initialDelay: Initial delay in seconds (default: 1.0)
    ///   - maxDelay: Maximum delay in seconds (default: 30.0)
    ///   - shouldRetry: Closure to determine if error is retryable (default: isRetryable)
    ///   - operation: The async operation to retry
    /// - Returns: The successful result
    /// - Throws: The last error if all attempts fail
    static func withRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        shouldRetry: ((Error) -> Bool)? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var currentDelay = initialDelay
        
        for attempt in 1...maxAttempts {
            do {
                // Check for task cancellation before retry
                try Task.checkCancellation()
                
                let result = try await operation()
                
                // Success - log if this was a retry
                if attempt > 1 {
                    AppLogger.info("network", "Operation succeeded on attempt \(attempt)")
                }
                
                return result
            } catch {
                lastError = error
                
                // Don't retry on cancellation
                if error is CancellationError {
                    AppLogger.warning("network", "Task cancelled, not retrying")
                    throw error
                }
                
                // Check if we should retry this error
                let errorIsRetryable = shouldRetry?(error) ?? isRetryable(error: error)
                if !errorIsRetryable {
                    AppLogger.error("network", "Error not retryable: \(error.localizedDescription)")
                    throw error
                }
                
                // Last attempt - don't wait
                if attempt == maxAttempts {
                    AppLogger.error("network", "All \(maxAttempts) attempts failed")
                    throw error
                }
                
                // Calculate delay with exponential backoff
                let delay = min(currentDelay, maxDelay)
                AppLogger.warning("network", "Attempt \(attempt) failed, retrying in \(String(format: "%.1f", delay))s: \(error.localizedDescription)")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                // Exponential backoff
                currentDelay *= 2
            }
        }
        
        // Should never reach here, but satisfy compiler
        throw lastError ?? AppError.unknown("Operation failed after all retries")
    }
    
    /// Determine if an error is retryable (network errors, timeouts, 5xx)
    /// - Parameter error: The error to check
    /// - Returns: true if error should be retried
    static func isRetryable(error: Error) -> Bool {
        // Check for URLError (network issues)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .resourceUnavailable,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        
        // Check for HTTP status codes (5xx server errors)
        if let httpError = error as NSError?, httpError.domain == "HTTPError" {
            let statusCode = httpError.code
            return (500...599).contains(statusCode)
        }
        
        // Check for common Supabase errors that are retryable
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("timeout") ||
           errorDescription.contains("connection") ||
           errorDescription.contains("network") ||
           errorDescription.contains("unavailable") {
            return true
        }
        
        return false
    }
    
    /// Retry with specific retry count and delays for critical operations
    /// - Parameters:
    ///   - maxAttempts: Maximum attempts (default: 5 for critical operations)
    ///   - initialDelay: Initial delay in seconds (default: 0.5)
    ///   - operation: The async operation to retry
    /// - Returns: The successful result
    /// - Throws: The last error if all attempts fail
    static func withAggressiveRetry<T>(
        maxAttempts: Int = 5,
        initialDelay: TimeInterval = 0.5,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await withRetry(
            maxAttempts: maxAttempts,
            initialDelay: initialDelay,
            maxDelay: 15.0,
            shouldRetry: isRetryable,
            operation: operation
        )
    }
}
