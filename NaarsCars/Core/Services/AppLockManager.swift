//
//  AppLockManager.swift
//  NaarsCars
//
//  Single source of truth for app lock state and biometric unlock flow.
//  Replaces scattered @State booleans in ContentView with a centralized,
//  @MainActor-isolated manager using a single enum state machine.
//

import SwiftUI

@MainActor
@Observable
final class AppLockManager {
    static let shared = AppLockManager()

    // MARK: - State

    enum LockState: Equatable {
        case unlocked
        case locked
        case authenticating
    }

    private(set) var state: LockState = .unlocked
    private(set) var lastError: BiometricError?

    // MARK: - Private

    private var lastBackgroundDate: Date?
    private let biometricPreferences = BiometricPreferences.shared
    private let biometricService = BiometricService.shared
    private let lockTimeout: TimeInterval = 300  // 5 minutes

    private init() {}

    // MARK: - Scene Phase

    /// Called from ContentView's `.onChange(of: scenePhase)`.
    /// This is the only entry point for scene-phase-driven lock decisions.
    func handleScenePhase(_ newPhase: ScenePhase, isAuthenticated: Bool) {
        guard isAuthenticated else { return }
        guard biometricPreferences.isBiometricsEnabled,
              biometricPreferences.requireBiometricsOnLaunch else { return }

        switch newPhase {
        case .background:
            lastBackgroundDate = Date()
            AppLogger.info("lock", "Recorded background timestamp")

        case .active:
            // Don't re-lock while already locked or mid-authentication
            guard state == .unlocked else {
                AppLogger.info("lock", "Skipping lock check — state=\(state)")
                return
            }

            if let lastBackground = lastBackgroundDate {
                let elapsed = Date().timeIntervalSince(lastBackground)
                if elapsed > lockTimeout {
                    AppLogger.info("lock", "Background duration \(Int(elapsed))s exceeds timeout — locking")
                    state = .locked
                }
            }

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Launch Check

    /// Called once during initial launch to determine if re-auth is needed.
    func checkOnLaunch(isAuthenticated: Bool) {
        guard isAuthenticated else { return }
        guard biometricPreferences.isBiometricsEnabled,
              biometricPreferences.requireBiometricsOnLaunch else { return }

        if biometricPreferences.needsReauthentication(timeout: lockTimeout) {
            AppLogger.info("lock", "Launch requires re-authentication — locking")
            state = .locked
        }
    }

    // MARK: - Authentication

    /// Attempt biometric unlock.
    /// Transitions: .locked → .authenticating → .unlocked (success) or .locked (failure).
    func unlock() async {
        guard state == .locked else {
            AppLogger.info("lock", "unlock() called but state=\(state), ignoring")
            return
        }

        state = .authenticating
        lastError = nil
        AppLogger.info("lock", "Biometric auth started")

        do {
            let success = try await biometricService.authenticate(
                reason: "app_lock_biometric_reason".localized
            )

            if success {
                AppLogger.info("lock", "Biometric auth succeeded")
                biometricPreferences.recordAuthentication()
                lastBackgroundDate = nil
                lastError = nil
                state = .unlocked
            } else {
                AppLogger.info("lock", "Biometric auth returned false")
                lastError = .failed
                state = .locked
            }
        } catch let biometricError as BiometricError {
            if case .cancelled = biometricError {
                AppLogger.info("lock", "Biometric auth cancelled by user")
                // No error shown for user-initiated cancel
            } else {
                AppLogger.info("lock", "Biometric auth error: \(biometricError.localizedDescription)")
                lastError = biometricError
            }
            state = .locked
        } catch {
            AppLogger.info("lock", "Biometric auth unknown error: \(error.localizedDescription)")
            lastError = .unknown(error.localizedDescription)
            state = .locked
        }
    }

    /// Clear the last error (called when user dismisses the alert).
    func clearError() {
        lastError = nil
    }

    /// Force-unlock without authentication (e.g., on sign out).
    func forceUnlock() {
        AppLogger.info("lock", "Force unlock — clearing lock state")
        state = .unlocked
        lastBackgroundDate = nil
        lastError = nil
    }
}
