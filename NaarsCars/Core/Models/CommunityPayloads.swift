//
//  CommunityPayloads.swift
//  NaarsCars
//
//  Payloads, the refusal envelope and the typed errors of the community RPCs
//  (supabase/migrations/20261017_0005_communities_rpcs.sql)
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

    init(
        code: CommunityRefusalCode?,
        serverMessage: String = "",
        maxOwned: Int? = nil,
        ownedCount: Int? = nil,
        retryAfter: Date? = nil
    ) {
        self.code = code
        self.serverMessage = serverMessage
        self.maxOwned = maxOwned
        self.ownedCount = ownedCount
        self.retryAfter = retryAfter
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

        enum CodingKeys: String, CodingKey {
            case success, error, code
            case maxOwned = "max_owned"
            case ownedCount = "owned_count"
            case retryAfter = "retry_after"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            success = try? c.decodeIfPresent(Bool.self, forKey: .success)
            error = try? c.decodeIfPresent(String.self, forKey: .error)
            code = try? c.decodeIfPresent(String.self, forKey: .code)
            maxOwned = try? c.decodeIfPresent(Int.self, forKey: .maxOwned)
            ownedCount = try? c.decodeIfPresent(Int.self, forKey: .ownedCount)
            retryAfter = try? c.decodeIfPresent(Date.self, forKey: .retryAfter)
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
            retryAfter: envelope.retryAfter
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
