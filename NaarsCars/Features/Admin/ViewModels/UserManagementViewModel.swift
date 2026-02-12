//
//  UserManagementViewModel.swift
//  NaarsCars
//
//  ViewModel for user management
//

import Foundation
internal import Combine

/// ViewModel for user management
@MainActor
final class UserManagementViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var members: [Profile] = []
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    // MARK: - Private Properties
    
    private let adminService = AdminService.shared
    private let authService: any AuthServiceProtocol

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
    
    // MARK: - Public Methods
    
    /// Load all approved members
    func loadAllMembers() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let users = try await adminService.fetchAllMembers()
            members = users
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error loading members: \(error.localizedDescription)")
        }
    }
    
    /// Toggle admin status for a user
    /// - Parameters:
    ///   - userId: ID of user to modify
    ///   - isAdmin: Whether user should be admin
    func toggleAdminStatus(userId: UUID, isAdmin: Bool) async {
        error = nil
        
        // Prevent self-demotion (additional check in ViewModel for UX)
        guard userId != authService.currentUserId else {
            error = AppError.unknown("Cannot change your own admin status")
            return
        }
        
        do {
            try await adminService.setAdminStatus(userId: userId, isAdmin: isAdmin)
            HapticManager.success()
            
            // Reload the list to reflect changes
            await loadAllMembers()
            
            AppLogger.info("admin", "Successfully toggled admin status for \(userId): \(isAdmin)")
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error toggling admin status: \(error.localizedDescription)")
            AppLogger.error("admin", "Error toggling admin status details: \(error)")
        }
    }
    
    /// Check if current user can change admin status for a user
    /// - Parameter userId: ID of user to check
    /// - Returns: True if current user can change admin status
    func canChangeAdminStatus(for userId: UUID) -> Bool {
        return userId != authService.currentUserId
    }
}

