//
//  AdminService.swift
//  NaarsCars
//
//  Service for admin operations with defense-in-depth security
//

import Foundation
import Supabase

// MARK: - Internal DTOs (non-actor isolated)

private struct AdminCheck: Decodable {
    let isAdmin: Bool
    enum CodingKeys: String, CodingKey { case isAdmin = "is_admin" }
}

private struct UserIdResponse: Decodable {
    let claimedBy: UUID?
    enum CodingKeys: String, CodingKey { case claimedBy = "claimed_by" }
}

private struct BroadcastParams: Codable, Sendable {
    let p_title: String
    let p_body: String
    let p_type: String
    let p_pinned: Bool
}

// MARK: - Nonisolated Helper Functions

/// Create broadcast params dictionary in nonisolated context
nonisolated private func createBroadcastParams(title: String, message: String, pinned: Bool) -> [String: AnyCodable] {
    return [
        "p_title": AnyCodable(title),
        "p_body": AnyCodable(message),
        "p_type": AnyCodable("broadcast"),
        "p_pinned": AnyCodable(pinned)
    ]
}

/// Service for admin operations
/// Implements multi-layer security: client verification + server-side RLS
@MainActor
final class AdminService {
    
    // MARK: - Singleton
    
    static let shared = AdminService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let authService = AuthService.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Admin Verification
    
    /// Verify current user is admin before any admin operation
    /// This is defense-in-depth - RLS is the real security
    /// - Throws: AppError.unauthorized if not admin
    internal func verifyAdminStatus() async throws {
        guard let userId = authService.currentUserId else {
            throw AppError.unauthorized
        }
        
        // Fresh check from server, not cached
        let response = try await supabase
            .from("profiles")
            .select("is_admin")
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
        
        let check = try JSONDecoder().decode(AdminCheck.self, from: response.data)
        
        guard check.isAdmin else {
            Log.security("Non-admin attempted admin operation: \(userId)")
            throw AppError.unauthorized
        }
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all pending (unapproved) users
    /// - Returns: Array of unapproved profiles
    /// - Throws: AppError if not admin or fetch fails
    func fetchPendingUsers() async throws -> [Profile] {
        try await verifyAdminStatus()
        
        let response = try await supabase
            .from("profiles")
            .select("*")
            .eq("approved", value: false)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let profiles = try decoder.decode([Profile].self, from: response.data)
        
        print("✅ [AdminService] Fetched \(profiles.count) pending users")
        return profiles
    }
    
    /// Fetch all approved members
    /// - Returns: Array of approved profiles
    /// - Throws: AppError if not admin or fetch fails
    func fetchAllMembers() async throws -> [Profile] {
        try await verifyAdminStatus()
        
        let response = try await supabase
            .from("profiles")
            .select("*")
            .eq("approved", value: true)
            .order("name", ascending: true)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let profiles = try decoder.decode([Profile].self, from: response.data)
        
        print("✅ [AdminService] Fetched \(profiles.count) approved members")
        return profiles
    }
    
    /// Fetch admin statistics
    /// - Returns: Tuple with (pendingCount, totalMembers, activeMembers)
    /// - Throws: AppError if not admin or fetch fails
    func fetchAdminStats() async throws -> (pendingCount: Int, totalMembers: Int, activeMembers: Int) {
        try await verifyAdminStatus()
        
        // Fetch pending count
        let pendingResponse = try await supabase
            .from("profiles")
            .select("id", head: true, count: .exact)
            .eq("approved", value: false)
            .execute()
        
        let pendingCount = pendingResponse.count ?? 0
        
        // Fetch total approved members count
        let membersResponse = try await supabase
            .from("profiles")
            .select("id", head: true, count: .exact)
            .eq("approved", value: true)
            .execute()
        
        let totalMembers = membersResponse.count ?? 0
        
        // Active members = users with at least 1 completed ride or favor as claimer
        // For MVP, we'll count distinct users who have completed requests
        var activeMembers = 0
        
        do {
            // Query for distinct claimed_by users from completed rides
            let ridesResponse = try await supabase
                .from("rides")
                .select("claimed_by")
                .eq("status", value: "completed")
                .execute()
            
            // Count distinct claimed_by from completed favors
            let favorsResponse = try await supabase
                .from("favors")
                .select("claimed_by")
                .eq("status", value: "completed")
                .execute()
            
            let decoder = JSONDecoder()
            let rides: [UserIdResponse] = try decoder.decode([UserIdResponse].self, from: ridesResponse.data)
            let favors: [UserIdResponse] = try decoder.decode([UserIdResponse].self, from: favorsResponse.data)
            
            // Combine and get unique user IDs
            var activeUserIds = Set<UUID>()
            rides.compactMap { $0.claimedBy }.forEach { activeUserIds.insert($0) }
            favors.compactMap { $0.claimedBy }.forEach { activeUserIds.insert($0) }
            
            activeMembers = activeUserIds.count
        } catch {
            // If query fails, use totalMembers as approximation
            print("⚠️ [AdminService] Could not fetch active members count: \(error.localizedDescription)")
            activeMembers = totalMembers
        }
        
        print("✅ [AdminService] Stats: \(pendingCount) pending, \(totalMembers) members, \(activeMembers) active")
        return (pendingCount, totalMembers, activeMembers)
    }
    
    // MARK: - User Management
    
    /// Approve a pending user
    /// - Parameter userId: ID of user to approve
    /// - Throws: AppError if not admin or operation fails
    func approveUser(userId: UUID) async throws {
        try await verifyAdminStatus()
        
        // Fetch user profile to get email and name for welcome email
        let profile: Profile = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        // Update profile to approved
        let updates: [String: AnyCodable] = [
            "approved": AnyCodable(true),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]
        
        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId.uuidString)
            .execute()
        
        Log.security("Admin approved user: \(userId)")
        
        // Send welcome email (non-blocking, don't fail approval if email fails)
        Task.detached {
            do {
                try await EmailService.shared.sendWelcomeEmail(
                    userId: userId,
                    email: profile.email,
                    name: profile.name
                )
            } catch {
                print("⚠️ [AdminService] Failed to send welcome email: \(error.localizedDescription)")
                // Don't throw - email failure shouldn't block approval
            }
        }
        
        // Send welcome notification
        try await NotificationService.shared.sendApprovalNotification(to: userId)
    }
    
    /// Reject a pending user (delete unapproved profile)
    /// - Parameter userId: ID of user to reject
    /// - Throws: AppError if not admin or operation fails
    func rejectUser(userId: UUID) async throws {
        try await verifyAdminStatus()
        
        // Delete the pending profile (safety: only delete unapproved)
        _ = try await supabase
            .from("profiles")
            .delete()
            .eq("id", value: userId.uuidString)
            .eq("approved", value: false)
            .execute()
        
        Log.security("Admin rejected user: \(userId)")
        
        print("✅ [AdminService] Rejected user: \(userId)")
    }
    
    /// Set admin status for a user
    /// - Parameters:
    ///   - userId: ID of user to modify
    ///   - isAdmin: Whether user should be admin
    /// - Throws: AppError if not admin, attempting self-demotion, or operation fails
    func setAdminStatus(userId: UUID, isAdmin: Bool) async throws {
        try await verifyAdminStatus()
        
        // Prevent self-demotion
        guard userId != authService.currentUserId else {
            throw AppError.unknown("Cannot change your own admin status")
        }
        
        let updates: [String: AnyCodable] = [
            "is_admin": AnyCodable(isAdmin),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]
        
        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId.uuidString)
            .execute()
        
        Log.security("Admin set admin status for \(userId): \(isAdmin)")
        
        print("✅ [AdminService] Set admin status for \(userId): \(isAdmin)")
    }
    
    // MARK: - Broadcast
    
    /// Send a broadcast announcement to all approved users
    /// - Parameters:
    ///   - title: Broadcast title
    ///   - message: Broadcast message
    ///   - pinToNotifications: Whether to pin to notifications for 7 days
    /// - Throws: AppError if not admin or operation fails
    func sendBroadcast(title: String, message: String, pinToNotifications: Bool) async throws {
        try await verifyAdminStatus()
        
        // Use database function to send broadcast (bypasses RLS)
        // Capture values explicitly to avoid MainActor isolation
        let titleValue = title
        let messageValue = message
        let pinnedValue = pinToNotifications
        
        // Wrap RPC call in Task.detached to avoid MainActor isolation issues
        let task = Task.detached(priority: .userInitiated) { [titleValue, messageValue, pinnedValue] () async throws -> Int in
            // Use nonisolated helper function to create params in nonisolated context
            let params = createBroadcastParams(title: titleValue, message: messageValue, pinned: pinnedValue)
            let client = await SupabaseService.shared.client
            let response = try await client
                .rpc("send_broadcast_notifications", params: params)
                .execute()
            let decoder = JSONDecoder()
            let count = try decoder.decode(Int.self, from: response.data)
            return count
        }
        let count = try await task.value
        
        Log.security("Admin sent broadcast to \(count) users")
        
        print("✅ [AdminService] Sent broadcast to \(count) users")
        
        // Note: Push notifications would be triggered via Edge Function
        // This would be implemented separately via Supabase Edge Functions
    }
}

