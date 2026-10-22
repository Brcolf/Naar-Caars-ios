//
//  CommunityPayloads.swift
//  NaarsCars
//
//  Payloads, the refusal envelope and the typed errors of the community RPCs
//  (supabase/migrations/20261017_0005_communities_rpcs.sql; the discovery and merge codes from
//  20261021_0021_discovery_rpcs.sql and 20261021_0022_community_merge.sql)
//

import Foundation

// MARK: - Refusals

/// The refusal codes the community RPCs return as `{success:false, error, code}`.
enum CommunityRefusalCode: String, CaseIterable, Sendable {
    case restricted
    case dailyLimit = "daily_limit"
    case ownedLimit = "owned_limit"
    case underLimit = "under_limit"
    case requestOpen = "request_open"
    case tooManyCodes = "too_many_codes"
    case rateLimited = "rate_limited"
    case invalid
    case expired
    case exhausted
    case removed
    case alreadyMember = "already_member"
    case alreadyPending = "already_pending"
    case full
    case recentlyRejected = "recently_rejected"
    case notPending = "not_pending"
    case notActive = "not_active"
    case lastOwner = "last_owner"
    case notMember = "not_member"
    case notRemoved = "not_removed"
    case notListed = "not_listed"
    // Release 2: access, listing rules and merging (20261021_0021, 20261021_0022)
    case notOwner = "not_owner"
    case needsArea = "needs_area"
    case invalidArea = "invalid_area"
    case reasonRequired = "reason_required"
    case defaultStaysListed = "default_stays_listed"
    case mergePending = "merge_pending"
    /// A merge declined within 7 days or withdrawn within 24 hours.
    case recentlyDeclined = "recently_declined"
    case proposalClosed = "proposal_closed"
    case defaultCommunity = "default_community"
    /// `get_community_preview` of a community merged into another; carries `mergedIntoId` / `mergedIntoName`.
    case merged
}

/// A refusal from a community RPC. The server's English text is kept for logs and never shown;
/// the person sees `localizedMessage`.
struct CommunityRPCError: Error, Equatable, Sendable {
    /// nil when the server sent no code or one this build does not know.
    let code: CommunityRefusalCode?
    let serverMessage: String
    /// `owned_limit` only.
    let maxOwned: Int?
    let ownedCount: Int?
    /// `recently_rejected` only.
    let retryAfter: Date?
    /// `merged` only: the community it is now part of, when the caller may discover it.
    let mergedIntoId: UUID?
    let mergedIntoName: String?

    init(
        code: CommunityRefusalCode?,
        serverMessage: String = "",
        maxOwned: Int? = nil,
        ownedCount: Int? = nil,
        retryAfter: Date? = nil,
        mergedIntoId: UUID? = nil,
        mergedIntoName: String? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.maxOwned = maxOwned
        self.ownedCount = ownedCount
        self.retryAfter = retryAfter
        self.mergedIntoId = mergedIntoId
        self.mergedIntoName = mergedIntoName
    }

    var localizedMessage: String {
        guard let code else { return "community_error_generic".localized }
        let text = "community_error_\(code.rawValue)".localized
        switch code {
        case .ownedLimit:
            return String(format: text, ownedCount ?? maxOwned ?? 0)
        case .recentlyRejected:
            guard let retryAfter else { return "community_error_generic".localized }
            return String(format: text, retryAfter.formatted(date: .abbreviated, time: .omitted))
        default:
            return text
        }
    }
}

/// Errors of the community service that are not server refusals.
enum CommunityServiceError: Error {
    /// A membership update matched no row (a PATCH that matches nothing still answers 200).
    case membershipNotUpdated
    /// `fetchCommunitySettings` found no row: the community is archived, or the caller may not read it.
    case communityNotFound
}

/// Reads the `{success, ...}` envelope of the community RPCs.
enum CommunityRPC {
    private struct Envelope: Decodable {
        let success: Bool?
        let error: String?
        let code: String?
        let maxOwned: Int?
        let ownedCount: Int?
        let retryAfter: Date?
        let mergedIntoId: UUID?
        let mergedIntoName: String?

        enum CodingKeys: String, CodingKey {
            case success, error, code
            case maxOwned = "max_owned"
            case ownedCount = "owned_count"
            case retryAfter = "retry_after"
            case mergedIntoId = "merged_into_id"
            case mergedIntoName = "merged_into_name"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            success = try? c.decodeIfPresent(Bool.self, forKey: .success)
            error = try? c.decodeIfPresent(String.self, forKey: .error)
            code = try? c.decodeIfPresent(String.self, forKey: .code)
            maxOwned = try? c.decodeIfPresent(Int.self, forKey: .maxOwned)
            ownedCount = try? c.decodeIfPresent(Int.self, forKey: .ownedCount)
            retryAfter = try? c.decodeIfPresent(Date.self, forKey: .retryAfter)
            mergedIntoId = try? c.decodeIfPresent(UUID.self, forKey: .mergedIntoId)
            mergedIntoName = try? c.decodeIfPresent(String.self, forKey: .mergedIntoName)
        }
    }

    /// Decodes a successful payload. `success` is read first: `false` throws a `CommunityRPCError`.
    /// A `code` key in a successful payload (the invite code) is data, not a refusal.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try throwIfRefused(data)
        return try DateDecoderFactory.makeSupabaseDecoder().decode(T.self, from: data)
    }

    /// Same check for an RPC whose payload is not needed.
    static func decodeSuccess(from data: Data) throws {
        try throwIfRefused(data)
    }

    private static func throwIfRefused(_ data: Data) throws {
        guard let envelope = try? DateDecoderFactory.makeSupabaseDecoder().decode(Envelope.self, from: data),
              envelope.success == false else { return }
        AppLogger.warning("community", "RPC refused: \(envelope.code ?? "no code") \(envelope.error ?? "")")
        throw CommunityRPCError(
            code: envelope.code.flatMap(CommunityRefusalCode.init(rawValue:)),
            serverMessage: envelope.error ?? "",
            maxOwned: envelope.maxOwned,
            ownedCount: envelope.ownedCount,
            retryAfter: envelope.retryAfter,
            mergedIntoId: envelope.mergedIntoId,
            mergedIntoName: envelope.mergedIntoName
        )
    }
}

// MARK: - Invite codes

enum CommunityInviteCode {
    /// Uppercases and drops every character that is not A-Z or 0-9, the server's rule
    /// (a code shown as "NC7X · 9K2A · BQ" or typed in lower case is accepted).
    static func normalize(_ raw: String) -> String {
        String(raw.uppercased().unicodeScalars.filter { scalar in
            (scalar.value >= 0x41 && scalar.value <= 0x5A) || (scalar.value >= 0x30 && scalar.value <= 0x39)
        }.map(Character.init))
    }

    /// `NC` plus eight characters from the code alphabet (no I, L, O, 0, 1).
    static func isWellFormed(_ normalized: String) -> Bool {
        normalized.range(of: "^NC[A-HJKMNP-Z2-9]{8}$", options: .regularExpression) != nil
    }
}

enum CommunityJoinPolicy: String, Sendable {
    case invite
    case approve
    case open

    /// The text of the policy chip.
    var chipText: String {
        switch self {
        case .open: return "community_policy_open".localized
        case .approve: return "community_policy_ask_to_join".localized
        case .invite: return "community_policy_invite_only".localized
        }
    }

    var systemImage: String {
        switch self {
        case .open: return "globe"
        case .approve: return "lock.fill"
        case .invite: return "key.fill"
        }
    }

    /// The subtitle under a community name in a list row.
    var subtitleText: String {
        switch self {
        case .open: return "community_policy_subtitle_open".localized
        case .approve: return "community_policy_ask_to_join".localized
        case .invite: return "community_policy_invite_only".localized
        }
    }

    /// One plain sentence on what joining this community means.
    var ruleSentence: String {
        switch self {
        case .open: return "community_rule_open".localized
        case .approve: return "community_rule_ask_to_join".localized
        case .invite: return "community_rule_invite_only".localized
        }
    }
}

// MARK: - Payloads

struct CreatedCommunity: Equatable, Sendable {
    let communityId: UUID
}

extension CreatedCommunity: Decodable {
    enum CodingKeys: String, CodingKey { case communityId = "community_id" }
}

enum LimitRequestStatus: String, Sendable {
    case pending, approved, declined
}

extension LimitRequestStatus: Decodable {
    /// Tolerant: an unknown value decodes as `.pending`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LimitRequestStatus(rawValue: raw) ?? .pending
    }
}

struct CommunityLimitRequest: Equatable, Sendable {
    let requestId: UUID
    let requestedMax: Int
    let reason: String
    let status: LimitRequestStatus
    let createdAt: Date
    let decidedAt: Date?
}

extension CommunityLimitRequest: Decodable {
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case requestedMax = "requested_max"
        case reason
        case status
        case createdAt = "created_at"
        case decidedAt = "decided_at"
    }
}

struct CommunityLimits: Equatable, Sendable {
    let maxOwned: Int
    let ownedCount: Int
    let nextCreateAt: Date?
    let canCreate: Bool
    let latestRequest: CommunityLimitRequest?
}

extension CommunityLimits: Decodable {
    enum CodingKeys: String, CodingKey {
        case maxOwned = "max_owned"
        case ownedCount = "owned_count"
        case nextCreateAt = "next_create_at"
        case canCreate = "can_create"
        case latestRequest = "latest_request"
    }
}

struct LimitRequestReceipt: Equatable, Sendable {
    let requestId: UUID
}

extension LimitRequestReceipt: Decodable {
    enum CodingKeys: String, CodingKey { case requestId = "request_id" }
}

/// A code just made by `create_community_invite`.
struct CommunityInvite: Equatable, Sendable {
    let code: String
    let inviteId: UUID
    let maxUses: Int
    let expiresAt: Date
}

extension CommunityInvite: Decodable {
    enum CodingKeys: String, CodingKey {
        case code
        case inviteId = "invite_id"
        case maxUses = "max_uses"
        case expiresAt = "expires_at"
    }
}

/// One row of `community_invites` the caller created.
struct CommunityInviteRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let code: String
    let maxUses: Int?
    let useCount: Int
    let expiresAt: Date?
    let revokedAt: Date?
    let createdAt: Date

    /// Not revoked, not expired, not used up.
    func isLive(at now: Date) -> Bool {
        if revokedAt != nil { return false }
        if let expiresAt, expiresAt <= now { return false }
        if let maxUses, useCount >= maxUses { return false }
        return true
    }
}

extension CommunityInviteRow: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, code
        case maxUses = "max_uses"
        case useCount = "use_count"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
        case createdAt = "created_at"
    }
}

/// What `validate_community_invite` says about a typed code.
struct InvitePreview: Equatable, Sendable {
    let valid: Bool
    let expired: Bool
    let requiresApproval: Bool?
    let communityName: String?
    let alreadyMember: Bool?
    /// Present for public communities only.
    let memberCount: Int?
}

extension InvitePreview: Decodable {
    enum CodingKeys: String, CodingKey {
        case valid, expired
        case requiresApproval = "requires_approval"
        case communityName = "community_name"
        case alreadyMember = "already_member"
        case memberCount = "member_count"
    }
}

/// The result of redeeming a code or asking to join.
struct JoinResult: Equatable, Sendable {
    let communityId: UUID
    let status: MembershipStatus
}

extension JoinResult: Decodable {
    enum CodingKeys: String, CodingKey {
        case communityId = "community_id"
        case status
    }
}

struct LeaveResult: Equatable, Sendable {
    let reopened: Int
    let removed: Int
    let cancelled: Int
    let archived: Bool
}

extension LeaveResult: Decodable {}

struct CommunityReportResult: Equatable, Sendable {
    let reportId: UUID?
    let duplicate: Bool
}

extension CommunityReportResult: Decodable {
    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case duplicate
    }

    /// Tolerant: `duplicate` is absent unless the report already existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reportId = try c.decodeIfPresent(UUID.self, forKey: .reportId)
        duplicate = try c.decodeIfPresent(Bool.self, forKey: .duplicate) ?? false
    }
}

/// A public community, as listed by `fetchPublicCommunities`.
struct PublicCommunity: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let description: String?
    let joinPolicy: String
    let isDefault: Bool
}

extension PublicCommunity: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case joinPolicy = "join_policy"
        case isDefault = "is_default"
    }
}

/// What a visitor sees of a listed community (`get_community_preview`): the community, its open
/// requests and its latest Town Hall posts. Addresses, notes and the community's description of
/// a request never travel in it; the server decides, this type only decodes.
struct CommunityPreview: Decodable, Equatable, Sendable {
    let community: Community
    let requests: [Request]
    let posts: [Post]

    struct Community: Decodable, Equatable, Sendable {
        let id: UUID
        let name: String
        let description: String?
        let joinPolicy: String
        let isPublic: Bool
        let isDefault: Bool
        let memberCount: Int
        let timezone: String
        /// nil for a community without a service area, or from a server before Release 2.
        var area: ServiceArea? = nil

        enum CodingKeys: String, CodingKey {
            case id, name, description, timezone
            case joinPolicy = "join_policy"
            case isPublic = "is_public"
            case isDefault = "is_default"
            case memberCount = "member_count"
        }
    }

    struct Request: Decodable, Equatable, Sendable, Identifiable {
        /// "ride" or "favor".
        let type: String
        let id: UUID
        let title: String?
        let date: Date
        let time: String?
        let timezone: String?
        let seats: Int?
        let posterId: UUID
        let posterName: String
        let posterAvatarUrl: String?
        /// Example content of the example community; false when the key is absent (before Release 2).
        var isExample: Bool = false

        var isRide: Bool { type == "ride" }

        enum CodingKeys: String, CodingKey {
            case type, id, title, date, time, timezone, seats
            case posterId = "poster_id"
            case posterName = "poster_name"
            case posterAvatarUrl = "poster_avatar_url"
            case isExample = "is_example"
        }
    }

    struct Post: Decodable, Equatable, Sendable, Identifiable {
        let id: UUID
        let type: String?
        let title: String?
        let content: String
        let createdAt: Date
        let authorId: UUID
        let authorName: String
        let authorAvatarUrl: String?
        let commentCount: Int

        enum CodingKeys: String, CodingKey {
            case id, type, title, content
            case createdAt = "created_at"
            case authorId = "author_id"
            case authorName = "author_name"
            case authorAvatarUrl = "author_avatar_url"
            case commentCount = "comment_count"
        }
    }
}

extension CommunityPreview.Community {
    /// The area keys may be absent (a server before Release 2); the memberwise initializer stays.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        joinPolicy = try c.decode(String.self, forKey: .joinPolicy)
        isPublic = try c.decode(Bool.self, forKey: .isPublic)
        isDefault = try c.decode(Bool.self, forKey: .isDefault)
        memberCount = try c.decode(Int.self, forKey: .memberCount)
        timezone = try c.decode(String.self, forKey: .timezone)
        area = try ServiceArea.decodeColumns(from: decoder)
    }
}

extension CommunityPreview.Request {
    /// `is_example` may be absent (a server before Release 2); the memberwise initializer stays.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        date = try c.decode(Date.self, forKey: .date)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        seats = try c.decodeIfPresent(Int.self, forKey: .seats)
        posterId = try c.decode(UUID.self, forKey: .posterId)
        posterName = try c.decode(String.self, forKey: .posterName)
        posterAvatarUrl = try c.decodeIfPresent(String.self, forKey: .posterAvatarUrl)
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
    }
}

// MARK: - Admin payloads

/// One row of `get_community_members`. The answers, inviter and removal reason are null unless the
/// caller is an admin of the community.
struct CommunityMember: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let avatarUrl: String?
    let car: String?
    let role: CommunityRole
    let status: MembershipStatus
    let joinedAt: Date
    let activatedAt: Date?
    let heardAbout: String?
    let joinReason: String?
    let invitedByName: String?
    let removalReason: String?
}

extension CommunityMember: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, car, role, status
        case avatarUrl = "avatar_url"
        case joinedAt = "joined_at"
        case activatedAt = "activated_at"
        case heardAbout = "heard_about"
        case joinReason = "join_reason"
        case invitedByName = "invited_by_name"
        case removalReason = "removal_reason"
    }

    /// Tolerant: one blank profile name must not fail the whole list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        car = try c.decodeIfPresent(String.self, forKey: .car)
        role = try c.decode(CommunityRole.self, forKey: .role)
        status = try c.decode(MembershipStatus.self, forKey: .status)
        joinedAt = try c.decode(Date.self, forKey: .joinedAt)
        activatedAt = try c.decodeIfPresent(Date.self, forKey: .activatedAt)
        heardAbout = try c.decodeIfPresent(String.self, forKey: .heardAbout)
        joinReason = try c.decodeIfPresent(String.self, forKey: .joinReason)
        invitedByName = try c.decodeIfPresent(String.self, forKey: .invitedByName)
        removalReason = try c.decodeIfPresent(String.self, forKey: .removalReason)
    }
}

extension CommunityMember: Hashable {}

extension CommunityMember {
    /// The same row with another role (after `set_member_role` succeeded).
    func replacingRole(_ role: CommunityRole) -> CommunityMember {
        CommunityMember(
            id: id, name: name, avatarUrl: avatarUrl, car: car, role: role, status: status,
            joinedAt: joinedAt, activatedAt: activatedAt, heardAbout: heardAbout, joinReason: joinReason,
            invitedByName: invitedByName, removalReason: removalReason
        )
    }
}

/// `get_platform_communities` (platform admins only).
struct PlatformCommunities: Equatable, Sendable {
    let communities: [PlatformCommunity]
    let limitRequests: [PlatformLimitRequest]
}

extension PlatformCommunities: Decodable {
    enum CodingKeys: String, CodingKey {
        case communities
        case limitRequests = "limit_requests"
    }
}

struct PlatformCommunity: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let description: String?
    let createdBy: UUID?
    let creatorName: String?
    let createdAt: Date
    let isPublic: Bool
    let isDefault: Bool
    let joinPolicy: String
    let archivedAt: Date?
    let archivedBy: UUID?
    let memberCount: Int
    let pendingCount: Int
    let ownerCount: Int
    let openReportCount: Int
}

extension PlatformCommunity: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case createdBy = "created_by"
        case creatorName = "creator_name"
        case createdAt = "created_at"
        case isPublic = "is_public"
        case isDefault = "is_default"
        case joinPolicy = "join_policy"
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
        case memberCount = "member_count"
        case pendingCount = "pending_count"
        case ownerCount = "owner_count"
        case openReportCount = "open_report_count"
    }
}

struct PlatformLimitRequest: Identifiable, Equatable, Sendable {
    let requestId: UUID
    let userId: UUID
    let userName: String?
    let requestedMax: Int
    let reason: String
    let createdAt: Date
    let currentMax: Int
    let ownedCount: Int

    var id: UUID { requestId }
}

extension PlatformLimitRequest: Decodable {
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case userId = "user_id"
        case userName = "user_name"
        case requestedMax = "requested_max"
        case reason
        case createdAt = "created_at"
        case currentMax = "current_max"
        case ownedCount = "owned_count"
    }
}

/// What `remove_community_member` did to the removed member's requests in that community
/// (20261017_0005 block 22): reopened claims, deleted unclaimed requests, cancelled claimed ones.
struct RemovalResult: Decodable, Equatable, Sendable {
    let reopened: Int
    let removed: Int
    let cancelled: Int
}

/// One community's editable settings, read from `communities` (readable only while not archived).
struct CommunitySettings: Decodable, Equatable, Sendable {
    let id: UUID
    let name: String
    let description: String?
    let joinPolicy: String
    let membersCanInvite: Bool
    let isPublic: Bool
    let isDefault: Bool
    let timezone: String
    /// The stored service area; nil when the community has none.
    var area: ServiceArea? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, description, timezone
        case joinPolicy = "join_policy"
        case membersCanInvite = "members_can_invite"
        case isPublic = "is_public"
        case isDefault = "is_default"
    }
}

extension CommunitySettings {
    /// The four area columns are read beside the settings; the memberwise initializer stays.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        joinPolicy = try c.decode(String.self, forKey: .joinPolicy)
        membersCanInvite = try c.decode(Bool.self, forKey: .membersCanInvite)
        isPublic = try c.decode(Bool.self, forKey: .isPublic)
        isDefault = try c.decode(Bool.self, forKey: .isDefault)
        timezone = try c.decode(String.self, forKey: .timezone)
        area = try ServiceArea.decodeColumns(from: decoder)
    }
}

/// A change to `update_community`. nil leaves a field unchanged; `description: ""` clears it
/// (update_community, 20261017_0005 block 11). `timezone` is an IANA identifier, set only when the
/// owner picked a different zone in Settings (the server refuses one it does not know).
struct CommunitySettingsChange: Equatable, Sendable {
    var name: String? = nil
    var description: String? = nil
    var joinPolicy: CommunityJoinPolicy? = nil
    var membersCanInvite: Bool? = nil
    var timezone: String? = nil

    var isEmpty: Bool {
        name == nil && description == nil && joinPolicy == nil && membersCanInvite == nil && timezone == nil
    }
}

/// The outcome of `decide_owned_community_limit`.
struct LimitDecision: Equatable, Sendable {
    let status: LimitRequestStatus
    let maxOwned: Int
}

extension LimitDecision: Decodable {
    enum CodingKeys: String, CodingKey {
        case status
        case maxOwned = "max_owned"
    }
}
