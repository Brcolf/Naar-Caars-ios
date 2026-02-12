//
//  PendingUsersViewModel.swift
//  NaarsCars
//
//  ViewModel for pending users approval list
//

import Foundation
import Supabase
internal import Combine

/// ViewModel for pending users approval list
@MainActor
final class PendingUsersViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var pendingUsers: [Profile] = []
    @Published var inviterProfiles: [UUID: Profile] = [:]
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    // MARK: - Private Properties
    
    private let adminService = AdminService.shared
    private let badgeManager: any BadgeCountManaging
    private let supabase = SupabaseService.shared.client

    init(badgeManager: any BadgeCountManaging = BadgeCountManager.shared) {
        self.badgeManager = badgeManager
    }
    
    // MARK: - Public Methods
    
    /// Load pending users
    func loadPendingUsers() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let users = try await adminService.fetchPendingUsers()
            pendingUsers = users
            
            // Fetch inviter profiles for users who have invitedBy
            let inviterIds = users.compactMap { $0.invitedBy }
            if !inviterIds.isEmpty {
                await loadInviterProfiles(inviterIds: Set(inviterIds))
            }
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error loading pending users: \(error.localizedDescription)")
        }
    }
    
    /// Load inviter profiles
    private func loadInviterProfiles(inviterIds: Set<UUID>) async {
        do {
            let ids = Array(inviterIds)
            // Fetch profiles in batches if needed
            let response = try await supabase
                .from("profiles")
                .select("*")
                .in("id", values: ids.map { $0.uuidString })
                .execute()
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let profiles = try decoder.decode([Profile].self, from: response.data)
            
            // Store in dictionary for quick lookup
            for profile in profiles {
                inviterProfiles[profile.id] = profile
            }
        } catch {
            AppLogger.warning("admin", "Could not load inviter profiles: \(error.localizedDescription)")
            // Non-critical error - continue without inviter names
        }
    }
    
    /// Approve a pending user
    /// - Parameter userId: ID of user to approve
    func approveUser(userId: UUID) async {
        error = nil
        
        do {
            try await adminService.approveUser(userId: userId)
            HapticManager.success()
            AppLogger.info("admin", "Approved user: \(userId)")
            
            // Reload the list first to ensure we have the latest data
            await loadPendingUsers()
            
            // Remove from local list if still present (should be gone after reload)
            pendingUsers.removeAll { $0.id == userId }
            // Also remove from inviter profiles if needed
            inviterProfiles.removeValue(forKey: userId)
            
            // Refresh badge counts after approving user
            await badgeManager.refreshAllBadges(reason: "adminApproveUser")
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error approving user: \(error.localizedDescription)")
            AppLogger.error("admin", "Error approving user details: \(error)")
            // Reload list to ensure UI is in sync
            await loadPendingUsers()
        }
    }
    
    /// Reject a pending user
    /// - Parameter userId: ID of user to reject
    func rejectUser(userId: UUID) async {
        error = nil
        
        do {
            AppLogger.info("admin", "Admin rejected user: \(userId)")
            try await adminService.rejectUser(userId: userId)
            HapticManager.success()
            
            // Reload the list to verify rejection worked
            // This ensures we get fresh data from the server
            await loadPendingUsers()
            
            // Also remove from local list if still present (belt and suspenders)
            pendingUsers.removeAll { $0.id == userId }
            
            // Refresh badge counts after rejecting user
            await badgeManager.refreshAllBadges(reason: "adminRejectUser")
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error rejecting user: \(error.localizedDescription)")
            // Reload list to ensure UI is in sync
            await loadPendingUsers()
        }
    }
}

