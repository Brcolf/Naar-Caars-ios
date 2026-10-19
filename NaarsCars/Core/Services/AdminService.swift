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

// MARK: - Community RPC parameters (explicit keys; optionals are omitted when nil)

/// `p_community_id` only; nil means every community (platform admins only).
private struct StatsScopeParams: Encodable, Sendable {
    let communityId: String?

    private enum CodingKeys: String, CodingKey { case p_community_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(communityId, forKey: .p_community_id)
    }
}

private struct StatsBreakdownParams: Encodable, Sendable {
    let communityId: String?
    let period: String
    let count: Int

    private enum CodingKeys: String, CodingKey { case p_community_id, p_period, p_count }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(communityId, forKey: .p_community_id)
        try c.encode(period, forKey: .p_period)
        try c.encode(count, forKey: .p_count)
    }
}

/// `p_type` is omitted: the server default is 'broadcast'.
private struct CommunityBroadcastParams: Encodable, Sendable {
    let communityId: String
    let title: String
    let body: String
    let pinned: Bool

    private enum CodingKeys: String, CodingKey { case p_community_id, p_title, p_body, p_pinned }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encode(title, forKey: .p_title)
        try c.encode(body, forKey: .p_body)
        try c.encode(pinned, forKey: .p_pinned)
    }
}

private struct CommunityReportsParams: Encodable, Sendable {
    let communityId: String
    let status: String?

    private enum CodingKeys: String, CodingKey { case p_community_id, p_status }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encodeIfPresent(status, forKey: .p_status)
    }
}

private struct CommunityModerationParams: Encodable, Sendable {
    let reportId: String
    let action: String
    let reason: String?

    private enum CodingKeys: String, CodingKey { case p_report_id, p_action, p_reason }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reportId, forKey: .p_report_id)
        try c.encode(action, forKey: .p_action)
        try c.encodeIfPresent(reason, forKey: .p_reason)
    }
}

/// The `{success: true, rows: [...]}` payload of the three statistics breakdowns.
private struct StatsRows<Row: Decodable>: Decodable {
    let rows: [Row]

    private enum CodingKeys: String, CodingKey { case rows }
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
            AppLogger.error("security", "Non-admin attempted admin operation: \(userId)")
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
    
    /// An applicant's email and phone, for a platform admin's Requests to join detail.
    /// Reads the `profiles` table, which a platform admin may read (`profiles_select_admin`);
    /// `public_profiles` has neither column. Never cached.
    /// - Throws: AppError.unauthorized if not a platform admin, or the read's error
    func fetchApplicantContact(userId: UUID) async throws -> ApplicantContact {
        try await verifyAdminStatus()

        let response = try await supabase
            .from("profiles")
            .select("email, phone_number")
            .eq("id", value: userId.uuidString)
            .single()
            .execute()

        return try JSONDecoder().decode(ApplicantContact.self, from: response.data)
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
    
    // MARK: - Figures (by community)
    //
    // The server checks the caller (`can_read_community_stats`, 20261018_0002 block 1): a platform
    // admin for every community or any one, a community's owners and admins for theirs. These calls
    // do not run `verifyAdminStatus()`, so a community admin reaches them.

    /// Summary figures for one community, or every community when `communityId` is nil.
    func fetchDashboardStats(communityId: UUID?) async throws -> AdminDashboardStats {
        let params = StatsScopeParams(communityId: communityId?.uuidString)
        let response = try await supabase
            .rpc("get_community_stats", params: params)
            .execute()

        let stats = try CommunityRPC.decode(AdminDashboardStats.self, from: response.data)
        AppLogger.info("admin", "Dashboard stats: \(stats.fulfilledCount) fulfilled, $\(stats.totalSavings) savings, \(stats.activeRidesCount) active")
        return stats
    }

    /// Fulfilled requests by period for one community, or every community when `communityId` is nil.
    func fetchFulfilledBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [FulfilledPeriod] {
        let params = StatsBreakdownParams(communityId: communityId?.uuidString, period: period, count: count)
        let response = try await supabase
            .rpc("get_community_stats_fulfilled", params: params)
            .execute()
        return try CommunityRPC.decode(StatsRows<FulfilledPeriod>.self, from: response.data).rows
    }

    /// Savings by period for one community, or every community when `communityId` is nil.
    func fetchSavingsBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [SavingsPeriod] {
        let params = StatsBreakdownParams(communityId: communityId?.uuidString, period: period, count: count)
        let response = try await supabase
            .rpc("get_community_stats_savings", params: params)
            .execute()
        return try CommunityRPC.decode(StatsRows<SavingsPeriod>.self, from: response.data).rows
    }

    /// Active (unfinished) rides and favors of one community, or every community when `communityId` is nil.
    func fetchActiveRequests(communityId: UUID?) async throws -> [ActiveRequestRow] {
        let params = StatsScopeParams(communityId: communityId?.uuidString)
        let response = try await supabase
            .rpc("get_community_stats_active_requests", params: params)
            .execute()
        return try CommunityRPC.decode(StatsRows<ActiveRequestRow>.self, from: response.data).rows
    }

    // MARK: - Announcements (by community)

    /// Posts an announcement to one community's Town Hall and tells its members.
    /// `send_community_broadcast` raises instead of answering an envelope: SQLSTATE P0001 (3 a day)
    /// becomes `AdminServiceError.broadcastDailyLimit`, 42501 `.notCommunityAdmin`.
    /// - Returns: the number of members told
    func sendBroadcast(communityId: UUID, title: String, message: String, pinToNotifications: Bool) async throws -> Int {
        let params = CommunityBroadcastParams(
            communityId: communityId.uuidString,
            title: title,
            body: message,
            pinned: pinToNotifications
        )
        do {
            let response = try await supabase
                .rpc("send_community_broadcast", params: params)
                .execute()
            let count = try JSONDecoder().decode(Int.self, from: response.data)
            AppLogger.info("admin", "Sent an announcement to \(count) members of \(communityId)")
            return count
        } catch let error as PostgrestError {
            switch error.code {
            case "P0001":
                throw AdminServiceError.broadcastDailyLimit
            case "42501":
                throw AdminServiceError.notCommunityAdmin
            default:
                throw error
            }
        }
    }

    // MARK: - Community reports (by community)

    /// A community's reports, without the reporter (INV-P2). `status` nil = every status.
    func fetchCommunityReports(communityId: UUID, status: String?) async throws -> [CommunityReport] {
        let params = CommunityReportsParams(communityId: communityId.uuidString, status: status)
        let response = try await supabase
            .rpc("get_community_reports", params: params)
            .execute()
        return try CommunityRPC.decode(CommunityReportsPayload.self, from: response.data).reports
    }

    /// Hide, restore or dismiss for one report of a community the caller administers.
    func moderateCommunityContent(reportId: UUID, action: CommunityModerationAction, reason: String?) async throws {
        let params = CommunityModerationParams(reportId: reportId.uuidString, action: action.rawValue, reason: reason)
        let response = try await supabase
            .rpc("moderate_community_content", params: params)
            .execute()
        try CommunityRPC.decodeSuccess(from: response.data)
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
            AppLogger.error("security", "Admin approved user: \(userId)")
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
            AppLogger.error("security", "Admin rejected user: \(userId)")
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
        
        AppLogger.error("security", "Admin set admin status for \(userId): \(isAdmin)")
        
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

        AppLogger.error("security", "Admin \(adminId) banned user \(userId): \(trimmedReason)")
        AppLogger.info("admin", "Banned user \(userId)")
    }

    /// Unban/remove restriction from a user account
    /// - Parameter userId: ID of user to unban
    /// - Throws: AppError if not admin or operation fails
    func unbanUser(userId: UUID) async throws {
        try await verifyAdminStatus()

        let updates: [String: AnyCodable] = [
            "is_banned": AnyCodable(false),
            "ban_reason": AnyCodable(Optional<String>.none),
            "banned_at": AnyCodable(Optional<String>.none),
            "banned_by": AnyCodable(Optional<String>.none),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]

        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId.uuidString)
            .execute()

        AppLogger.error("security", "Admin \(authService.currentUserId?.uuidString ?? "unknown") unbanned user \(userId)")
        AppLogger.info("admin", "Unbanned user \(userId)")
    }
}

extension AdminService: ApplicantContactFetching {}

extension AdminService: AdminServiceProtocol {}
