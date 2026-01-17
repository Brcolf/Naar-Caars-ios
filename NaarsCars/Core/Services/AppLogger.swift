//
//  AppLogger.swift
//  NaarsCars
//
//  Structured logging system using OSLog
//

import Foundation
import OSLog

/// Centralized logging system with structured logging using OSLog
enum AppLogger {
    
    // MARK: - Log Categories
    
    private static let network = Logger(subsystem: "com.naarscars.app", category: "network")
    private static let cache = Logger(subsystem: "com.naarscars.app", category: "cache")
    private static let auth = Logger(subsystem: "com.naarscars.app", category: "auth")
    private static let realtime = Logger(subsystem: "com.naarscars.app", category: "realtime")
    private static let performance = Logger(subsystem: "com.naarscars.app", category: "performance")
    private static let database = Logger(subsystem: "com.naarscars.app", category: "database")
    private static let ui = Logger(subsystem: "com.naarscars.app", category: "ui")
    
    // MARK: - Network Logging
    
    /// Log a network request
    /// - Parameters:
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - path: Request path
    ///   - duration: Optional request duration in seconds
    ///   - statusCode: Optional HTTP status code
    ///   - error: Optional error
    static func logNetworkRequest(
        method: String,
        path: String,
        duration: TimeInterval? = nil,
        statusCode: Int? = nil,
        error: Error? = nil
    ) {
        if let duration = duration {
            let durationMs = duration * 1000
            if let statusCode = statusCode {
                if (200..<300).contains(statusCode) {
                    network.info("[\(method)] \(path) - \(statusCode) (\(String(format: "%.2f", durationMs))ms)")
                } else {
                    network.warning("[\(method)] \(path) - \(statusCode) (\(String(format: "%.2f", durationMs))ms)")
                }
            } else if let error = error {
                network.error("[\(method)] \(path) - ERROR: \(error.localizedDescription) (\(String(format: "%.2f", durationMs))ms)")
            }
        } else {
            network.debug("[\(method)] \(path) - Started")
        }
    }
    
    /// Log a network error with context
    /// - Parameters:
    ///   - operation: The operation that failed
    ///   - error: The error that occurred
    ///   - context: Additional context information
    static func logNetworkError(operation: String, error: Error, context: [String: String] = [:]) {
        var message = "Network error in \(operation): \(error.localizedDescription)"
        if !context.isEmpty {
            let contextString = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            message += " | Context: \(contextString)"
        }
        network.error("\(message)")
    }
    
    // MARK: - Cache Logging
    
    /// Log cache hit/miss
    /// - Parameters:
    ///   - key: Cache key
    ///   - hit: Whether it was a hit or miss
    ///   - size: Optional size of cached data
    static func logCacheAccess(key: String, hit: Bool, size: Int? = nil) {
        if hit {
            if let size = size {
                cache.debug("Cache HIT: \(key) (\(size) bytes)")
            } else {
                cache.debug("Cache HIT: \(key)")
            }
        } else {
            cache.debug("Cache MISS: \(key)")
        }
    }
    
    /// Log cache eviction
    /// - Parameters:
    ///   - key: Cache key being evicted
    ///   - reason: Reason for eviction
    ///   - size: Optional size freed
    static func logCacheEviction(key: String, reason: String, size: Int? = nil) {
        if let size = size {
            cache.info("Cache EVICT: \(key) - \(reason) (freed \(size) bytes)")
        } else {
            cache.info("Cache EVICT: \(key) - \(reason)")
        }
    }
    
    // MARK: - Auth Logging
    
    /// Log authentication event
    /// - Parameters:
    ///   - event: Event name (signin, signout, signup, etc.)
    ///   - userId: Optional user ID
    ///   - success: Whether operation succeeded
    ///   - error: Optional error
    static func logAuth(event: String, userId: UUID? = nil, success: Bool, error: Error? = nil) {
        let userIdString = userId?.uuidString ?? "unknown"
        
        if success {
            auth.info("\(event) - SUCCESS (user: \(userIdString))")
        } else {
            let errorMsg = error?.localizedDescription ?? "Unknown error"
            auth.error("\(event) - FAILED: \(errorMsg) (user: \(userIdString))")
        }
    }
    
    /// Log permission check
    /// - Parameters:
    ///   - action: Action being checked
    ///   - userId: User requesting permission
    ///   - granted: Whether permission was granted
    static func logPermissionCheck(action: String, userId: UUID, granted: Bool) {
        if granted {
            auth.debug("Permission GRANTED: \(action) for user \(userId.uuidString)")
        } else {
            auth.warning("Permission DENIED: \(action) for user \(userId.uuidString)")
        }
    }
    
    // MARK: - Realtime Logging
    
    /// Log realtime subscription event
    /// - Parameters:
    ///   - event: Event type (subscribe, unsubscribe, message, error)
    ///   - channel: Channel name
    ///   - priority: Optional subscription priority
    static func logRealtime(event: String, channel: String, priority: String? = nil) {
        if let priority = priority {
            realtime.info("\(event): \(channel) (priority: \(priority))")
        } else {
            realtime.info("\(event): \(channel)")
        }
    }
    
    // MARK: - Performance Logging
    
    /// Log performance metric
    /// - Parameters:
    ///   - operation: Operation name
    ///   - duration: Duration in seconds
    ///   - itemCount: Optional count of items processed
    ///   - metadata: Optional additional metadata
    static func logPerformance(
        operation: String,
        duration: TimeInterval,
        itemCount: Int? = nil,
        metadata: [String: Any] = [:]
    ) {
        let durationMs = duration * 1000
        var message = "\(operation) - \(String(format: "%.2f", durationMs))ms"
        
        if let itemCount = itemCount {
            let itemsPerSecond = Double(itemCount) / duration
            message += " (\(itemCount) items, \(String(format: "%.1f", itemsPerSecond)) items/s)"
        }
        
        if !metadata.isEmpty {
            let metadataString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            message += " | \(metadataString)"
        }
        
        performance.info("\(message)")
    }
    
    /// Log slow operation warning
    /// - Parameters:
    ///   - operation: Operation name
    ///   - duration: Duration in seconds
    ///   - threshold: Threshold that was exceeded
    static func logSlowOperation(operation: String, duration: TimeInterval, threshold: TimeInterval) {
        let durationMs = duration * 1000
        let thresholdMs = threshold * 1000
        performance.warning("SLOW: \(operation) took \(String(format: "%.2f", durationMs))ms (threshold: \(String(format: "%.2f", thresholdMs))ms)")
    }
    
    // MARK: - Database Logging
    
    /// Log database query
    /// - Parameters:
    ///   - table: Table name
    ///   - operation: Operation type (select, insert, update, delete)
    ///   - duration: Query duration in seconds
    ///   - rowCount: Optional row count affected
    static func logDatabaseQuery(
        table: String,
        operation: String,
        duration: TimeInterval,
        rowCount: Int? = nil
    ) {
        let durationMs = duration * 1000
        if let rowCount = rowCount {
            database.debug("[\(operation)] \(table) - \(rowCount) rows (\(String(format: "%.2f", durationMs))ms)")
        } else {
            database.debug("[\(operation)] \(table) (\(String(format: "%.2f", durationMs))ms)")
        }
    }
    
    /// Log database error
    /// - Parameters:
    ///   - table: Table name
    ///   - operation: Operation type
    ///   - error: Error that occurred
    static func logDatabaseError(table: String, operation: String, error: Error) {
        database.error("[\(operation)] \(table) - ERROR: \(error.localizedDescription)")
    }
    
    // MARK: - UI Logging
    
    /// Log view lifecycle event
    /// - Parameters:
    ///   - view: View name
    ///   - event: Lifecycle event (appear, disappear, load, etc.)
    static func logViewLifecycle(view: String, event: String) {
        ui.debug("[\(view)] \(event)")
    }
    
    /// Log user interaction
    /// - Parameters:
    ///   - action: Action performed
    ///   - target: Target of the action
    static func logUserInteraction(action: String, target: String) {
        ui.info("User action: \(action) on \(target)")
    }
    
    // MARK: - General Logging
    
    /// Log general info message
    /// - Parameters:
    ///   - category: Category name
    ///   - message: Log message
    static func info(_ category: String, _ message: String) {
        Logger(subsystem: "com.naarscars.app", category: category).info("\(message)")
    }
    
    /// Log general warning
    /// - Parameters:
    ///   - category: Category name
    ///   - message: Warning message
    static func warning(_ category: String, _ message: String) {
        Logger(subsystem: "com.naarscars.app", category: category).warning("\(message)")
    }
    
    /// Log general error
    /// - Parameters:
    ///   - category: Category name
    ///   - message: Error message
    static func error(_ category: String, _ message: String) {
        Logger(subsystem: "com.naarscars.app", category: category).error("\(message)")
    }
}
