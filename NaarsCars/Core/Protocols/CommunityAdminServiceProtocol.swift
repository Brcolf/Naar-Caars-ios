//
//  CommunityAdminServiceProtocol.swift
//  NaarsCars
//
//  Protocol abstraction for community admin and platform admin calls
//

import Foundation

protocol CommunityAdminServiceProtocol: AnyObject {
    /// Members of one status. A caller who may not see the list gets `[]`.
    func fetchCommunityMembers(communityId: UUID, status: MembershipStatus, limit: Int, offset: Int) async throws -> [CommunityMember]
    func approveMember(communityId: UUID, userId: UUID) async throws
    func rejectMember(communityId: UUID, userId: UUID) async throws
    /// The id of the default community, or nil when it cannot be read.
    func fetchDefaultCommunityId() async throws -> UUID?

    func fetchPlatformCommunities() async throws -> PlatformCommunities
    func archiveCommunity(communityId: UUID) async throws
    func unarchiveCommunity(communityId: UUID) async throws
    func setCommunityPublic(communityId: UUID, isPublic: Bool) async throws
    func decideOwnedCommunityLimit(requestId: UUID, approve: Bool) async throws -> LimitDecision

    // MARK: Member management and settings (20261017_0005 blocks 11, 22-25). `userId` is always the
    // target member, never the caller.

    /// Removes an active member; `reason` is the note the member sees (omitted when nil).
    func removeMember(communityId: UUID, userId: UUID, reason: String?) async throws -> RemovalResult
    /// Lets a removed member back in as a member.
    func readmitMember(communityId: UUID, userId: UUID) async throws
    func setMemberRole(communityId: UUID, userId: UUID, role: CommunityRole) async throws
    /// The caller (an owner) hands ownership to `userId` and becomes an admin.
    func transferOwnership(communityId: UUID, userId: UUID) async throws
    /// Throws `CommunityServiceError.communityNotFound` when the community is archived or not readable.
    func fetchCommunitySettings(communityId: UUID) async throws -> CommunitySettings
    /// Sends only the fields `change` sets.
    func updateCommunity(communityId: UUID, change: CommunitySettingsChange) async throws
}
