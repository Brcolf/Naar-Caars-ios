//
//  ProfileService+AccountStatus.swift
//  NaarsCars
//
//  Own-row account status reads/writes: ban reason, application submission
//

import Foundation
import Supabase

extension ProfileService {

    /// Minimal response struct for fetching only the ban reason column
    private struct BanReasonResponse: Decodable {
        let banReason: String?
        enum CodingKeys: String, CodingKey {
            case banReason = "ban_reason"
        }
    }

    /// Fetch the current user's ban reason straight from `profiles`.
    /// Deliberately bypasses the profile cache: a ban may post-date the cached row.
    /// - Parameter userId: The current user's ID (own row; RLS allows reading it)
    /// - Returns: The ban reason, or nil when none is set
    func fetchBanReason(userId: UUID) async throws -> String? {
        let response: BanReasonResponse = try await SupabaseService.shared.client
            .from("profiles")
            .select("ban_reason")
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
        return response.banReason
    }

    /// Store the post-auth application answers and mark the application complete.
    /// Inputs must already be sanitized by the caller (see ApplicationFieldsViewModel).
    func submitApplication(userId: UUID, heardAbout: String, joinReason: String) async throws {
        try await SupabaseService.shared.client
            .from("profiles")
            .update([
                "heard_about": AnyCodable(heardAbout),
                "join_reason": AnyCodable(joinReason),
                "application_complete": AnyCodable(true),
                "application_submitted_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
            ])
            .eq("id", value: userId.uuidString)
            .execute()
    }
}
