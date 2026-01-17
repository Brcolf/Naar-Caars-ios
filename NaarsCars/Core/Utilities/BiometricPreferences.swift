//
//  BiometricPreferences.swift
//  NaarsCars
//
//  Manages user preferences for biometric authentication
//

import Foundation

/// Manages user preferences for biometric authentication
final class BiometricPreferences {
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let biometricsEnabled = "biometrics_enabled"
        static let requireBiometricsOnLaunch = "require_biometrics_on_launch"
        static let lastAuthenticatedDate = "last_authenticated_date"
    }
    
    static let shared = BiometricPreferences()
    private init() {}
    
    /// Whether the user has enabled biometric authentication
    var isBiometricsEnabled: Bool {
        get { userDefaults.bool(forKey: Keys.biometricsEnabled) }
        set { userDefaults.set(newValue, forKey: Keys.biometricsEnabled) }
    }
    
    /// Whether to require biometrics when app launches
    var requireBiometricsOnLaunch: Bool {
        get { userDefaults.bool(forKey: Keys.requireBiometricsOnLaunch) }
        set { userDefaults.set(newValue, forKey: Keys.requireBiometricsOnLaunch) }
    }
    
    /// When the user last successfully authenticated
    var lastAuthenticatedDate: Date? {
        get { userDefaults.object(forKey: Keys.lastAuthenticatedDate) as? Date }
        set { userDefaults.set(newValue, forKey: Keys.lastAuthenticatedDate) }
    }
    
    /// Check if re-authentication is needed (e.g., after 5 minutes in background)
    /// - Parameter timeout: Timeout in seconds (default: 300 = 5 minutes)
    /// - Returns: true if re-authentication is needed
    func needsReauthentication(timeout: TimeInterval = 300) -> Bool {
        guard requireBiometricsOnLaunch else { return false }
        guard let lastAuth = lastAuthenticatedDate else { return true }
        return Date().timeIntervalSince(lastAuth) > timeout
    }
    
    /// Record successful authentication
    func recordAuthentication() {
        lastAuthenticatedDate = Date()
    }
}


