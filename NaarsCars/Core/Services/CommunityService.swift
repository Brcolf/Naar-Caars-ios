//
//  CommunityService.swift
//  NaarsCars
//
//  Member-side community calls: memberships, create, invite codes, join, leave, mute, report,
//  and discovery (search by name or place, area checks, service areas).
//  Every envelope RPC answers HTTP 200; a refusal is `{success:false, error, code?}` and is
//  thrown as a `CommunityRPCError` by `CommunityRPC`.
//

import Foundation
import Supabase

// MARK: - RPC parameters (explicit keys; optionals are omitted when nil)

/// `create_community_with_area(p_name, p_description, p_join_policy, p_timezone, p_listed, p_area_name,
/// p_center_lat, p_center_lng, p_radius_miles, p_reason)` (20261021_0021 block 4). `p_listed` is always
/// sent; the area and the reason only for a listed community; nil values are omitted, never sent as null.
private struct CreateCommunityWithAreaParams: Encodable, Sendable {
    let draft: NewCommunityDraft

    private enum CodingKeys: String, CodingKey {
        case p_name, p_description, p_join_policy, p_timezone, p_listed
        case p_area_name, p_center_lat, p_center_lng, p_radius_miles, p_reason
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(draft.name, forKey: .p_name)
        try c.encodeIfPresent(draft.description, forKey: .p_description)
        try c.encode(draft.joinPolicy.rawValue, forKey: .p_join_policy)
        try c.encodeIfPresent(draft.timezone, forKey: .p_timezone)
        try c.encode(draft.area != nil, forKey: .p_listed)
        guard let area = draft.area else { return }
        try c.encode(area.name, forKey: .p_area_name)
        try c.encode(area.center.latitude, forKey: .p_center_lat)
        try c.encode(area.center.longitude, forKey: .p_center_lng)
        try c.encode(area.radiusMiles, forKey: .p_radius_miles)
        try c.encodeIfPresent(draft.reason, forKey: .p_reason)
    }
}

/// `search_communities_by_name(p_query)` (20261021_0021 block 1).
private struct SearchByNameParams: Encodable, Sendable {
    let query: String

    private enum CodingKeys: String, CodingKey { case p_query }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(query, forKey: .p_query)
    }
}

/// `find_communities_near(p_lat, p_lng)` (20261021_0021 block 2). The point is sent as given.
private struct FindNearParams: Encodable, Sendable {
    let point: GeoPoint

    private enum CodingKeys: String, CodingKey { case p_lat, p_lng }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(point.latitude, forKey: .p_lat)
        try c.encode(point.longitude, forKey: .p_lng)
    }
}

/// `check_community_area(p_center_lat, p_center_lng, p_radius_miles, p_community_id)` (20261021_0021
/// block 3). `p_community_id` is omitted when nil (a community being created).
private struct CheckAreaParams: Encodable, Sendable {
    let area: ServiceArea
    let communityId: String?

    private enum CodingKeys: String, CodingKey { case p_center_lat, p_center_lng, p_radius_miles, p_community_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(area.center.latitude, forKey: .p_center_lat)
        try c.encode(area.center.longitude, forKey: .p_center_lng)
        try c.encode(area.radiusMiles, forKey: .p_radius_miles)
        try c.encodeIfPresent(communityId, forKey: .p_community_id)
    }
}

/// `update_community_access(p_community_id, p_listed, p_join_policy, p_area_name, p_center_lat,
/// p_center_lng, p_radius_miles, p_reason)` (20261021_0021 block 5). The area only when a new one is
/// set; the reason only while listed; nil values are omitted.
private struct UpdateAccessParams: Encodable, Sendable {
    let communityId: String
    let change: CommunityAccessChange

    private enum CodingKeys: String, CodingKey {
        case p_community_id, p_listed, p_join_policy
        case p_area_name, p_center_lat, p_center_lng, p_radius_miles, p_reason
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encode(change.isListed, forKey: .p_listed)
        try c.encode(change.joinPolicy.rawValue, forKey: .p_join_policy)
        if let area = change.newArea {
            try c.encode(area.name, forKey: .p_area_name)
            try c.encode(area.center.latitude, forKey: .p_center_lat)
            try c.encode(area.center.longitude, forKey: .p_center_lng)
            try c.encode(area.radiusMiles, forKey: .p_radius_miles)
        }
        if change.isListed {
            try c.encodeIfPresent(change.reason, forKey: .p_reason)
        }
    }
}

private struct RequestLimitParams: Encodable, Sendable {
    let requested: Int
    let reason: String

    private enum CodingKeys: String, CodingKey { case p_requested, p_reason }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requested, forKey: .p_requested)
        try c.encode(reason, forKey: .p_reason)
    }
}

private struct CreateInviteParams: Encodable, Sendable {
    let communityId: String
    let maxUses: Int?
    /// ISO 8601 text; the function declares a timestamptz.
    let expiresAt: String?

    private enum CodingKeys: String, CodingKey { case p_community_id, p_max_uses, p_expires_at }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encodeIfPresent(maxUses, forKey: .p_max_uses)
        try c.encodeIfPresent(expiresAt, forKey: .p_expires_at)
    }
}

private struct InviteIdParams: Encodable, Sendable {
    let inviteId: String

    private enum CodingKeys: String, CodingKey { case p_invite_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inviteId, forKey: .p_invite_id)
    }
}

private struct CodeParams: Encodable, Sendable {
    let code: String

    private enum CodingKeys: String, CodingKey { case p_code }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .p_code)
    }
}

private struct RedeemInviteParams: Encodable, Sendable {
    let code: String
    let heardAbout: String?
    let joinReason: String?

    private enum CodingKeys: String, CodingKey { case p_code, p_heard_about, p_join_reason }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .p_code)
        try c.encodeIfPresent(heardAbout, forKey: .p_heard_about)
        try c.encodeIfPresent(joinReason, forKey: .p_join_reason)
    }
}

private struct RequestToJoinParams: Encodable, Sendable {
    let communityId: String
    let heardAbout: String?
    let joinReason: String?

    private enum CodingKeys: String, CodingKey { case p_community_id, p_heard_about, p_join_reason }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encodeIfPresent(heardAbout, forKey: .p_heard_about)
        try c.encodeIfPresent(joinReason, forKey: .p_join_reason)
    }
}

private struct CommunityIdParams: Encodable, Sendable {
    let communityId: String

    private enum CodingKeys: String, CodingKey { case p_community_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
    }
}

private struct ReportCommunityParams: Encodable, Sendable {
    let communityId: String?
    let code: String?
    let reportType: String
    let description: String?

    private enum CodingKeys: String, CodingKey { case p_community_id, p_code, p_report_type, p_description }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(communityId, forKey: .p_community_id)
        try c.encodeIfPresent(code, forKey: .p_code)
        try c.encode(reportType, forKey: .p_report_type)
        try c.encodeIfPresent(description, forKey: .p_description)
    }
}

private struct MembersParams: Encodable, Sendable {
    let communityId: String
    let status: String
    let limit: Int
    let offset: Int

    private enum CodingKeys: String, CodingKey { case p_community_id, p_status, p_limit, p_offset }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encode(status, forKey: .p_status)
        try c.encode(limit, forKey: .p_limit)
        try c.encode(offset, forKey: .p_offset)
    }
}

private struct MemberDecisionParams: Encodable, Sendable {
    let communityId: String
    let userId: String

    private enum CodingKeys: String, CodingKey { case p_community_id, p_user_id }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encode(userId, forKey: .p_user_id)
    }
}

private struct SetPublicParams: Encodable, Sendable {
    let communityId: String
    let isPublic: Bool

    private enum CodingKeys: String, CodingKey { case p_community_id, p_is_public }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encode(isPublic, forKey: .p_is_public)
    }
}

private struct LimitDecisionParams: Encodable, Sendable {
    let requestId: String
    let approve: Bool

    private enum CodingKeys: String, CodingKey { case p_request_id, p_approve }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .p_request_id)
        try c.encode(approve, forKey: .p_approve)
    }
}

private struct RemoveMemberParams: Encodable, Sendable {
    let communityId: String
    /// The member being removed, never the caller.
    let userId: String
    let reason: String?

    private enum CodingKeys: String, CodingKey { case p_community_id, p_user_id, p_reason }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encode(userId, forKey: .p_user_id)
        try c.encodeIfPresent(reason, forKey: .p_reason)
    }
}

private struct SetMemberRoleParams: Encodable, Sendable {
    let communityId: String
    let userId: String
    /// `CommunityRole.rawValue`: owner, admin or member.
    let role: String

    private enum CodingKeys: String, CodingKey { case p_community_id, p_user_id, p_role }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encode(userId, forKey: .p_user_id)
        try c.encode(role, forKey: .p_role)
    }
}

/// `update_community`: only the set fields are sent; `p_timezone` only when the time zone changed.
/// A nil field is omitted (the server leaves it unchanged); an empty description is sent as "" and
/// clears it.
private struct UpdateCommunityParams: Encodable, Sendable {
    let communityId: String
    let name: String?
    let description: String?
    let joinPolicy: String?
    let membersCanInvite: Bool?
    let timezone: String?

    private enum CodingKeys: String, CodingKey {
        case p_community_id, p_name, p_description, p_join_policy, p_members_can_invite, p_timezone
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .p_community_id)
        try c.encodeIfPresent(name, forKey: .p_name)
        try c.encodeIfPresent(description, forKey: .p_description)
        try c.encodeIfPresent(joinPolicy, forKey: .p_join_policy)
        try c.encodeIfPresent(membersCanInvite, forKey: .p_members_can_invite)
        try c.encodeIfPresent(timezone, forKey: .p_timezone)
    }
}

/// Body of the mute update. `muted_until` is sent as an explicit null so a timed mute set
/// elsewhere is cleared.
private struct MuteBody: Encodable, Sendable {
    let muted: Bool

    private enum CodingKeys: String, CodingKey { case notifications_muted, muted_until }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(muted, forKey: .notifications_muted)
        try c.encodeNil(forKey: .muted_until)
    }
}

// MARK: - Service

final class CommunityService: CommunityServiceProtocol {
    static let shared = CommunityService()

    private init() {}

    private var client: SupabaseClient { SupabaseService.shared.client }

    func fetchMyMemberships() async throws -> [CommunityMembership] {
        let response = try await client
            .rpc("get_my_memberships")
            .execute()
        return try DateDecoderFactory.makeSupabaseDecoder()
            .decode([CommunityMembership].self, from: response.data)
    }

    func createCommunity(_ draft: NewCommunityDraft) async throws -> CreatedCommunity {
        let response = try await client
            .rpc("create_community_with_area", params: CreateCommunityWithAreaParams(draft: draft))
            .execute()
        return try CommunityRPC.decode(CreatedCommunity.self, from: response.data)
    }

    func fetchMyCommunityLimits() async throws -> CommunityLimits {
        let response = try await client.rpc("get_my_community_limits").execute()
        return try CommunityRPC.decode(CommunityLimits.self, from: response.data)
    }

    func requestOwnedCommunityLimit(requested: Int, reason: String) async throws -> LimitRequestReceipt {
        let params = RequestLimitParams(requested: requested, reason: reason)
        let response = try await client.rpc("request_owned_community_limit", params: params).execute()
        return try CommunityRPC.decode(LimitRequestReceipt.self, from: response.data)
    }

    func createInvite(communityId: UUID, maxUses: Int?, expiresAt: Date?) async throws -> CommunityInvite {
        let params = CreateInviteParams(
            communityId: communityId.uuidString,
            maxUses: maxUses,
            expiresAt: expiresAt.map { ISO8601DateFormatter().string(from: $0) }
        )
        let response = try await client.rpc("create_community_invite", params: params).execute()
        return try CommunityRPC.decode(CommunityInvite.self, from: response.data)
    }

    func fetchLiveInvites(communityId: UUID, createdBy: UUID) async throws -> [CommunityInviteRow] {
        let response = try await client
            .from("community_invites")
            .select("id, code, max_uses, use_count, expires_at, revoked_at, created_at")
            .eq("community_id", value: communityId.uuidString)
            .eq("created_by", value: createdBy.uuidString)
            .is("revoked_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
        let rows = try DateDecoderFactory.makeSupabaseDecoder().decode([CommunityInviteRow].self, from: response.data)
        let now = Date()
        return rows.filter { $0.isLive(at: now) }
    }

    func revokeInvite(inviteId: UUID) async throws {
        let response = try await client
            .rpc("revoke_community_invite", params: InviteIdParams(inviteId: inviteId.uuidString))
            .execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func validateInvite(code: String) async throws -> InvitePreview {
        let response = try await client.rpc("validate_community_invite", params: CodeParams(code: code)).execute()
        return try CommunityRPC.decode(InvitePreview.self, from: response.data)
    }

    func redeemInvite(code: String, heardAbout: String?, joinReason: String?) async throws -> JoinResult {
        let params = RedeemInviteParams(code: code, heardAbout: heardAbout, joinReason: joinReason)
        let response = try await client.rpc("redeem_community_invite", params: params).execute()
        return try CommunityRPC.decode(JoinResult.self, from: response.data)
    }

    func fetchPublicCommunities() async throws -> [PublicCommunity] {
        let response = try await client
            .from("communities")
            .select("id, name, description, join_policy, is_default")
            .eq("is_public", value: true)
            .order("name")
            .execute()
        return try DateDecoderFactory.makeSupabaseDecoder().decode([PublicCommunity].self, from: response.data)
    }

    func fetchCommunityPreview(communityId: UUID) async throws -> CommunityPreview {
        let response = try await client
            .rpc("get_community_preview", params: CommunityIdParams(communityId: communityId.uuidString))
            .execute()
        return try CommunityRPC.decode(CommunityPreview.self, from: response.data)
    }

    func requestToJoin(communityId: UUID, heardAbout: String?, joinReason: String?) async throws -> JoinResult {
        let params = RequestToJoinParams(communityId: communityId.uuidString, heardAbout: heardAbout, joinReason: joinReason)
        let response = try await client.rpc("request_to_join_community", params: params).execute()
        return try CommunityRPC.decode(JoinResult.self, from: response.data)
    }

    func leaveCommunity(communityId: UUID) async throws -> LeaveResult {
        let response = try await client
            .rpc("leave_community", params: CommunityIdParams(communityId: communityId.uuidString))
            .execute()
        return try CommunityRPC.decode(LeaveResult.self, from: response.data)
    }

    func setCommunityMuted(communityId: UUID, muted: Bool) async throws {
        struct UpdatedRow: Decodable { let community_id: UUID }
        let response = try await client
            .from("community_members")
            .update(MuteBody(muted: muted))
            .eq("community_id", value: communityId.uuidString)
            .select("community_id")
            .execute()
        let rows = try JSONDecoder().decode([UpdatedRow].self, from: response.data)
        guard !rows.isEmpty else { throw CommunityServiceError.membershipNotUpdated }
    }

    func reportCommunity(communityId: UUID?, code: String?, type: MessageService.ReportType, description: String?) async throws -> CommunityReportResult {
        let params = ReportCommunityParams(
            communityId: communityId?.uuidString,
            code: code,
            reportType: type.rawValue,
            description: description
        )
        let response = try await client.rpc("report_community", params: params).execute()
        return try CommunityRPC.decode(CommunityReportResult.self, from: response.data)
    }

    // MARK: Discovery (20261021_0021 blocks 1-3). The query and the point are never logged.

    func searchCommunities(name: String) async throws -> [CommunitySearchResult] {
        let response = try await client
            .rpc("search_communities_by_name", params: SearchByNameParams(query: name))
            .execute()
        return try CommunityRPC.decode(CommunitySearchResults.self, from: response.data).communities
    }

    func findCommunitiesNear(_ point: GeoPoint) async throws -> [CommunitySearchResult] {
        let response = try await client
            .rpc("find_communities_near", params: FindNearParams(point: point))
            .execute()
        return try CommunityRPC.decode(CommunitySearchResults.self, from: response.data).communities
    }

    func checkCommunityArea(_ area: ServiceArea, excluding communityId: UUID?) async throws -> [CommunitySearchResult] {
        let params = CheckAreaParams(area: area, communityId: communityId?.uuidString)
        let response = try await client.rpc("check_community_area", params: params).execute()
        return try CommunityRPC.decode(CommunitySearchResults.self, from: response.data).communities
    }

    func fetchServiceArea(communityId: UUID) async throws -> ServiceArea? {
        struct AreaRow: Decodable {
            let area: ServiceArea?
            init(from decoder: Decoder) throws { area = try ServiceArea.decodeColumns(from: decoder) }
        }
        let response = try await client
            .from("communities")
            .select("area_name, area_center_lat, area_center_lng, area_radius_miles")
            .eq("id", value: communityId.uuidString)
            .limit(1)
            .execute()
        return try JSONDecoder().decode([AreaRow].self, from: response.data).first?.area
    }
}

// MARK: - Admin

extension CommunityService: CommunityAdminServiceProtocol {
    func fetchCommunityMembers(communityId: UUID, status: MembershipStatus, limit: Int, offset: Int) async throws -> [CommunityMember] {
        let params = MembersParams(communityId: communityId.uuidString, status: status.rawValue, limit: limit, offset: offset)
        let response = try await client.rpc("get_community_members", params: params).execute()
        return try DateDecoderFactory.makeSupabaseDecoder().decode([CommunityMember].self, from: response.data)
    }

    func approveMember(communityId: UUID, userId: UUID) async throws {
        let params = MemberDecisionParams(communityId: communityId.uuidString, userId: userId.uuidString)
        let response = try await client.rpc("approve_community_member", params: params).execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func rejectMember(communityId: UUID, userId: UUID) async throws {
        let params = MemberDecisionParams(communityId: communityId.uuidString, userId: userId.uuidString)
        let response = try await client.rpc("reject_community_member", params: params).execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func fetchDefaultCommunityId() async throws -> UUID? {
        struct Row: Decodable { let id: UUID }
        let response = try await client
            .from("communities")
            .select("id")
            .eq("is_default", value: true)
            .limit(1)
            .execute()
        return try JSONDecoder().decode([Row].self, from: response.data).first?.id
    }

    func fetchPlatformCommunities() async throws -> PlatformCommunities {
        let response = try await client.rpc("get_platform_communities").execute()
        return try CommunityRPC.decode(PlatformCommunities.self, from: response.data)
    }

    func archiveCommunity(communityId: UUID) async throws {
        let response = try await client
            .rpc("archive_community", params: CommunityIdParams(communityId: communityId.uuidString))
            .execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func unarchiveCommunity(communityId: UUID) async throws {
        let response = try await client
            .rpc("unarchive_community", params: CommunityIdParams(communityId: communityId.uuidString))
            .execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func setCommunityPublic(communityId: UUID, isPublic: Bool) async throws {
        let params = SetPublicParams(communityId: communityId.uuidString, isPublic: isPublic)
        let response = try await client.rpc("set_community_public", params: params).execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func decideOwnedCommunityLimit(requestId: UUID, approve: Bool) async throws -> LimitDecision {
        let params = LimitDecisionParams(requestId: requestId.uuidString, approve: approve)
        let response = try await client.rpc("decide_owned_community_limit", params: params).execute()
        return try CommunityRPC.decode(LimitDecision.self, from: response.data)
    }

    // MARK: Member management and settings (20261017_0005 blocks 11, 22-25)

    func removeMember(communityId: UUID, userId: UUID, reason: String?) async throws -> RemovalResult {
        let params = RemoveMemberParams(communityId: communityId.uuidString, userId: userId.uuidString, reason: reason)
        let response = try await client.rpc("remove_community_member", params: params).execute()
        return try CommunityRPC.decode(RemovalResult.self, from: response.data)
    }

    func readmitMember(communityId: UUID, userId: UUID) async throws {
        let params = MemberDecisionParams(communityId: communityId.uuidString, userId: userId.uuidString)
        let response = try await client.rpc("readmit_community_member", params: params).execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func setMemberRole(communityId: UUID, userId: UUID, role: CommunityRole) async throws {
        let params = SetMemberRoleParams(communityId: communityId.uuidString, userId: userId.uuidString, role: role.rawValue)
        let response = try await client.rpc("set_member_role", params: params).execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func transferOwnership(communityId: UUID, userId: UUID) async throws {
        let params = MemberDecisionParams(communityId: communityId.uuidString, userId: userId.uuidString)
        let response = try await client.rpc("transfer_community_ownership", params: params).execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func fetchCommunitySettings(communityId: UUID) async throws -> CommunitySettings {
        let response = try await client
            .from("communities")
            .select("id, name, description, join_policy, members_can_invite, is_public, is_default, timezone, "
                + "area_name, area_center_lat, area_center_lng, area_radius_miles")
            .eq("id", value: communityId.uuidString)
            .limit(1)
            .execute()
        let rows = try DateDecoderFactory.makeSupabaseDecoder().decode([CommunitySettings].self, from: response.data)
        // The SELECT policy hides archived communities and ones the caller may not read.
        guard let settings = rows.first else { throw CommunityServiceError.communityNotFound }
        return settings
    }

    func updateCommunity(communityId: UUID, change: CommunitySettingsChange) async throws {
        let params = UpdateCommunityParams(
            communityId: communityId.uuidString,
            name: change.name,
            description: change.description,
            joinPolicy: change.joinPolicy?.rawValue,
            membersCanInvite: change.membersCanInvite,
            timezone: change.timezone
        )
        let response = try await client.rpc("update_community", params: params).execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }

    func updateCommunityAccess(communityId: UUID, change: CommunityAccessChange) async throws {
        let params = UpdateAccessParams(communityId: communityId.uuidString, change: change)
        let response = try await client.rpc("update_community_access", params: params).execute()
        try CommunityRPC.decodeSuccess(from: response.data)
    }
}
