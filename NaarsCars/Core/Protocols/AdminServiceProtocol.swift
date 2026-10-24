//
//  AdminServiceProtocol.swift
//  NaarsCars
//
//  Protocol abstraction for the community-scoped AdminService calls: figures, announcements,
//  community reports and community moderation. The server decides every call.
//

import Foundation

protocol AdminServiceProtocol: AnyObject {
    /// nil = every community (platform admins only; the server refuses anyone else).
    func fetchDashboardStats(communityId: UUID?) async throws -> AdminDashboardStats
    func fetchFulfilledBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [FulfilledPeriod]
    func fetchSavingsBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [SavingsPeriod]
    func fetchActiveRequests(communityId: UUID?) async throws -> [ActiveRequestRow]
    /// Returns the number of members told. Throws AdminServiceError for the cap and for a non-admin.
    func sendBroadcast(communityId: UUID, title: String, message: String, pinToNotifications: Bool) async throws -> Int
    /// The community's reports, without the reporter. `status` nil = every status.
    func fetchCommunityReports(communityId: UUID, status: String?) async throws -> [CommunityReport]
    func moderateCommunityContent(reportId: UUID, action: CommunityModerationAction, reason: String?) async throws
}
