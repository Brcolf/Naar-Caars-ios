//
//  AppLaunchManager.swift
//  NaarsCars
//
//  Critical-path launch management for fast app startup
//

import Foundation
import SwiftUI
import Supabase
internal import Combine

/// Launch state enum for app initialization
enum LaunchState: Equatable {
    case initializing
    case checkingAuth
    case ready(AuthState)
    case failed(Error)
    
    static func == (lhs: LaunchState, rhs: LaunchState) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing),
             (.checkingAuth, .checkingAuth):
            return true
        case (.ready(let lhsState), .ready(let rhsState)):
            return lhsState == rhsState
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
    
    /// Unique identifier for the state to force view updates
    var id: String {
        switch self {
        case .initializing:
            return "initializing"
        case .checkingAuth:
            return "checkingAuth"
        case .ready(let authState):
            return "ready_\(authState)"
        case .failed(let error):
            return "failed_\(error.localizedDescription)"
        }
    }
}

/// Manages critical-path app launch to complete in <1 second
/// Performs minimal checks (auth session + approval) before showing UI
/// Defers non-critical loading (profile, rides, etc.) to background
@MainActor
final class AppLaunchManager: ObservableObject {
    
    /// Shared singleton instance
    static let shared = AppLaunchManager()
    
    /// Current launch state
    @Published var state: LaunchState = .initializing
    
    /// Supabase client reference
    private let supabase = SupabaseService.shared.client
    
    /// Auth service reference
    private let authService = AuthService.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var signOutObserver: NSObjectProtocol?
    private var deferredSyncStartedForUserId: UUID?
    private var refreshCoordinatorInitializedForUserId: UUID?

    /// UserDefaults key for the per-user cached AuthState. Used on the next launch
    /// to skip the ~700ms `checkAccountStatus` roundtrip on the critical path while
    /// still verifying authoritatively in the background.
    private let cachedAuthStateKey = "AppLaunchManager.lastAuthState"
    
    private init() {
        AppLogger.info("launch", "Initializing - setting up notification listener")
        
        // Use direct NotificationCenter observer instead of Combine for reliability
        let notificationName: Notification.Name = .userDidSignOut
        AppLogger.info("launch", "Setting up observer for notification: '\(notificationName.rawValue)'")
        
        signOutObserver = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            AppLogger.info("launch", "Received userDidSignOut notification")
            AppLogger.info("launch", "Notification name: \(notification.name.rawValue)")
            AppLogger.info("launch", "Notification object: \(String(describing: notification.object))")
            
            guard let self = self else {
                AppLogger.warning("launch", "Self is nil, cannot update state")
                return
            }
            
            // Immediately set state to unauthenticated when sign out happens
            // Since AppLaunchManager is @MainActor, this is safe to do synchronously
            AppLogger.info("launch", "Setting state to unauthenticated immediately")
            AppLogger.info("launch", "Current state before update: \(self.state.id)")
            self.deferredSyncStartedForUserId = nil
            self.refreshCoordinatorInitializedForUserId = nil
            self.state = .ready(.unauthenticated)
            AppLogger.info("launch", "State updated to: \(self.state.id)")
        }
        
        AppLogger.info("launch", "Notification listener set up successfully")
        AppLogger.info("launch", "Observer stored: \(signOutObserver != nil ? "YES" : "NO")")
    }
    
    deinit {
        // Remove observer when deallocated
        if let observer = signOutObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Critical Launch Path
    
    /// Perform critical launch operations (auth session + approval check only)
    /// Target: Complete in <1 second per FR-051
    func performCriticalLaunch() async {
        let launchStart = Date()
        state = .checkingAuth

        do {
            // Step 1: Check for existing session (fast - reads from keychain)
            let session = try await supabase.auth.session

            // Extract user ID from session
            let userIdString = session.user.id.uuidString
            guard let userId = UUID(uuidString: userIdString) else {
                // No valid user ID - ready for login
                state = .ready(.unauthenticated)
                await recordLaunchDuration(
                    start: launchStart,
                    result: "invalid_user_id",
                    metadata: ["state": state.id]
                )
                return
            }

            // Step 2: Optimistic launch when we have a cached authState for this user.
            // The vast majority of returning users haven't changed status since last
            // launch, so we skip the ~700ms profile roundtrip on the critical path
            // and verify authoritatively in the background.
            if let cached = cachedAuthState(for: userId) {
                if cached == .authenticated {
                    prepareAuthenticatedRefreshState(for: userId)
                }
                state = .ready(cached)
                if cached == .authenticated {
                    Task(priority: .userInitiated) { [weak self, userId] in
                        guard let self else { return }
                        await self.performDeferredLoading(userId: userId)
                    }
                }
                Task(priority: .userInitiated) { [weak self, userId, cached] in
                    guard let self else { return }
                    await self.verifyAccountStatusInBackground(userId: userId, optimisticState: cached)
                }
                await recordLaunchDuration(
                    start: launchStart,
                    result: "optimistic",
                    metadata: [
                        "state": state.id,
                        "cachedAuthState": "\(cached)",
                        "hasSession": true
                    ]
                )
                return
            }

            // Step 2 (cold path): no cache, do the full blocking check.
            let authState = await checkAccountStatus(userId: userId)
            if authState == .authenticated {
                prepareAuthenticatedRefreshState(for: userId)
            }
            state = .ready(authState)
            cacheAuthState(authState, for: userId)

            // Step 3: Start deferred loading in background (non-blocking)
            if authState == .authenticated {
                Task(priority: .userInitiated) { [weak self, userId] in
                    guard let self else { return }
                    await self.performDeferredLoading(userId: userId)
                }
            }
            await recordLaunchDuration(
                start: launchStart,
                result: "success",
                metadata: [
                    "state": state.id,
                    "authState": "\(authState)",
                    "hasSession": true
                ]
            )

        } catch {
            // Session check failed - treat as unauthenticated
            state = .ready(.unauthenticated)
            await recordLaunchDuration(
                start: launchStart,
                result: "session_missing_or_invalid",
                metadata: [
                    "state": state.id,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    /// Background reconciliation for the optimistic-launch path. Only mutates state
    /// if the authoritative server result differs from the cached optimistic value.
    private func verifyAccountStatusInBackground(userId: UUID, optimisticState: AuthState) async {
        let actual = await checkAccountStatus(userId: userId)
        cacheAuthState(actual, for: userId)
        guard actual != optimisticState else { return }
        // The user's status has actually changed since last launch.
        AppLogger.info("launch", "Auth state changed since last launch: \(optimisticState) -> \(actual)")
        if actual == .authenticated {
            prepareAuthenticatedRefreshState(for: userId)
        }
        state = .ready(actual)
        // If we transitioned into authenticated (e.g. approval was granted), start
        // the deferred loading we skipped during optimistic launch.
        if optimisticState != .authenticated && actual == .authenticated {
            await performDeferredLoading(userId: userId)
        }
    }
    
    // MARK: - Public Methods
    
    /// Lightweight approval check for use by PendingApprovalView
    /// Does NOT change state to checkingAuth (prevents state loops)
    /// - Returns: true if current user is approved, false otherwise
    func checkApprovalStatusOnly() async -> Bool {
        do {
            let session = try await supabase.auth.session
            let userIdString = session.user.id.uuidString
            guard let userId = UUID(uuidString: userIdString) else {
                return false
            }
            let status = await checkAccountStatus(userId: userId)
            return status == .authenticated
        } catch {
            AppLogger.warning("launch", "Lightweight approval check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Lightweight ban re-check for use on app foreground.
    /// If user is now banned, transitions state to .banned.
    func recheckBanStatus() async {
        guard case .ready(.authenticated) = state else { return }
        do {
            let session = try await supabase.auth.session
            guard let userId = UUID(uuidString: session.user.id.uuidString) else { return }
            let status = await checkAccountStatus(userId: userId)
            cacheAuthState(status, for: userId)
            if status == .banned {
                state = .ready(.banned)
            }
        } catch {
            AppLogger.warning("launch", "Ban re-check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Cached AuthState (for optimistic launch)

    private func cachedAuthState(for userId: UUID) -> AuthState? {
        let dict = UserDefaults.standard.dictionary(forKey: cachedAuthStateKey) as? [String: String] ?? [:]
        guard let raw = dict[userId.uuidString] else { return nil }
        switch raw {
        case "authenticated":   return .authenticated
        case "banned":          return .banned
        case "needsApplication": return .needsApplication
        case "pendingApproval": return .pendingApproval
        default: return nil
        }
    }

    private func cacheAuthState(_ state: AuthState, for userId: UUID) {
        let raw: String?
        switch state {
        case .authenticated:    raw = "authenticated"
        case .banned:           raw = "banned"
        case .needsApplication: raw = "needsApplication"
        case .pendingApproval:  raw = "pendingApproval"
        default:                raw = nil  // unauthenticated/guest aren't cached
        }
        guard let raw else { return }
        var dict = UserDefaults.standard.dictionary(forKey: cachedAuthStateKey) as? [String: String] ?? [:]
        dict[userId.uuidString] = raw
        UserDefaults.standard.set(dict, forKey: cachedAuthStateKey)
    }

    /// Enter guest browsing mode without creating a Supabase session.
    /// Callers must also set `appState.isGuestMode = true` before calling this.
    /// No session, no profile, no deferred loading, no sync engines.
    func enterGuestMode() {
        state = .ready(.guest)
    }

    /// Exit guest mode and return to the unauthenticated welcome screen.
    /// Callers must also set `appState.isGuestMode = false` before calling this.
    func exitGuestMode() {
        state = .ready(.unauthenticated)
    }

    // MARK: - Private Methods
    
    /// Check account status with minimal query (approved + application_complete)
    /// - Parameter userId: User ID to check
    /// - Returns: The appropriate AuthState for the user
    private func checkAccountStatus(userId: UUID) async -> AuthState {
        let start = Date()
        do {
            struct ProfileStatus: Codable {
                let isBanned: Bool
                let approved: Bool
                let applicationComplete: Bool

                enum CodingKeys: String, CodingKey {
                    case isBanned = "is_banned"
                    case approved
                    case applicationComplete = "application_complete"
                }
            }

            AppLogger.info("launch", "Checking account status for user: \(userId)")

            let response: ProfileStatus = try await supabase
                .from("profiles")
                .select("is_banned, approved, application_complete")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value

            AppLogger.info("launch", "Account status for user \(userId): isBanned=\(response.isBanned), approved=\(response.approved), applicationComplete=\(response.applicationComplete)")
            await PerformanceMonitor.shared.record(
                operation: "launch.approvalCheck",
                duration: Date().timeIntervalSince(start),
                metadata: ["isBanned": response.isBanned, "approved": response.approved, "applicationComplete": response.applicationComplete],
                slowThreshold: 0.5
            )

            if response.isBanned {
                return .banned
            } else if response.approved {
                return .authenticated
            } else if !response.applicationComplete {
                return .needsApplication
            } else {
                return .pendingApproval
            }
        } catch {
            AppLogger.warning("launch", "Failed to check account status for user \(userId): \(error.localizedDescription)")
            await PerformanceMonitor.shared.record(
                operation: "launch.approvalCheck",
                duration: Date().timeIntervalSince(start),
                metadata: ["error": error.localizedDescription],
                slowThreshold: 0.5
            )
            // If query fails, assume needs application (safer default)
            return .needsApplication
        }
    }
    
    /// Perform deferred loading of non-critical data in background
    /// - Parameter userId: Authenticated user ID
    private func performDeferredLoading(userId: UUID) async {
        let start = Date()

        // Ensure AuthService has the userId before sync engines start.
        // performCriticalLaunch() reads the userId from the JWT session but
        // doesn't set it on AuthService — sync engines check
        // authService.currentUserId for user-specific subscriptions and data
        // fetches, so it must be populated first.
        prepareAuthenticatedRefreshState(for: userId)

        startDeferredServicesIfNeeded(for: userId)

        // Refresh blocked users cache for content filtering
        await MessageService.shared.refreshBlockedUsers()

        // Update AuthService with full profile
        try? await authService.checkAuthStatus()
        
        // Note: Additional background loading (rides, favors, etc.) is visible-domain driven
        // by RefreshCoordinator so first interactions are not competing with every engine.
        await PerformanceMonitor.shared.record(
            operation: "launch.deferredLoading",
            duration: Date().timeIntervalSince(start),
            metadata: ["userId": userId.uuidString]
        )
    }

    private func startDeferredServicesIfNeeded(for userId: UUID) {
        guard deferredSyncStartedForUserId != userId else { return }
        deferredSyncStartedForUserId = userId

        prepareAuthenticatedRefreshState(for: userId)

        Task {
            await MessageSendWorker.shared.start()
            await MessageSendWorker.shared.notifyNewPendingMessage()
        }
    }

    private func prepareAuthenticatedRefreshState(for userId: UUID) {
        if authService.currentUserId != userId {
            authService.currentUserId = userId
        }
        guard refreshCoordinatorInitializedForUserId != userId else { return }
        refreshCoordinatorInitializedForUserId = userId
        RefreshCoordinator.shared.initializeStates()
        RefreshCoordinator.shared.startSafetyPoll()
    }

    private func recordLaunchDuration(start: Date, result: String, metadata: [String: Any] = [:]) async {
        var payload = metadata
        payload["result"] = result
        await PerformanceMonitor.shared.record(
            operation: "launch.performCriticalLaunch",
            duration: Date().timeIntervalSince(start),
            metadata: payload,
            slowThreshold: Constants.Performance.launchCriticalPathSlowThreshold
        )
    }
}
