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

    /// `create_community_with_area`. A draft without an area creates a hidden community; with one, a
    /// listed community (its reason is sent only then). nil values are omitted; `timezone` is an IANA
    /// identifier and the server keeps its column default for one it does not know.
    func createCommunity(_ draft: NewCommunityDraft) async throws -> CreatedCommunity
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
    /// What a visitor may see of a listed community; throws `CommunityRPCError` with `.notListed` when it is not listed.
    func fetchCommunityPreview(communityId: UUID) async throws -> CommunityPreview
    func requestToJoin(communityId: UUID, heardAbout: String?, joinReason: String?) async throws -> JoinResult
    func leaveCommunity(communityId: UUID) async throws -> LeaveResult
    func setCommunityMuted(communityId: UUID, muted: Bool) async throws

    /// Reports a community by id or by a code the reporter holds (exactly one of the two).
    func reportCommunity(communityId: UUID?, code: String?, type: MessageService.ReportType, description: String?) async throws -> CommunityReportResult

    // MARK: Discovery (20261021_0021; the two searches are callable by guests)

    /// Discoverable communities whose name contains `name` (at most 20; `distanceMiles` nil).
    func searchCommunities(name: String) async throws -> [CommunitySearchResult]
    /// Discoverable communities whose area covers `point`, nearest first. The caller rounds the point.
    func findCommunitiesNear(_ point: GeoPoint) async throws -> [CommunitySearchResult]
    /// Listed communities whose area overlaps `area`, other than `communityId` (signed-in callers).
    func checkCommunityArea(_ area: ServiceArea, excluding communityId: UUID?) async throws -> [CommunitySearchResult]
    /// The stored service area of a community the caller may read; nil when it has none.
    func fetchServiceArea(communityId: UUID) async throws -> ServiceArea?
}
