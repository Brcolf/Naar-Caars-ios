//
//  CommunityMergeServiceProtocol.swift
//  NaarsCars
//
//  Protocol abstraction for the six community-merge calls (20261021_0022)
//

import Foundation

protocol CommunityMergeServiceProtocol: AnyObject {
    /// `search_merge_targets`: owners only; fewer than two characters answers an empty list.
    func searchMergeTargets(communityId: UUID, query: String) async throws -> [MergeTarget]

    /// `propose_community_merge`: returns the new proposal's id. `survivorId` is one of the two
    /// communities; `note` is omitted when nil.
    func proposeMerge(communityId: UUID, otherId: UUID, survivorId: UUID, note: String?) async throws -> UUID

    /// `get_community_merge_proposal`: the open proposal the community is part of, or nil.
    func fetchMergeProposal(communityId: UUID) async throws -> CommunityMergeProposal?

    /// `respond_to_community_merge`: an accept returns the outcome, a decline returns nil. A proposal
    /// that closed meanwhile throws `CommunityRPCError` with `.proposalClosed`.
    func respondToMerge(proposalId: UUID, accept: Bool) async throws -> CommunityMergeOutcome?

    /// `withdraw_community_merge`.
    func withdrawMerge(proposalId: UUID) async throws

    /// `get_my_community_merges`: merges of the last 90 days that touched the caller's memberships.
    func fetchMyCommunityMerges() async throws -> [CommunityMerge]
}
