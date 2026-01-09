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
    private let authService = AuthService.shared
    
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
            print("🔴 [UserManagementViewModel] Error loading members: \(error.localizedDescription)")
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
            
            // Reload the list to reflect changes
            await loadAllMembers()
            
            print("✅ [UserManagementViewModel] Successfully toggled admin status for \(userId): \(isAdmin)")
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            print("🔴 [UserManagementViewModel] Error toggling admin status: \(error.localizedDescription)")
            print("🔴 [UserManagementViewModel] Error details: \(error)")
        }
    }
    
    /// Check if current user can change admin status for a user
    /// - Parameter userId: ID of user to check
    /// - Returns: True if current user can change admin status
    func canChangeAdminStatus(for userId: UUID) -> Bool {
        return userId != authService.currentUserId
    }
}

