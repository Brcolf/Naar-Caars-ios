#if DEBUG
//
//  PreviewAdminService.swift
//  NaarsCars
//
//  An AdminServiceProtocol stand-in for SwiftUI previews: Swift values only, no network, no delay.
//  DEBUG only; previews that use it sit inside #if DEBUG.
//

import Foundation

final class PreviewAdminService: AdminServiceProtocol {
    var stats = AdminDashboardStats(fulfilledCount: 42, totalSavings: 1234, activeRidesCount: 3)
    var fulfilled: [FulfilledPeriod] = [
        FulfilledPeriod(periodStart: PreviewAdminService.day(-1), rideCount: 5, favorCount: 3, totalCount: 8),
        FulfilledPeriod(periodStart: PreviewAdminService.day(-31), rideCount: 4, favorCount: 2, totalCount: 6)
    ]
    var savings: [SavingsPeriod] = [
        SavingsPeriod(periodStart: PreviewAdminService.day(-1), totalSavings: 182.5, rideCount: 5),
        SavingsPeriod(periodStart: PreviewAdminService.day(-31), totalSavings: 96, rideCount: 4)
    ]
    var active: [ActiveRequestRow] = [
        ActiveRequestRow(
            id: UUID(uuidString: "5E000000-0000-4000-8000-0000000000F1")!,
            type: "ride", title: "Ballard", subtitle: "SEA Airport",
            date: PreviewAdminService.day(2), time: "08:30:00", status: "open",
            claimedBy: nil, posterName: "Sam Neighbor", claimerName: nil
        ),
        ActiveRequestRow(
            id: UUID(uuidString: "6E000000-0000-4000-8000-0000000000F1")!,
            type: "favor", title: "Water the plants", subtitle: "Fremont",
            date: PreviewAdminService.day(3), time: nil, status: "confirmed",
            claimedBy: UUID(uuidString: "0A000000-0000-4000-8000-0000000000F2")!,
            posterName: "Dana Rivera", claimerName: "Sam Neighbor"
        )
    ]
    var reports: [CommunityReport] = PreviewAdminService.sampleReports
    /// Thrown by `sendBroadcast` when set (for example `AdminServiceError.broadcastDailyLimit`).
    var broadcastError: Error?
    /// Thrown by `fetchCommunityReports` when set.
    var reportsRefusal: CommunityRPCError?

    func fetchDashboardStats(communityId: UUID?) async throws -> AdminDashboardStats { stats }

    func fetchFulfilledBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [FulfilledPeriod] { fulfilled }

    func fetchSavingsBreakdown(communityId: UUID?, period: String, count: Int) async throws -> [SavingsPeriod] { savings }

    func fetchActiveRequests(communityId: UUID?) async throws -> [ActiveRequestRow] { active }

    func sendBroadcast(communityId: UUID, title: String, message: String, pinToNotifications: Bool) async throws -> Int {
        if let broadcastError { throw broadcastError }
        return 12
    }

    func fetchCommunityReports(communityId: UUID, status: String?) async throws -> [CommunityReport] {
        if let reportsRefusal { throw reportsRefusal }
        guard let status else { return reports }
        return reports.filter { $0.status == status }
    }

    func moderateCommunityContent(reportId: UUID, action: CommunityModerationAction, reason: String?) async throws {}

    // MARK: - Samples

    private static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private static let samAuthor = UUID(uuidString: "0A000000-0000-4000-8000-0000000000F2")!
    private static let danaAuthor = UUID(uuidString: "DDDDDDDD-0000-4000-8000-0000000000F4")!

    /// A post report with an author and a two-line reporter note; a comment report the caller hid
    /// (can restore); a ride report a platform moderator hid (platform handled); a person report.
    static let sampleReports: [CommunityReport] = [
        CommunityReport(
            reportId: UUID(uuidString: "3E000000-0000-4000-8000-0000000000F1")!,
            targetType: "town_hall_post",
            reportedUserId: nil, reportedUserName: nil,
            authorId: samAuthor, authorName: "Sam Neighbor",
            reportedPostId: UUID(uuidString: "4E000000-0000-4000-8000-0000000000F1")!,
            reportedCommentId: nil, reportedRideId: nil, reportedFavorId: nil,
            townHallPostId: UUID(uuidString: "4E000000-0000-4000-8000-0000000000F1")!,
            reportType: "spam",
            description: "Posted the same ad three times today.\nIt keeps pushing other posts down.",
            status: "pending",
            createdAt: day(0), reviewedAt: nil,
            contentPreview: "Selling a couch, best offer, message me", contentHidden: false, reportCount: 2,
            canRestore: false, platformHandled: false
        ),
        CommunityReport(
            reportId: UUID(uuidString: "3E000000-0000-4000-8000-0000000000F2")!,
            targetType: "town_hall_comment",
            reportedUserId: nil, reportedUserName: nil,
            authorId: danaAuthor, authorName: "Dana Rivera",
            reportedPostId: nil,
            reportedCommentId: UUID(uuidString: "7E000000-0000-4000-8000-0000000000F1")!,
            reportedRideId: nil, reportedFavorId: nil,
            townHallPostId: UUID(uuidString: "4E000000-0000-4000-8000-0000000000F2")!,
            reportType: "harassment",
            description: nil,
            status: "action_taken",
            createdAt: day(-1), reviewedAt: day(0),
            contentPreview: "Nobody asked you", contentHidden: true, reportCount: 1,
            canRestore: true, platformHandled: false
        ),
        CommunityReport(
            reportId: UUID(uuidString: "3E000000-0000-4000-8000-0000000000F3")!,
            targetType: "ride",
            reportedUserId: nil, reportedUserName: nil,
            authorId: samAuthor, authorName: "Sam Neighbor",
            reportedPostId: nil, reportedCommentId: nil,
            reportedRideId: UUID(uuidString: "5E000000-0000-4000-8000-0000000000F1")!,
            reportedFavorId: nil,
            townHallPostId: nil,
            reportType: "inappropriate",
            description: "The pickup note is rude.",
            status: "action_taken",
            createdAt: day(-2), reviewedAt: day(-1),
            contentPreview: "Ballard -> SEA Airport", contentHidden: true, reportCount: 3,
            canRestore: false, platformHandled: true
        ),
        CommunityReport(
            reportId: UUID(uuidString: "3E000000-0000-4000-8000-0000000000F4")!,
            targetType: "user",
            reportedUserId: danaAuthor, reportedUserName: "Dana Rivera",
            authorId: nil, authorName: nil,
            reportedPostId: nil, reportedCommentId: nil, reportedRideId: nil, reportedFavorId: nil,
            townHallPostId: nil,
            reportType: "other",
            description: "Did not show up for two rides.",
            status: "pending",
            createdAt: day(-3), reviewedAt: nil,
            contentPreview: "Dana Rivera", contentHidden: false, reportCount: 1,
            canRestore: false, platformHandled: false
        )
    ]
}
#endif
