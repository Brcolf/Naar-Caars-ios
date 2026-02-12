//
//  AppState.swift
//  NaarsCars
//
//  Global app state management for authentication and user data
//

import Foundation
import SwiftUI
internal import Combine

/// Global app state manager that tracks authentication status and current user
/// Observes AuthService for authentication changes and provides computed properties
/// for common state checks (isAdmin, isApproved, authState)
@MainActor
final class AppState: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current authenticated user's profile, nil if not authenticated
    @Published var currentUser: Profile?
    
    /// Loading state for app initialization and authentication checks
    @Published var isLoading: Bool = true
    
    /// Whether the notifications surface is currently shown
    @Published var showNotifications: Bool = false
    
    // MARK: - Private Properties
    
    /// Reference to AuthService for authentication state
    private let authService = AuthService.shared
    
    // MARK: - Computed Properties
    
    /// Whether the current user is an admin
    /// Returns false if no user is authenticated
    var isAdmin: Bool {
        currentUser?.isAdmin ?? false
    }
    
    /// Whether the current user is approved
    /// Returns false if no user is authenticated
    var isApproved: Bool {
        currentUser?.approved ?? false
    }
    
    /// Current authentication state based on user profile and loading state
    /// Returns appropriate AuthState enum value
    var authState: AuthState {
        if isLoading {
            return .loading
        }
        
        guard let user = currentUser else {
            return .unauthenticated
        }
        
        if !user.approved {
            return .pendingApproval
        }
        
        return .authenticated
    }
    
    // MARK: - Initialization
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Mirror the latest auth state immediately and keep AppState in sync.
        currentUser = authService.currentProfile
        isLoading = authService.isLoading

        authService.$currentProfile
            .sink { [weak self] profile in
                self?.currentUser = profile
            }
            .store(in: &cancellables)

        authService.$isLoading
            .sink { [weak self] isLoading in
                self?.isLoading = isLoading
            }
            .store(in: &cancellables)
        
        // Listen for signout events
        NotificationCenter.default.publisher(for: NSNotification.Name("userDidSignOut"))
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await SyncEngineOrchestrator.shared.teardownAll()
                    self?.currentUser = nil
                    self?.isLoading = false
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Check authentication status and update current user
    /// Should be called on app launch
    func checkAuthStatus() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            _ = try await authService.checkAuthStatus()
            // Update currentUser based on auth state
            // This will be implemented when AuthService.checkAuthStatus() is complete
            currentUser = authService.currentProfile
        } catch {
            // Handle error - user is not authenticated
            currentUser = nil
        }
    }
}
