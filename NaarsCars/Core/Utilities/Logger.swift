//
//  Logger.swift
//  NaarsCars
//
//  Structured logging utility with categories
//

import Foundation
import os.log

/// Structured logging utility with categories
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.naarscars"
    
    /// Authentication-related logs
    static func auth(_ message: String, type: OSLogType = .info) {
        let logger = OSLog(subsystem: subsystem, category: "auth")
        os_log("%{public}@", log: logger, type: type, message)
    }
    
    /// Network-related logs
    static func network(_ message: String, type: OSLogType = .info) {
        let logger = OSLog(subsystem: subsystem, category: "network")
        os_log("%{public}@", log: logger, type: type, message)
    }
    
    /// UI-related logs
    static func ui(_ message: String, type: OSLogType = .info) {
        let logger = OSLog(subsystem: subsystem, category: "ui")
        os_log("%{public}@", log: logger, type: type, message)
    }
    
    /// Realtime-related logs
    static func realtime(_ message: String, type: OSLogType = .info) {
        let logger = OSLog(subsystem: subsystem, category: "realtime")
        os_log("%{public}@", log: logger, type: type, message)
    }
    
    /// Push notification-related logs
    static func push(_ message: String, type: OSLogType = .info) {
        let logger = OSLog(subsystem: subsystem, category: "push")
        os_log("%{public}@", log: logger, type: type, message)
    }
    
    /// Security-related logs (for admin operations and auth failures)
    /// Use .error or .fault for security events
    static func security(_ message: String, type: OSLogType = .error) {
        let logger = OSLog(subsystem: subsystem, category: "security")
        os_log("%{public}@", log: logger, type: type, message)
    }
}

