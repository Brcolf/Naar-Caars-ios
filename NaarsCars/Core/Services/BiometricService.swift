//
//  BiometricService.swift
//  NaarsCars
//
//  Service for handling biometric authentication (Face ID / Touch ID)
//

import Foundation
import LocalAuthentication

/// Service for handling biometric authentication (Face ID / Touch ID)
final class BiometricService {
    static let shared = BiometricService()
    private init() {}
    
    // MARK: - Availability
    
    /// Check if biometrics are available on this device
    var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Check if any authentication (biometrics or passcode) is available
    var isAuthenticationAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    
    /// Get the type of biometrics available
    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }
    
    // MARK: - Authentication
    
    /// Authenticate using biometrics with passcode fallback
    /// - Parameter reason: Reason string shown to user
    /// - Returns: true if authentication succeeded
    /// - Throws: BiometricError if authentication fails
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        context.localizedCancelTitle = "Cancel"
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // Allows passcode fallback
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel:
                throw BiometricError.cancelled
            case .userFallback:
                throw BiometricError.userFallback
            case .biometryNotAvailable:
                throw BiometricError.notAvailable
            case .biometryNotEnrolled:
                throw BiometricError.notEnrolled
            case .biometryLockout:
                throw BiometricError.lockout
            case .authenticationFailed:
                throw BiometricError.failed
            default:
                throw BiometricError.unknown(error.localizedDescription)
            }
        } catch {
            throw BiometricError.unknown(error.localizedDescription)
        }
    }
    
    /// Authenticate using biometrics only (no passcode fallback)
    /// - Parameter reason: Reason string shown to user
    /// - Returns: true if authentication succeeded
    /// - Throws: BiometricError if authentication fails
    func authenticateBiometricsOnly(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""  // Hide fallback button
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel:
                throw BiometricError.cancelled
            case .userFallback:
                throw BiometricError.userFallback
            case .biometryNotAvailable:
                throw BiometricError.notAvailable
            case .biometryNotEnrolled:
                throw BiometricError.notEnrolled
            case .biometryLockout:
                throw BiometricError.lockout
            case .authenticationFailed:
                throw BiometricError.failed
            default:
                throw BiometricError.unknown(error.localizedDescription)
            }
        } catch {
            throw BiometricError.unknown(error.localizedDescription)
        }
    }
}

// MARK: - Types

enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID  // Vision Pro
    
    var displayName: String {
        switch self {
        case .none: return "Passcode"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }
    
    var iconName: String {
        switch self {
        case .none: return "lock.fill"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "eye"
        }
    }
}

enum BiometricError: LocalizedError {
    case cancelled
    case userFallback
    case notAvailable
    case notEnrolled
    case lockout
    case failed
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Authentication was cancelled."
        case .userFallback:
            return "User chose to use passcode."
        case .notAvailable:
            return "Biometric authentication is not available on this device."
        case .notEnrolled:
            return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
        case .lockout:
            return "Biometric authentication is locked. Please use your passcode."
        case .failed:
            return "Authentication failed. Please try again."
        case .unknown(let message):
            return message
        }
    }
}


