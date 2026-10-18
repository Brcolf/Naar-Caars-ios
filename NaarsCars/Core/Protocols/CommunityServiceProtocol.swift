//
//  CommunityServiceProtocol.swift
//  NaarsCars
//
//  Protocol abstraction for the member-side community calls
//

import Foundation

protocol CommunityServiceProtocol: AnyObject {
    /// Active and pending memberships of the signed-in user.
    func fetchMyMemberships() async throws -> [CommunityMembership]

    func createCommunity(name: String, description: String?, joinPolicy: CommunityJoinPolicy) async throws -> CreatedCommunity
    func fetchMyCommunityLimits() async throws -> CommunityLimits
    func requestOwnedCommunityLimit(requested: Int, reason: String) async throws -> LimitRequestReceipt

    func createInvite(communityId: UUID, maxUses: Int?, expiresAt: Date?) async throws -> CommunityInvite
    /// The caller's own codes for a community that still work.
    func fetchLiveInvites(communityId: UUID, createdBy: UUID) async throws -> [CommunityInviteRow]
    func revokeInvite(inviteId: UUID) async throws
    /// `code` must already be normalized (`CommunityInviteCode.normalize`) and well formed.
    func validateInvite(code: String) async throws -> InvitePreview
    func redeemInvite(code: String, heardAbout: String?, joinReason: String?) async throws -> JoinResult

    func fetchPublicCommunities() async throws -> [PublicCommunity]
    func requestToJoin(communityId: UUID, heardAbout: String?, joinReason: String?) async throws -> JoinResult
    func leaveCommunity(communityId: UUID) async throws -> LeaveResult
    func setCommunityMuted(communityId: UUID, muted: Bool) async throws

    /// Reports a community by id or by a code the reporter holds (exactly one of the two).
    func reportCommunity(communityId: UUID?, code: String?, type: MessageService.ReportType, description: String?) async throws -> CommunityReportResult
}
