//
//  PerformanceMonitor.swift
//  NaarsCars
//
//  Monitor and track performance metrics
//

import Foundation

/// Performance monitoring for tracking operation durations and statistics
actor PerformanceMonitor {
    
    // MARK: - Singleton
    
    static let shared = PerformanceMonitor()
    
    // MARK: - Private Properties
    
    /// Store operation timings: [operation: [durations]]
    private var operationTimings: [String: [TimeInterval]] = [:]
    
    /// Store operation metadata: [operation: [metadata]]
    private var operationMetadata: [String: [[String: Any]]] = [:]
    
    /// Maximum samples to keep per operation
    private let maxSamplesPerOperation = 100
    
    /// Slow operation thresholds (in seconds)
    private let slowThresholds: [String: TimeInterval] = [
        "fetchConversations": 2.0,
        "fetchMessages": 1.0,
        "fetchRides": 1.5,
        "fetchFavors": 1.5,
        "sendMessage": 0.5,
        "uploadImage": 3.0,
        "networkRequest": 2.0
    ]
    
    private init() {}
    
    // MARK: - Measurement
    
    /// Measure the duration of an operation
    /// - Parameters:
    ///   - operation: Operation name
    ///   - metadata: Optional metadata to track
    ///   - block: The async operation to measure
    /// - Returns: The result of the operation
    func measure<T>(
        operation: String,
        metadata: [String: Any] = [:],
        _ block: () async throws -> T
    ) async rethrows -> T {
        let start = Date()
        
        let result = try await block()
        
        let duration = Date().timeIntervalSince(start)
        
        // Record timing
        recordTiming(operation: operation, duration: duration, metadata: metadata)
        
        // Log to AppLogger
        AppLogger.logPerformance(
            operation: operation,
            duration: duration,
            metadata: metadata
        )
        
        // Check for slow operation
        if let threshold = slowThresholds[operation], duration > threshold {
            AppLogger.logSlowOperation(
                operation: operation,
                duration: duration,
                threshold: threshold
            )
        }
        
        return result
    }
    
    /// Record a timing measurement
    /// - Parameters:
    ///   - operation: Operation name
    ///   - duration: Duration in seconds
    ///   - metadata: Optional metadata
    private func recordTiming(operation: String, duration: TimeInterval, metadata: [String: Any]) {
        // Add timing
        if operationTimings[operation] == nil {
            operationTimings[operation] = []
        }
        operationTimings[operation]?.append(duration)
        
        // Add metadata
        if !metadata.isEmpty {
            if operationMetadata[operation] == nil {
                operationMetadata[operation] = []
            }
            operationMetadata[operation]?.append(metadata)
        }
        
        // Keep only last N samples
        if let count = operationTimings[operation]?.count, count > maxSamplesPerOperation {
            operationTimings[operation] = Array(operationTimings[operation]!.suffix(maxSamplesPerOperation))
            operationMetadata[operation] = Array((operationMetadata[operation] ?? []).suffix(maxSamplesPerOperation))
        }
    }
    
    // MARK: - Statistics
    
    /// Get statistics for an operation
    /// - Parameter operation: Operation name
    /// - Returns: Performance statistics if available
    func getStats(for operation: String) -> PerformanceStats? {
        guard let timings = operationTimings[operation], !timings.isEmpty else {
            return nil
        }
        
        let sorted = timings.sorted()
        let count = sorted.count
        
        let sum = sorted.reduce(0, +)
        let avg = sum / Double(count)
        let minValue = sorted.first!
        let maxValue = sorted.last!
        let p50 = sorted[count / 2]
        let p95 = sorted[min(Int(Double(count) * 0.95), count - 1)]
        let p99 = sorted[min(Int(Double(count) * 0.99), count - 1)]
        
        return PerformanceStats(
            operation: operation,
            count: count,
            min: minValue,
            max: maxValue,
            avg: avg,
            p50: p50,
            p95: p95,
            p99: p99
        )
    }
    
    /// Get all tracked operations
    /// - Returns: List of operation names
    func getAllOperations() -> [String] {
        return Array(operationTimings.keys).sorted()
    }
    
    /// Get summary of all operations
    /// - Returns: Dictionary of operation names to their stats
    func getAllStats() -> [String: PerformanceStats] {
        var stats: [String: PerformanceStats] = [:]
        for operation in operationTimings.keys {
            if let stat = getStats(for: operation) {
                stats[operation] = stat
            }
        }
        return stats
    }
    
    /// Print performance report to console
    func printReport() {
        print("\n📊 ===== Performance Report =====")
        print("Generated: \(Date())\n")
        
        let operations = getAllOperations()
        guard !operations.isEmpty else {
            print("No performance data collected yet.\n")
            return
        }
        
        for operation in operations {
            guard let stats = getStats(for: operation) else { continue }
            print(stats.description())
            print("---")
        }
        
        print("=================================\n")
    }
    
    /// Reset statistics for a specific operation
    /// - Parameter operation: Operation name to reset
    func reset(operation: String) {
        operationTimings.removeValue(forKey: operation)
        operationMetadata.removeValue(forKey: operation)
    }
    
    /// Reset all statistics
    func resetAll() {
        operationTimings.removeAll()
        operationMetadata.removeAll()
        print("📊 [Performance] Reset all statistics")
    }
    
    /// Get slow operations (above threshold)
    /// - Returns: List of operations that frequently exceed threshold
    func getSlowOperations() -> [(operation: String, avgDuration: TimeInterval, threshold: TimeInterval)] {
        var slowOps: [(operation: String, avgDuration: TimeInterval, threshold: TimeInterval)] = []
        
        for (operation, thresholdValue) in slowThresholds {
            guard let stats = getStats(for: operation) else { continue }
            
            if stats.avg > thresholdValue {
                slowOps.append((operation: operation, avgDuration: stats.avg, threshold: thresholdValue))
            }
        }
        
        return slowOps.sorted { $0.avgDuration > $1.avgDuration }
    }
}

/// Performance statistics for an operation
struct PerformanceStats {
    let operation: String
    let count: Int
    let min: TimeInterval
    let max: TimeInterval
    let avg: TimeInterval
    let p50: TimeInterval
    let p95: TimeInterval
    let p99: TimeInterval
    
    /// Format as readable string
    func description() -> String {
        """
        \(operation):
          Samples: \(count)
          Min:     \(String(format: "%.2f", min * 1000))ms
          Max:     \(String(format: "%.2f", max * 1000))ms
          Avg:     \(String(format: "%.2f", avg * 1000))ms
          P50:     \(String(format: "%.2f", p50 * 1000))ms
          P95:     \(String(format: "%.2f", p95 * 1000))ms
          P99:     \(String(format: "%.2f", p99 * 1000))ms
        """
    }
    
    /// Format as compact string
    func compactDescription() -> String {
        "\(operation): avg=\(String(format: "%.0f", avg * 1000))ms p95=\(String(format: "%.0f", p95 * 1000))ms (\(count) samples)"
    }
}
