//
//  CommunityService.swift
//  NaarsCars
//
//  Member-side community calls: memberships, create, invite codes, join, leave, mute, report.
//  Every envelope RPC answers HTTP 200; a refusal is `{success:false, error, code?}` and is
//  thrown as a `CommunityRPCError` by `CommunityRPC`.
//

import Foundation
import Supabase

// MARK: - RPC parameters (explicit keys; optionals are omitted when nil)

private struct CreateCommunityParams: Encodable, Sendable {
    let name: String
    let description: String?
    let joinPolicy: String

    private enum CodingKeys: String, CodingKey {
        case p_name, p_description, p_join_policy
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .p_name)
        try c.encodeIfPresent(description, forKey: .p_description)
        try c.encode(joinPolicy, forKey: .p_join_policy)
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

    func createCommunity(name: String, description: String?, joinPolicy: CommunityJoinPolicy) async throws -> CreatedCommunity {
        let params = CreateCommunityParams(name: name, description: description, joinPolicy: joinPolicy.rawValue)
        let response = try await client.rpc("create_community", params: params).execute()
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
}
