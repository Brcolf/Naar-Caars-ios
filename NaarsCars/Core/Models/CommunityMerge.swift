//
//  CommunityMerge.swift
//  NaarsCars
//
//  Payloads of the six merge RPCs (20261021_0022): the other communities an owner may propose to,
//  a proposal as one of its two owners sees it, the outcome of accepting, and a merge that touched
//  the caller's memberships.
//

import Foundation

/// One row of `search_merge_targets`: a community an owner could propose a merge with. `areaName`
/// is null for a hidden community (it never reveals its place).
struct MergeTarget: Identifiable, Equatable, Sendable, Decodable {
    let id: UUID
    let name: String
    /// `CommunityJoinPolicy.rawValue`, kept as text so an unknown policy still decodes.
    let joinPolicy: String
    let isPublic: Bool
    let memberCount: Int
    let areaName: String?
}

extension MergeTarget {
    enum CodingKeys: String, CodingKey {
        case id, name
        case joinPolicy = "join_policy"
        case isPublic = "is_public"
        case memberCount = "member_count"
        case areaName = "area_name"
    }
}

/// The `{success, communities}` answer of `search_merge_targets`.
struct MergeTargetResults: Decodable, Sendable {
    let communities: [MergeTarget]
}

/// The pending, unexpired proposal of `get_community_merge_proposal`, seen from the community that
/// was asked about: `direction` is `outgoing` when that community proposed it and `incoming` when
/// the other one did (only the incoming side can accept or decline; either side can withdraw).
struct CommunityMergeProposal: Identifiable, Equatable, Sendable, Decodable {
    enum Direction: String, Decodable {
        case incoming
        case outgoing
    }

    struct Side: Equatable, Sendable, Decodable {
        let id: UUID
        let name: String
        let joinPolicy: String
        let memberCount: Int

        enum CodingKeys: String, CodingKey {
            case id, name
            case joinPolicy = "join_policy"
            case memberCount = "member_count"
        }
    }

    let id: UUID
    let direction: Direction
    let from: Side
    let to: Side
    let survivorId: UUID
    let note: String?
    let proposedByName: String?
    let createdAt: Date
    let expiresAt: Date

    /// The community that keeps its name, settings and page.
    var survivor: Side { survivorId == from.id ? from : to }
    /// The community that is folded into the survivor and archived.
    var merged: Side { survivorId == from.id ? to : from }

    enum CodingKeys: String, CodingKey {
        case id, direction, from, to, note
        case survivorId = "survivor_id"
        case proposedByName = "proposed_by_name"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

/// The `{success, proposal}` answer; `proposal` is null when none is open.
struct CommunityMergeProposalResult: Decodable, Sendable {
    let proposal: CommunityMergeProposal?
}

/// The `{success, proposal_id}` answer of `propose_community_merge`.
struct ProposedMerge: Decodable, Sendable {
    let proposalId: UUID

    enum CodingKeys: String, CodingKey { case proposalId = "proposal_id" }
}

/// What accepting a proposal returns.
struct CommunityMergeOutcome: Equatable, Sendable, Decodable {
    let survivorId: UUID
    let mergedId: UUID

    enum CodingKeys: String, CodingKey {
        case survivorId = "survivor_id"
        case mergedId = "merged_id"
    }
}

/// One row of `get_my_community_merges`: a community merged in the last 90 days in which the caller
/// was an active member. Used to move a stored filter from the merged community to the survivor.
struct CommunityMerge: Equatable, Sendable, Decodable {
    let mergedId: UUID
    let mergedName: String
    let survivorId: UUID
    let survivorName: String
    let mergedAt: Date

    enum CodingKeys: String, CodingKey {
        case mergedId = "merged_id"
        case mergedName = "merged_name"
        case survivorId = "survivor_id"
        case survivorName = "survivor_name"
        case mergedAt = "merged_at"
    }
}

/// The `{success, merges}` answer of `get_my_community_merges`.
struct CommunityMergeList: Decodable, Sendable {
    let merges: [CommunityMerge]
}
