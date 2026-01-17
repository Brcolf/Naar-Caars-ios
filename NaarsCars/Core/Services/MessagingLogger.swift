//
//  MessagingLogger.swift
//  NaarsCars
//
//  Comprehensive logging utility for the messaging module
//  Tracks async operations, performance, and potential race conditions
//

import Foundation
import os.log

/// Comprehensive logger for messaging operations with performance tracking
actor MessagingLogger {
    
    // MARK: - Singleton
    
    static let shared = MessagingLogger()
    
    // MARK: - Log Levels
    
    enum LogLevel: String {
        case debug = "🔍"
        case info = "ℹ️"
        case warning = "⚠️"
        case error = "🔴"
        case performance = "⏱️"
        case race = "🏁"
        case cache = "💾"
        case network = "🌐"
        case success = "✅"
    }
    
    // MARK: - Properties
    
    private var operationTimestamps: [String: Date] = [:]
    private var activeOperations: [String: Date] = [:] // Track concurrent operations
    private var operationCounts: [String: Int] = [:] // Track how many times each operation runs
    
    private let logger = Logger(subsystem: "com.naarscars.app", category: "Messaging")
    private let enableDetailedLogging = true // Set to false in production
    
    // Log level filtering - only log messages at or above this level
    private let minimumLogLevel: LogLevel = .warning // Only warnings and errors by default
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Log a message with specific level
    func log(
        _ message: String,
        level: LogLevel = .info,
        function: String = #function,
        file: String = #file,
        line: Int = #line
    ) {
        guard enableDetailedLogging else { return }
        
        // Filter by minimum log level
        let levelPriority: [LogLevel: Int] = [
            .debug: 0,
            .info: 1,
            .network: 1,
            .cache: 1,
            .success: 2,
            .warning: 3,
            .performance: 3,
            .race: 4,
            .error: 5
        ]
        
        guard let messagePriority = levelPriority[level],
              let minimumPriority = levelPriority[minimumLogLevel],
              messagePriority >= minimumPriority else {
            return
        }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logTimeFormatter.string(from: Date())
        let logMessage = "\(level.rawValue) [\(timestamp)] [\(fileName):\(line)] \(function) - \(message)"
        
        print(logMessage)
        
        // Also log to unified logging system
        switch level {
        case .debug:
            logger.debug("\(logMessage)")
        case .info:
            logger.info("\(logMessage)")
        case .warning:
            logger.warning("\(logMessage)")
        case .error:
            logger.error("\(logMessage)")
        case .performance, .race, .cache, .network, .success:
            logger.info("\(logMessage)")
        }
    }
    
    /// Start tracking an async operation
    func startOperation(
        _ operationId: String,
        description: String,
        function: String = #function
    ) {
        let now = Date()
        
        // Check for concurrent duplicate operations (potential race condition)
        if let existingStart = activeOperations[operationId] {
            let duration = now.timeIntervalSince(existingStart)
            log(
                "⚠️ POTENTIAL RACE CONDITION: '\(operationId)' started again while previous call is still running (running for \(String(format: "%.2f", duration))s)",
                level: .race,
                function: function
            )
        }
        
        activeOperations[operationId] = now
        operationCounts[operationId, default: 0] += 1
        
        // Reduced logging: Only log on first call or race conditions
        // Comment out the verbose "Started" log
        // log(
        //     "Started: \(description) (count: \(operationCounts[operationId, default: 0]))",
        //     level: .info,
        //     function: function
        // )
    }
    
    /// End tracking an async operation and log duration
    func endOperation(
        _ operationId: String,
        success: Bool = true,
        resultDescription: String? = nil,
        function: String = #function
    ) {
        guard let startTime = activeOperations[operationId] else {
            log(
                "⚠️ Attempted to end operation '\(operationId)' but it was never started",
                level: .warning,
                function: function
            )
            return
        }
        
        let duration = Date().timeIntervalSince(startTime)
        activeOperations.removeValue(forKey: operationId)
        
        // Only log errors and slow operations
        if !success {
            let result = resultDescription ?? "failed"
            log(
                "❌ Completed: \(operationId) - \(result) (took \(String(format: "%.3f", duration))s)",
                level: .error,
                function: function
            )
        } else if duration > 3.0 {
            // Warn about slow operations (> 3 seconds)
            log(
                "🐌 SLOW OPERATION: '\(operationId)' took \(String(format: "%.3f", duration))s (threshold: 3.0s)",
                level: .performance,
                function: function
            )
        }
        
        // Successful fast operations are not logged
    }
    
    /// Log an error with context
    func logError(
        _ error: Error,
        context: String,
        function: String = #function,
        file: String = #file,
        line: Int = #line
    ) {
        _ = (file as NSString).lastPathComponent
        log(
            "ERROR in \(context): \(error.localizedDescription)",
            level: .error,
            function: function,
            file: file,
            line: line
        )
        
        // Log additional error details
        print("   Error type: \(type(of: error))")
        if let appError = error as? AppError {
            print("   App error: \(appError)")
        }
    }
    
    /// Log cache operation
    func logCache(
        operation: String,
        hit: Bool,
        key: String,
        function: String = #function
    ) {
        let status = hit ? "HIT ✓" : "MISS ✗"
        log(
            "Cache \(status): \(operation) [key: \(key)]",
            level: .cache,
            function: function
        )
    }
    
    /// Log network request
    func logNetwork(
        request: String,
        parameters: [String: Any]? = nil,
        function: String = #function
    ) {
        var message = "Network Request: \(request)"
        if let params = parameters, !params.isEmpty {
            message += " | Params: \(params)"
        }
        log(message, level: .network, function: function)
    }
    
    /// Get a summary of active operations (for debugging race conditions)
    func getActiveOperationsSummary() -> String {
        if activeOperations.isEmpty {
            return "No active operations"
        }
        
        var summary = "Active Operations (\(activeOperations.count)):\n"
        for (operation, startTime) in activeOperations.sorted(by: { $0.value < $1.value }) {
            let duration = Date().timeIntervalSince(startTime)
            summary += "  - \(operation): running for \(String(format: "%.2f", duration))s\n"
        }
        return summary
    }
    
    /// Get operation statistics (for performance analysis)
    func getOperationStatistics() -> [String: Int] {
        return operationCounts
    }
    
    /// Reset statistics (useful for testing)
    func resetStatistics() {
        operationCounts.removeAll()
        activeOperations.removeAll()
        log("Statistics reset", level: .info)
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Convenience Methods for Common Operations

extension MessagingLogger {
    
    /// Log conversation fetch operation
    func logConversationFetch(
        userId: UUID,
        limit: Int,
        offset: Int,
        cached: Bool = false,
        function: String = #function
    ) {
        let source = cached ? "cache" : "network"
        log(
            "Fetching conversations for user \(userId) (limit: \(limit), offset: \(offset), source: \(source))",
            level: cached ? .cache : .network,
            function: function
        )
    }
    
    /// Log message fetch operation
    func logMessageFetch(
        conversationId: UUID,
        limit: Int,
        beforeId: UUID? = nil,
        cached: Bool = false,
        function: String = #function
    ) {
        let pagination = beforeId != nil ? "paginated before \(beforeId!)" : "initial load"
        let source = cached ? "cache" : "network"
        log(
            "Fetching messages for conversation \(conversationId) (limit: \(limit), \(pagination), source: \(source))",
            level: cached ? .cache : .network,
            function: function
        )
    }
    
    /// Log display name resolution
    func logDisplayNameResolution(
        conversationId: UUID,
        cached: Bool,
        computed: Bool = false,
        function: String = #function
    ) {
        if cached {
            log(
                "Display name resolved from cache for conversation \(conversationId)",
                level: .cache,
                function: function
            )
        } else if computed {
            log(
                "Display name computed for conversation \(conversationId) (will cache in background)",
                level: .info,
                function: function
            )
        } else {
            log(
                "Display name unavailable for conversation \(conversationId) (showing 'Loading...')",
                level: .warning,
                function: function
            )
        }
    }
}

// MARK: - Task Tracking Extension

extension MessagingLogger {
    
    /// Track a Task and log if it's cancelled
    func trackTask(
        _ operationId: String,
        function: String = #function
    ) async throws {
        do {
            try Task.checkCancellation()
        } catch {
            log(
                "Task cancelled: \(operationId)",
                level: .warning,
                function: function
            )
            throw error
        }
    }
}
