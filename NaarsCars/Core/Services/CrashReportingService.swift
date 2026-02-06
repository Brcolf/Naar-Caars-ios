//
//  CrashReportingService.swift
//  NaarsCars
//
//  Crash reporting and error logging service using Firebase Crashlytics
//

import Foundation
import FirebaseCrashlytics
internal import Combine

/// Error domains for categorizing non-fatal errors
enum CrashDomain {
    static let network = "com.naarscars.network"
    static let auth = "com.naarscars.auth"
    static let database = "com.naarscars.database"
    static let parsing = "com.naarscars.parsing"
    static let storage = "com.naarscars.storage"
    static let ui = "com.naarscars.ui"
    static let realtime = "com.naarscars.realtime"
    static let messaging = "com.naarscars.messaging"
    static let claiming = "com.naarscars.claiming"
}

/// Error codes for categorizing non-fatal errors
enum CrashErrorCode {
    // Network: 1000-1999
    static let networkTimeout = 1001
    static let networkUnreachable = 1002
    static let networkUnauthorized = 1003
    static let networkServerError = 1004
    static let networkRateLimited = 1005
    
    // Auth: 2000-2999
    static let authInvalidToken = 2001
    static let authExpiredSession = 2002
    static let authInvalidCredentials = 2003
    static let authInvalidInviteCode = 2004
    static let authAppleSignInFailed = 2005
    static let authBiometricFailed = 2006
    
    // Database: 3000-3999
    static let dbQueryFailed = 3001
    static let dbInsertFailed = 3002
    static let dbUpdateFailed = 3003
    static let dbDeleteFailed = 3004
    static let dbNotFound = 3005
    static let dbRLSPolicyViolation = 3006
    
    // Parsing: 4000-4999
    static let parseDecodingFailed = 4001
    static let parseInvalidFormat = 4002
    static let parseInvalidDate = 4003
    static let parseInvalidUUID = 4004
    
    // Storage: 5000-5999
    static let storageUploadFailed = 5001
    static let storageDownloadFailed = 5002
    static let storageDeleteFailed = 5003
    static let storageFileTooLarge = 5004
    
    // UI: 6000-6999
    static let uiNavigationFailed = 6001
    static let uiStateInconsistent = 6002
    static let uiDeepLinkFailed = 6003
    
    // Realtime: 7000-7999
    static let realtimeConnectionFailed = 7001
    static let realtimeSubscriptionFailed = 7002
    static let realtimeMessageFailed = 7003
    
    // Messaging: 8000-8999
    static let messagingSendFailed = 8001
    static let messagingConversationFailed = 8002
    
    // Claiming: 9000-9999
    static let claimingFailed = 9001
    static let claimingUnclaimFailed = 9002
    static let claimingCompleteFailed = 9003
}

/// Service for crash reporting and error logging using Firebase Crashlytics
/// Provides methods for:
/// - User identification for crash context
/// - Breadcrumb logging for crash context
/// - Non-fatal error recording
/// - Custom key-value context
@MainActor
final class CrashReportingService {
    
    // MARK: - Singleton
    
    static let shared = CrashReportingService()
    
    // MARK: - Properties
    
    private var crashlytics: Crashlytics {
        Crashlytics.crashlytics()
    }
    
    /// Whether crash reporting is enabled (user opt-out support)
    @Published private(set) var isEnabled: Bool = true
    
    /// UserDefaults key for crash reporting opt-out
    private let crashReportingEnabledKey = "crash_reporting_enabled"
    
    // MARK: - Initialization
    
    private init() {
        // Load user preference
        isEnabled = UserDefaults.standard.object(forKey: crashReportingEnabledKey) as? Bool ?? true
        
        // Apply preference
        crashlytics.setCrashlyticsCollectionEnabled(isEnabled)
        
        AppLogger.info("crash", "Service initialized, enabled: \(isEnabled)")
    }
    
    // MARK: - Configuration
    
    /// Enable or disable crash collection (user opt-out)
    func setCrashReportingEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: crashReportingEnabledKey)
        crashlytics.setCrashlyticsCollectionEnabled(enabled)
        
        AppLogger.info("crash", "Crash reporting \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - User Identification
    
    /// Set the current user ID for crash reports
    /// - Parameter userId: User's UUID string, or nil to clear
    func setUserId(_ userId: String?) {
        guard isEnabled else { return }
        
        if let userId = userId {
            crashlytics.setUserID(userId)
            AppLogger.info("crash", "User ID set: \(userId.prefix(8))...")
        } else {
            crashlytics.setUserID("")
            AppLogger.info("crash", "User ID cleared")
        }
    }
    
    /// Set custom key-value pairs for crash context
    /// - Parameters:
    ///   - value: The value to set (String, Int, Bool, Float, Double)
    ///   - key: The key name
    func setCustomValue(_ value: Any, forKey key: String) {
        guard isEnabled else { return }
        crashlytics.setCustomValue(value, forKey: key)
    }
    
    /// Set multiple custom key-value pairs at once
    /// - Parameter keysAndValues: Dictionary of keys and values
    func setCustomKeysAndValues(_ keysAndValues: [String: Any]) {
        guard isEnabled else { return }
        crashlytics.setCustomKeysAndValues(keysAndValues)
    }
    
    // MARK: - Breadcrumbs
    
    /// Log a breadcrumb message (visible in crash reports)
    /// - Parameter message: The message to log
    func log(_ message: String) {
        guard isEnabled else { return }
        crashlytics.log(message)
    }
    
    /// Log screen view for navigation context
    /// - Parameter screenName: Name of the screen being viewed
    func logScreenView(_ screenName: String) {
        guard isEnabled else { return }
        crashlytics.log("Screen: \(screenName)")
    }
    
    /// Log user action for interaction context
    /// - Parameters:
    ///   - action: The action name (e.g., "claim_ride", "send_message")
    ///   - parameters: Optional parameters for additional context
    func logAction(_ action: String, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }
        
        var message = "Action: \(action)"
        if let params = parameters {
            // Sanitize parameters to avoid logging sensitive data
            let sanitizedParams = sanitizeParameters(params)
            message += " - \(sanitizedParams)"
        }
        crashlytics.log(message)
    }
    
    /// Log a network request for debugging context
    /// - Parameters:
    ///   - endpoint: The API endpoint
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - success: Whether the request succeeded
    func logNetworkRequest(endpoint: String, method: String, success: Bool) {
        guard isEnabled else { return }
        crashlytics.log("Network: \(method) \(endpoint) - \(success ? "✓" : "✗")")
    }
    
    // MARK: - Non-Fatal Errors
    
    /// Record a non-fatal error (app didn't crash but something went wrong)
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - userInfo: Additional context information
    func recordError(_ error: Error, userInfo: [String: Any]? = nil) {
        guard isEnabled else { return }
        
        let nsError = error as NSError
        
        var info = userInfo ?? [:]
        info["errorDescription"] = error.localizedDescription
        
        // Add AppError context if applicable
        if let appError = error as? AppError {
            info["appErrorType"] = String(describing: appError)
        }
        
        crashlytics.record(error: nsError, userInfo: info)
        
        AppLogger.warning("crash", "Non-fatal error recorded: \(error.localizedDescription)")
    }
    
    /// Record an error with custom domain and code
    /// - Parameters:
    ///   - domain: Error domain (use CrashDomain constants)
    ///   - code: Error code (use CrashErrorCode constants)
    ///   - message: Human-readable error message
    ///   - userInfo: Additional context information
    func recordError(
        domain: String,
        code: Int,
        message: String,
        userInfo: [String: Any]? = nil
    ) {
        guard isEnabled else { return }
        
        var info = userInfo ?? [:]
        info[NSLocalizedDescriptionKey] = message
        
        let error = NSError(domain: domain, code: code, userInfo: info)
        crashlytics.record(error: error)
        
        AppLogger.warning("crash", "Non-fatal error recorded: [\(domain):\(code)] \(message)")
    }
    
    /// Record a decoding error with context
    /// - Parameters:
    ///   - error: The DecodingError
    ///   - context: What was being decoded (e.g., "Ride", "Profile")
    func recordDecodingError(_ error: DecodingError, context: String) {
        guard isEnabled else { return }
        
        var message = "Failed to decode \(context)"
        var userInfo: [String: Any] = ["context": context]
        
        switch error {
        case .typeMismatch(let type, let decodingContext):
            message += ": Type mismatch for \(type)"
            userInfo["type"] = String(describing: type)
            userInfo["codingPath"] = decodingContext.codingPath.map { $0.stringValue }.joined(separator: ".")
            
        case .valueNotFound(let type, let decodingContext):
            message += ": Value not found for \(type)"
            userInfo["type"] = String(describing: type)
            userInfo["codingPath"] = decodingContext.codingPath.map { $0.stringValue }.joined(separator: ".")
            
        case .keyNotFound(let key, let decodingContext):
            message += ": Key not found: \(key.stringValue)"
            userInfo["key"] = key.stringValue
            userInfo["codingPath"] = decodingContext.codingPath.map { $0.stringValue }.joined(separator: ".")
            
        case .dataCorrupted(let decodingContext):
            message += ": Data corrupted"
            userInfo["codingPath"] = decodingContext.codingPath.map { $0.stringValue }.joined(separator: ".")
            userInfo["debugDescription"] = decodingContext.debugDescription
            
        @unknown default:
            message += ": Unknown decoding error"
        }
        
        recordError(
            domain: CrashDomain.parsing,
            code: CrashErrorCode.parseDecodingFailed,
            message: message,
            userInfo: userInfo
        )
    }
    
    // MARK: - App State Context
    
    /// Update crash context with current app state
    /// Call this when auth state changes
    func updateAppStateContext(
        isAuthenticated: Bool,
        isApproved: Bool,
        isAdmin: Bool
    ) {
        guard isEnabled else { return }
        
        setCustomKeysAndValues([
            "is_authenticated": isAuthenticated,
            "is_approved": isApproved,
            "is_admin": isAdmin
        ])
    }
    
    /// Update crash context with network state
    func updateNetworkContext(isConnected: Bool) {
        guard isEnabled else { return }
        setCustomValue(isConnected, forKey: "has_network")
    }
    
    // MARK: - Debug / Testing
    
    #if DEBUG
    /// Force a test crash (DEBUG only)
    /// Use this to verify Crashlytics is working
    func forceCrash() {
        fatalError("Test crash triggered by CrashReportingService")
    }
    
    /// Record a test non-fatal error (DEBUG only)
    func recordTestError() {
        recordError(
            domain: CrashDomain.ui,
            code: 9999,
            message: "Test non-fatal error from CrashReportingService",
            userInfo: ["test": true, "timestamp": Date().ISO8601Format()]
        )
    }
    #endif
    
    // MARK: - Private Helpers
    
    /// Sanitize parameters to avoid logging sensitive data
    private func sanitizeParameters(_ params: [String: Any]) -> [String: Any] {
        var sanitized: [String: Any] = [:]
        
        let sensitiveKeys = ["password", "email", "phone", "address", "token", "secret", "key"]
        
        for (key, value) in params {
            let lowercaseKey = key.lowercased()
            
            // Check if key contains sensitive words
            if sensitiveKeys.contains(where: { lowercaseKey.contains($0) }) {
                sanitized[key] = "[REDACTED]"
            } else if let stringValue = value as? String, stringValue.count > 100 {
                // Truncate long strings
                sanitized[key] = String(stringValue.prefix(100)) + "..."
            } else {
                sanitized[key] = value
            }
        }
        
        return sanitized
    }
}

// MARK: - View Modifier for Screen Tracking

import SwiftUI

/// View modifier for automatic screen tracking
struct ScreenTrackingModifier: ViewModifier {
    let screenName: String
    
    func body(content: Content) -> some View {
        content.onAppear {
            CrashReportingService.shared.logScreenView(screenName)
        }
    }
}

extension View {
    /// Track this screen view in crash reports
    /// - Parameter name: The screen name for tracking
    /// - Returns: Modified view with screen tracking
    func trackScreen(_ name: String) -> some View {
        modifier(ScreenTrackingModifier(screenName: name))
    }
}

// MARK: - Error Recording Extensions

extension CrashReportingService {
    
    /// Record a network/database error with context
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - operation: The operation being performed (e.g., "fetchRides", "createMessage")
    ///   - service: The service name (e.g., "RideService", "MessageService")
    func recordServiceError(_ error: Error, operation: String, service: String) {
        guard isEnabled else { return }
        
        let domain: String
        let code: Int
        
        // Determine domain and code based on error type
        if let appError = error as? AppError {
            switch appError {
            case .networkUnavailable:
                domain = CrashDomain.network
                code = CrashErrorCode.networkUnreachable
            case .unauthorized:
                domain = CrashDomain.auth
                code = CrashErrorCode.authInvalidToken
            case .rateLimitExceeded, .rateLimited:
                domain = CrashDomain.network
                code = CrashErrorCode.networkRateLimited
            case .notFound:
                domain = CrashDomain.database
                code = CrashErrorCode.dbNotFound
            case .sessionExpired, .notAuthenticated, .authenticationRequired:
                domain = CrashDomain.auth
                code = CrashErrorCode.authExpiredSession
            case .invalidCredentials:
                domain = CrashDomain.auth
                code = CrashErrorCode.authInvalidCredentials
            default:
                domain = CrashDomain.database
                code = CrashErrorCode.dbQueryFailed
            }
        } else if error is DecodingError {
            domain = CrashDomain.parsing
            code = CrashErrorCode.parseDecodingFailed
        } else {
            domain = CrashDomain.database
            code = CrashErrorCode.dbQueryFailed
        }
        
        recordError(
            domain: domain,
            code: code,
            message: "\(service).\(operation) failed: \(error.localizedDescription)",
            userInfo: [
                "service": service,
                "operation": operation,
                "error_type": String(describing: type(of: error))
            ]
        )
    }
    
    /// Record a claiming error
    func recordClaimingError(_ error: Error, operation: String, requestType: String, requestId: UUID) {
        guard isEnabled else { return }
        
        let code: Int
        switch operation {
        case "claim": code = CrashErrorCode.claimingFailed
        case "unclaim": code = CrashErrorCode.claimingUnclaimFailed
        case "complete": code = CrashErrorCode.claimingCompleteFailed
        default: code = CrashErrorCode.claimingFailed
        }
        
        recordError(
            domain: CrashDomain.claiming,
            code: code,
            message: "Claiming \(operation) failed for \(requestType)",
            userInfo: [
                "operation": operation,
                "request_type": requestType,
                "request_id": requestId.uuidString,
                "error_type": String(describing: type(of: error))
            ]
        )
    }
    
    /// Record a messaging error
    func recordMessagingError(_ error: Error, operation: String, conversationId: UUID?) {
        guard isEnabled else { return }
        
        let code = operation == "send" ? CrashErrorCode.messagingSendFailed : CrashErrorCode.messagingConversationFailed
        
        var userInfo: [String: Any] = [
            "operation": operation,
            "error_type": String(describing: type(of: error))
        ]
        if let conversationId = conversationId {
            userInfo["conversation_id"] = conversationId.uuidString
        }
        
        recordError(
            domain: CrashDomain.messaging,
            code: code,
            message: "Messaging \(operation) failed",
            userInfo: userInfo
        )
    }
}

