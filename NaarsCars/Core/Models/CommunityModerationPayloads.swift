//
//  CommunityModerationPayloads.swift
//  NaarsCars
//
//  Payloads and errors of the community admin calls on AdminService: community reports,
//  community moderation and announcements (supabase/migrations/20261018_0001, 20261018_0002)
//

import Foundation

// MARK: - Community reports

/// One row of `get_community_reports` (20261018_0001 block 3). There is deliberately no reporter
/// field (INV-P2): a community admin never learns who filed a report. `description` is the
/// reporter's own note about the content, shown under "Reporter's note".
struct CommunityReport: Identifiable, Equatable, Sendable {
    let reportId: UUID
    /// town_hall_post | town_hall_comment | ride | favor | user
    let targetType: String
    let reportedUserId: UUID?
    let reportedUserName: String?
    let authorId: UUID?
    let authorName: String?
    let reportedPostId: UUID?
    let reportedCommentId: UUID?
    let reportedRideId: UUID?
    let reportedFavorId: UUID?
    /// The post a reported post or comment belongs to.
    let townHallPostId: UUID?
    let reportType: String
    let description: String?
    /// The community's view: the platform status once a platform admin reviewed the report,
    /// else the community's own decision, else "pending".
    let status: String
    let createdAt: Date
    let reviewedAt: Date?
    let contentPreview: String?
    let contentHidden: Bool
    let reportCount: Int
    /// `can_restore`: the content is hidden and the caller may restore it.
    let canRestore: Bool
    /// `platform_handled`: a platform admin reviewed the report; no hide and no dismiss here.
    let platformHandled: Bool

    var id: UUID { reportId }
    var isPersonReport: Bool { targetType == "user" }
}

extension CommunityReport: Decodable {
    private enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case targetType = "target_type"
        case reportedUserId = "reported_user_id"
        case reportedUserName = "reported_user_name"
        case authorId = "author_id"
        case authorName = "author_name"
        case reportedPostId = "reported_post_id"
        case reportedCommentId = "reported_comment_id"
        case reportedRideId = "reported_ride_id"
        case reportedFavorId = "reported_favor_id"
        case townHallPostId = "town_hall_post_id"
        case reportType = "report_type"
        case description
        case status
        case createdAt = "created_at"
        case reviewedAt = "reviewed_at"
        case contentPreview = "content_preview"
        case contentHidden = "content_hidden"
        case reportCount = "report_count"
        case canRestore = "can_restore"
        case platformHandled = "platform_handled"
    }

    /// The flags default to false and `report_count` to 1 when absent: an older server answers
    /// without them, and false offers less.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reportId = try c.decode(UUID.self, forKey: .reportId)
        targetType = try c.decode(String.self, forKey: .targetType)
        reportedUserId = try c.decodeIfPresent(UUID.self, forKey: .reportedUserId)
        reportedUserName = try c.decodeIfPresent(String.self, forKey: .reportedUserName)
        authorId = try c.decodeIfPresent(UUID.self, forKey: .authorId)
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName)
        reportedPostId = try c.decodeIfPresent(UUID.self, forKey: .reportedPostId)
        reportedCommentId = try c.decodeIfPresent(UUID.self, forKey: .reportedCommentId)
        reportedRideId = try c.decodeIfPresent(UUID.self, forKey: .reportedRideId)
        reportedFavorId = try c.decodeIfPresent(UUID.self, forKey: .reportedFavorId)
        townHallPostId = try c.decodeIfPresent(UUID.self, forKey: .townHallPostId)
        reportType = try c.decode(String.self, forKey: .reportType)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        status = try c.decode(String.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        reviewedAt = try c.decodeIfPresent(Date.self, forKey: .reviewedAt)
        contentPreview = try c.decodeIfPresent(String.self, forKey: .contentPreview)
        contentHidden = try c.decodeIfPresent(Bool.self, forKey: .contentHidden) ?? false
        reportCount = try c.decodeIfPresent(Int.self, forKey: .reportCount) ?? 1
        canRestore = try c.decodeIfPresent(Bool.self, forKey: .canRestore) ?? false
        platformHandled = try c.decodeIfPresent(Bool.self, forKey: .platformHandled) ?? false
    }
}

/// The successful payload of `get_community_reports`: `{success: true, reports: [...]}`.
struct CommunityReportsPayload: Decodable, Sendable {
    let reports: [CommunityReport]

    private enum CodingKeys: String, CodingKey { case reports }
}

// MARK: - Community moderation

/// The `p_action` values of `moderate_community_content` (20261018_0001 block 4).
enum CommunityModerationAction: String, CaseIterable, Sendable {
    case hide
    case restore
    case dismiss
}

// MARK: - Errors

/// Errors of `send_community_broadcast`, which raises instead of answering an envelope.
enum AdminServiceError: Error, Equatable {
    /// SQLSTATE P0001: the community has sent 3 announcements in the last 24 hours.
    case broadcastDailyLimit
    /// SQLSTATE 42501: the caller is not an admin of that community.
    case notCommunityAdmin
}
