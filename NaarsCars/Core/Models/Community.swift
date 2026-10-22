//
//  Community.swift
//  NaarsCars
//
//  Community membership models decoded from the get_my_memberships RPC
//

import Foundation

/// Role of the signed-in user in a community.
/// Tolerant: an unknown raw string decodes as `.member` (least privilege).
enum CommunityRole: String, Decodable, Sendable {
    case owner, admin, member

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CommunityRole(rawValue: raw) ?? .member
    }
}

/// Status of a membership.
/// Tolerant: an unknown raw string decodes as `.pending` (never counted as active).
enum MembershipStatus: String, Decodable, Sendable {
    case pending, active, left, removed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MembershipStatus(rawValue: raw) ?? .pending
    }
}

/// One row of `get_my_memberships`.
struct CommunityMembership: Decodable, Identifiable, Equatable, Sendable {
    let communityId: UUID
    let name: String
    let description: String?
    let role: CommunityRole
    let status: MembershipStatus
    let isPrimary: Bool
    let joinPolicy: String
    let isPublic: Bool
    let isDefault: Bool
    let membersCanInvite: Bool
    let timezone: String
    let canInvite: Bool
    let memberCount: Int
    let pendingCount: Int?
    let notificationsMuted: Bool
    let mutedUntil: Date?
    let joinedAt: Date
    let activatedAt: Date?

    var id: UUID { communityId }

    /// True when joining needs an admin's approval (the server's `approve` join policy).
    var requiresApproval: Bool { joinPolicy == CommunityJoinPolicy.approve.rawValue }

    enum CodingKeys: String, CodingKey {
        case communityId = "community_id"
        case name
        case description
        case role
        case status
        case isPrimary = "is_primary"
        case joinPolicy = "join_policy"
        case isPublic = "is_public"
        case isDefault = "is_default"
        case membersCanInvite = "members_can_invite"
        case timezone
        case canInvite = "can_invite"
        case memberCount = "member_count"
        case pendingCount = "pending_count"
        case notificationsMuted = "notifications_muted"
        case mutedUntil = "muted_until"
        case joinedAt = "joined_at"
        case activatedAt = "activated_at"
    }
}

/// Which community's requests the Requests screen shows.
enum RequestsScope: Equatable, Hashable, Sendable {
    case all
    case community(UUID)
    /// Every community except these (the community chips' include and exclude filter).
    case excluding(Set<UUID>)

    private static let excludingStoragePrefix = "exclude:"

    /// The one community a narrow shows; nil for `.all` and `.excluding`.
    var communityId: UUID? {
        switch self {
        case .all, .excluding: return nil
        case .community(let id): return id
        }
    }

    /// `.all` includes everything; a community scope includes its rows and rows with unknown (nil) community;
    /// `.excluding` includes every row whose community is not in its set, rows with unknown community included.
    func includes(_ communityId: UUID?) -> Bool {
        switch self {
        case .all: return true
        case .community(let id): return communityId == id || communityId == nil
        case .excluding(let ids):
            guard let communityId else { return true }
            return !ids.contains(communityId)
        }
    }

    var storageValue: String {
        switch self {
        case .all: return "all"
        case .community(let id): return id.uuidString
        case .excluding(let ids):
            return Self.excludingStoragePrefix + ids.map(\.uuidString).sorted().joined(separator: ",")
        }
    }

    /// Reads `storageValue`. Invalid ids in an exclude list are dropped; an exclude list with no valid id,
    /// and anything unreadable, is `.all`.
    init(storageValue: String?) {
        guard let storageValue else {
            self = .all
            return
        }
        if storageValue.hasPrefix(Self.excludingStoragePrefix) {
            let ids = Set(storageValue.dropFirst(Self.excludingStoragePrefix.count)
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) })
            self = ids.isEmpty ? .all : .excluding(ids)
        } else if let id = UUID(uuidString: storageValue) {
            self = .community(id)
        } else {
            self = .all
        }
    }
}
