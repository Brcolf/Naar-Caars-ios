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
    /// The last load failure. Cleared whenever a load starts.
    @Published var error: AppError?
    /// A failed admin action (promote, restrict, remove restriction), for the error banner.
    /// Kept apart from `error`, which the reload after every action resets.
    @Published var actionErrorMessage: String?
    /// True while an admin action request is running
    @Published var isPerformingAction: Bool = false

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
    /// - Returns: True when the change was saved. On failure `actionErrorMessage` is set.
    @discardableResult
    func toggleAdminStatus(userId: UUID, isAdmin: Bool) async -> Bool {
        guard !isPerformingAction else { return false }
        error = nil
        actionErrorMessage = nil

        // Prevent self-demotion (additional check in ViewModel for UX)
        guard userId != authService.currentUserId else {
            error = AppError.unknown("Cannot change your own admin status")
            actionErrorMessage = "admin_update_admin_failed".localized
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await adminService.setAdminStatus(userId: userId, isAdmin: isAdmin)
            HapticManager.success()

            // Reload the list to reflect changes
            await loadAllMembers()

            AppLogger.info("admin", "Successfully toggled admin status for \(userId): \(isAdmin)")
            return true
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            actionErrorMessage = "admin_update_admin_failed".localized
            HapticManager.error()
            AppLogger.error("admin", "Error toggling admin status: \(error.localizedDescription)")
            AppLogger.error("admin", "Error toggling admin status details: \(error)")
            return false
        }
    }
    
    /// Check if current user can change admin status for a user
    /// - Parameter userId: ID of user to check
    /// - Returns: True if current user can change admin status
    func canChangeAdminStatus(for userId: UUID) -> Bool {
        return userId != authService.currentUserId
    }

    /// Ban a user with a required reason
    /// - Returns: True when the restriction was saved. On failure `actionErrorMessage` is set.
    @discardableResult
    func banUser(userId: UUID, reason: String) async -> Bool {
        guard !isPerformingAction else { return false }
        error = nil
        actionErrorMessage = nil

        guard userId != authService.currentUserId else {
            error = AppError.unknown("admin_cannot_restrict_self".localized)
            actionErrorMessage = "admin_cannot_restrict_self".localized
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await adminService.banUser(userId: userId, reason: reason)
            HapticManager.success()
            await loadAllMembers()
            AppLogger.info("admin", "Successfully banned user \(userId)")
            return true
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            actionErrorMessage = "admin_restrict_failed".localized
            HapticManager.error()
            AppLogger.error("admin", "Error banning user: \(error.localizedDescription)")
            return false
        }
    }

    /// Remove ban/restriction from a user
    /// - Returns: True when the restriction was removed. On failure `actionErrorMessage` is set.
    @discardableResult
    func unbanUser(userId: UUID) async -> Bool {
        guard !isPerformingAction else { return false }
        error = nil
        actionErrorMessage = nil
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await adminService.unbanUser(userId: userId)
            HapticManager.success()
            await loadAllMembers()
            AppLogger.info("admin", "Successfully unbanned user \(userId)")
            return true
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            actionErrorMessage = "admin_unrestrict_failed".localized
            HapticManager.error()
            AppLogger.error("admin", "Error unbanning user: \(error.localizedDescription)")
            return false
        }
    }
}

