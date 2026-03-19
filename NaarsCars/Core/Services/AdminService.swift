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

private struct BroadcastParams: Codable, Sendable {
    let p_title: String
    let p_body: String
    let p_type: String
    let p_pinned: Bool
}

// MARK: - Admin Stats DTOs

struct AdminDashboardStats: Decodable {
    let fulfilledCount: Int
    let totalSavings: Double
    let activeRidesCount: Int

    enum CodingKeys: String, CodingKey {
        case fulfilledCount = "fulfilled_count"
        case totalSavings = "total_savings"
        case activeRidesCount = "active_rides_count"
    }
}

struct FulfilledPeriod: Decodable, Identifiable {
    let periodStart: Date
    let rideCount: Int
    let favorCount: Int
    let totalCount: Int

    var id: Date { periodStart }

    enum CodingKeys: String, CodingKey {
        case periodStart = "period_start"
        case rideCount = "ride_count"
        case favorCount = "favor_count"
        case totalCount = "total_count"
    }
}

struct SavingsPeriod: Decodable, Identifiable {
    let periodStart: Date
    let totalSavings: Double
    let rideCount: Int

    var id: Date { periodStart }

    enum CodingKeys: String, CodingKey {
        case periodStart = "period_start"
        case totalSavings = "total_savings"
        case rideCount = "ride_count"
    }
}

struct ActiveRequestRow: Decodable, Identifiable {
    let id: UUID
    let type: String
    let title: String
    let subtitle: String?
    let date: Date
    let time: String?
    let status: String
    let claimedBy: UUID?
    let posterName: String?
    let claimerName: String?

    var isRide: Bool { type == "ride" }

    enum CodingKeys: String, CodingKey {
        case id, type, title, subtitle, date, time, status
        case claimedBy = "claimed_by"
        case posterName = "poster_name"
        case claimerName = "claimer_name"
    }
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
        
        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        
        let profiles = try decoder.decode([Profile].self, from: response.data)
        
        AppLogger.info("admin", "Fetched \(profiles.count) pending users")
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
        
        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        
        let profiles = try decoder.decode([Profile].self, from: response.data)
        
        AppLogger.info("admin", "Fetched \(profiles.count) approved members")
        return profiles
    }
    
    /// Fetch admin dashboard summary stats via RPC
    func fetchDashboardStats() async throws -> AdminDashboardStats {
        try await verifyAdminStatus()

        let response = try await supabase
            .rpc("admin_dashboard_stats")
            .execute()

        let stats = try JSONDecoder().decode(AdminDashboardStats.self, from: response.data)

        AppLogger.info("admin", "Dashboard stats: \(stats.fulfilledCount) fulfilled, $\(stats.totalSavings) savings, \(stats.activeRidesCount) active")
        return stats
    }

    /// Fetch fulfilled requests breakdown by period
    func fetchFulfilledBreakdown(period: String, count: Int = 12) async throws -> [FulfilledPeriod] {
        try await verifyAdminStatus()

        let params: [String: AnyCodable] = [
            "p_period": AnyCodable(period),
            "p_count": AnyCodable(count)
        ]

        let response = try await supabase
            .rpc("admin_stats_fulfilled", params: params)
            .execute()

        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        let periods = try decoder.decode([FulfilledPeriod]?.self, from: response.data)
        return periods ?? []
    }

    /// Fetch savings breakdown by period
    func fetchSavingsBreakdown(period: String, count: Int = 12) async throws -> [SavingsPeriod] {
        try await verifyAdminStatus()

        let params: [String: AnyCodable] = [
            "p_period": AnyCodable(period),
            "p_count": AnyCodable(count)
        ]

        let response = try await supabase
            .rpc("admin_stats_savings", params: params)
            .execute()

        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        let periods = try decoder.decode([SavingsPeriod]?.self, from: response.data)
        return periods ?? []
    }

    /// Fetch all active (unfinished) rides and favors
    func fetchActiveRequests() async throws -> [ActiveRequestRow] {
        try await verifyAdminStatus()

        let response = try await supabase
            .rpc("admin_stats_active_rides")
            .execute()

        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        let requests = try decoder.decode([ActiveRequestRow]?.self, from: response.data)
        return requests ?? []
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
        
        AppLogger.info("admin", "Attempting to approve user: \(userId)")
        AppLogger.info("admin", "Update payload: approved=true")
        
        let response = try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId.uuidString)
            .execute()
        
        AppLogger.info("admin", "Update response received for user: \(userId)")
        
        // Verify the update actually worked by fetching the profile
        let verifyProfile: Profile = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        if verifyProfile.approved {
            AppLogger.info("admin", "User \(userId) successfully approved (verified)")
            Log.security("Admin approved user: \(userId)")
        } else {
            AppLogger.error("admin", "User \(userId) update appeared to succeed but approved is still false")
            throw AppError.unknown("Approval update failed - user is still not approved")
        }
        
        // Send welcome email (non-blocking, don't fail approval if email fails)
        Task.detached {
            do {
                try await EmailService.shared.sendWelcomeEmail(
                    userId: userId,
                    email: profile.email,
                    name: profile.name
                )
            } catch {
                AppLogger.warning("admin", "Failed to send welcome email: \(error.localizedDescription)")
                // Don't throw - email failure shouldn't block approval
            }
        }

        // Note: Approval notification + push is handled by the on_user_approved_notify
        // database trigger on the profiles table, so no need to call it from Swift.
    }
    
    /// Reject a pending user (delete unapproved profile)
    /// - Parameter userId: ID of user to reject
    /// - Throws: AppError if not admin or operation fails
    func rejectUser(userId: UUID) async throws {
        try await verifyAdminStatus()
        
        // Use RPC function to delete profile (bypasses RLS)
        // The direct delete doesn't work due to missing RLS delete policy
        let params: [String: String] = ["p_user_id": userId.uuidString]
        
        AppLogger.info("admin", "Calling admin_reject_pending_user for: \(userId)")
        
        struct RejectResponse: Decodable {
            let success: Bool
            let error: String?
            let deletedUserId: UUID?
            let rowsDeleted: Int?
            
            enum CodingKeys: String, CodingKey {
                case success
                case error
                case deletedUserId = "deleted_user_id"
                case rowsDeleted = "rows_deleted"
            }
        }
        
        let response: RejectResponse = try await supabase
            .rpc("admin_reject_pending_user", params: params)
            .execute()
            .value
        
        if response.success {
            Log.security("Admin rejected user: \(userId)")
            AppLogger.info("admin", "Successfully rejected user: \(userId), rows deleted: \(response.rowsDeleted ?? 0)")
        } else {
            let errorMsg = response.error ?? "Unknown error"
            AppLogger.error("admin", "Failed to reject user \(userId): \(errorMsg)")
            throw AppError.processingError("Failed to reject user: \(errorMsg)")
        }
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
        
        AppLogger.info("admin", "Set admin status for \(userId): \(isAdmin)")
    }

    /// Ban/restrict a user account
    /// - Parameters:
    ///   - userId: ID of user to ban
    ///   - reason: Required reason for the ban (displayed to the user)
    /// - Throws: AppError if not admin, attempting self-ban, or operation fails
    func banUser(userId: UUID, reason: String) async throws {
        try await verifyAdminStatus()

        guard userId != authService.currentUserId else {
            throw AppError.unknown("Cannot restrict your own account")
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw AppError.unknown("A reason is required to restrict a user")
        }

        guard let adminId = authService.currentUserId else {
            throw AppError.unauthorized
        }

        let updates: [String: AnyCodable] = [
            "is_banned": AnyCodable(true),
            "ban_reason": AnyCodable(trimmedReason),
            "banned_at": AnyCodable(ISO8601DateFormatter().string(from: Date())),
            "banned_by": AnyCodable(adminId.uuidString),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]

        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId.uuidString)
            .execute()

        Log.security("Admin \(adminId) banned user \(userId): \(trimmedReason)")
        AppLogger.info("admin", "Banned user \(userId)")
    }

    /// Unban/remove restriction from a user account
    /// - Parameter userId: ID of user to unban
    /// - Throws: AppError if not admin or operation fails
    func unbanUser(userId: UUID) async throws {
        try await verifyAdminStatus()

        let updates: [String: AnyCodable] = [
            "is_banned": AnyCodable(false),
            "ban_reason": AnyCodable(NSNull()),
            "banned_at": AnyCodable(NSNull()),
            "banned_by": AnyCodable(NSNull()),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]

        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId.uuidString)
            .execute()

        Log.security("Admin \(authService.currentUserId?.uuidString ?? "unknown") unbanned user \(userId)")
        AppLogger.info("admin", "Unbanned user \(userId)")
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
        
        AppLogger.info("admin", "Sent broadcast to \(count) users")
        
        // Note: Push notifications would be triggered via Edge Function
        // This would be implemented separately via Supabase Edge Functions
    }
}

