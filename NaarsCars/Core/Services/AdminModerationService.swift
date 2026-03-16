//
//  AdminModerationService.swift
//  NaarsCars
//
//  Service for admin content moderation actions
//

import Foundation
import Supabase

struct AdminReport: Codable, Identifiable, Equatable {
    let reportId: UUID
    let reporterId: UUID
    let reporterName: String?
    let reportedUserId: UUID?
    let reportedUserName: String?
    let reportedPostId: UUID?
    let reportedCommentId: UUID?
    let reportType: String
    let description: String?
    let status: String
    let createdAt: Date
    let reviewedAt: Date?
    let contentPreview: String?
    let contentHidden: Bool
    let reportCount: Int

    var id: UUID { reportId }

    var reportTypeDisplay: String {
        reportType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var isPost: Bool { reportedPostId != nil }
    var isComment: Bool { reportedCommentId != nil }
    var contentTypeLabel: String {
        if reportedPostId != nil { return "Post" }
        if reportedCommentId != nil { return "Comment" }
        if reportedUserId != nil { return "User" }
        return "Message"
    }
}

final class AdminModerationService {
    static let shared = AdminModerationService()
    private let supabase = SupabaseService.shared.client

    private init() {}

    func fetchReports(status: String? = nil) async throws -> [AdminReport] {
        guard let userId = AuthService.shared.currentUserId else {
            throw AppError.unauthorized
        }

        var params: [String: String] = ["p_admin_id": userId.uuidString]
        if let status {
            params["p_status"] = status
        }

        let response = try await supabase.rpc("admin_get_reports", params: params).execute()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date")
        }
        return try decoder.decode([AdminReport].self, from: response.data)
    }

    func moderateContent(reportId: UUID, action: String, notes: String? = nil) async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw AppError.unauthorized
        }

        try await supabase.rpc("admin_moderate_content", params: [
            "p_admin_id": userId.uuidString,
            "p_report_id": reportId.uuidString,
            "p_action": action,
            "p_admin_notes": notes ?? ""
        ]).execute()
    }
}
