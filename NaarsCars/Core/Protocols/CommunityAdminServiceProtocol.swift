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
}
