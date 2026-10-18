//
//  ProfileService+Search.swift
//  NaarsCars
//
//  Member search through the search_community_members RPC
//

import Foundation
import Supabase

/// Parameters for `search_community_members`. `p_community_id` is omitted when nil:
/// the server default (null) means "the union of my communities".
private struct SearchCommunityMembersParams: Encodable {
    let p_query: String
    let p_community_id: UUID?
    let p_limit: Int

    enum CodingKeys: String, CodingKey {
        case p_query, p_community_id, p_limit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_query, forKey: .p_query)
        try container.encodeIfPresent(p_community_id, forKey: .p_community_id)
        try container.encode(p_limit, forKey: .p_limit)
    }
}

extension ProfileService {

    /// Search members by name through `search_community_members` (blocks are filtered on the server).
    /// - Parameters:
    ///   - query: Trimmed, non-empty search text (callers enforce the minimum length)
    ///   - communityId: Restrict to one community; nil searches the union of the caller's communities
    ///   - limit: Maximum rows (Constants.PageSizes.userSearch)
    func searchCommunityMembers(query: String, communityId: UUID?, limit: Int) async throws -> [Profile] {
        AppLogger.info("messaging", "ProfileService searching community members for: '\(query)'")

        let response = try await SupabaseService.shared.client
            .rpc(
                "search_community_members",
                params: SearchCommunityMembersParams(p_query: query, p_community_id: communityId, p_limit: limit)
            )
            .execute()

        // Rows carry public_profiles' columns; Profile's decoder defaults the rest.
        return try DateDecoderFactory.makeSupabaseDecoder().decode([Profile].self, from: response.data)
    }
}
