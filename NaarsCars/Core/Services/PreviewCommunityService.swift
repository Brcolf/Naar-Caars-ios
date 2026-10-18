//
//  PreviewCommunityService.swift
//  NaarsCars
//
//  Canned, offline answers for #Preview only
//

#if DEBUG
import Foundation

/// Canned, offline answers for #Preview only. Never used outside DEBUG previews; no network, no delay.
final class PreviewCommunityService: CommunityServiceProtocol {
    var memberships: [CommunityMembership] = PreviewCommunityService.sampleMemberships
    var publicCommunities: [PublicCommunity] = PreviewCommunityService.samplePublicCommunities
    /// Previews the load-failure state.
    var failPublicCommunities = false
    var limits = CommunityLimits(maxOwned: 3, ownedCount: 1, nextCreateAt: nil, canCreate: true, latestRequest: nil)
    var invite = CommunityInvite(code: "NC7K2PQ9XA", inviteId: UUID(), maxUses: 1, expiresAt: Date().addingTimeInterval(7 * 86_400))
    var liveInvites: [CommunityInviteRow] = PreviewCommunityService.sampleLiveInvites
    var invitePreview = InvitePreview(
        valid: true,
        expired: false,
        requiresApproval: true,
        communityName: "Ballard Neighbors",
        alreadyMember: false,
        memberCount: 12
    )
    var joinStatus: MembershipStatus = .pending
    var members: [CommunityMember] = PreviewCommunityService.sampleApplicants
    var platformCommunities: PlatformCommunities = PreviewCommunityService.samplePlatformCommunities
    /// When set, approve, reject and archive throw it (the not-admin preview).
    var adminRefusal: CommunityRPCError?

    init() {}

    // MARK: - Samples

    static func membership(
        name: String,
        role: CommunityRole = .member,
        status: MembershipStatus = .active,
        memberCount: Int = 12,
        pendingCount: Int? = nil,
        isDefault: Bool = false
    ) -> CommunityMembership {
        CommunityMembership(
            communityId: UUID(),
            name: name,
            description: nil,
            role: role,
            status: status,
            isPrimary: isDefault,
            joinPolicy: CommunityJoinPolicy.approve.rawValue,
            isPublic: false,
            isDefault: isDefault,
            membersCanInvite: true,
            timezone: "America/Los_Angeles",
            canInvite: true,
            memberCount: memberCount,
            pendingCount: pendingCount,
            notificationsMuted: false,
            mutedUntil: nil,
            joinedAt: Date(timeIntervalSince1970: 1_790_000_000),
            activatedAt: status == .active ? Date(timeIntervalSince1970: 1_790_000_100) : nil
        )
    }

    static let sampleMemberships: [CommunityMembership] = [
        membership(name: "Naar's Cars Seattle", role: .member, memberCount: 140, isDefault: true),
        membership(name: "Ballard Neighbors", role: .owner, memberCount: 12, pendingCount: 2),
        membership(name: "Fremont Families", role: .member, status: .pending, memberCount: 8)
    ]

    static let samplePublicCommunities: [PublicCommunity] = [
        PublicCommunity(
            id: UUID(),
            name: "Capitol Hill Carpool",
            description: "Neighbors sharing rides on the hill.",
            joinPolicy: CommunityJoinPolicy.approve.rawValue,
            isDefault: false
        ),
        PublicCommunity(
            id: UUID(),
            name: "Green Lake Helpers",
            description: nil,
            joinPolicy: CommunityJoinPolicy.invite.rawValue,
            isDefault: false
        )
    ]

    static let sampleLiveInvites: [CommunityInviteRow] = [
        CommunityInviteRow(
            id: UUID(),
            code: "NC7K2PQ9XA",
            maxUses: 1,
            useCount: 0,
            expiresAt: Date().addingTimeInterval(5 * 86_400),
            revokedAt: nil,
            createdAt: Date().addingTimeInterval(-86_400)
        ),
        CommunityInviteRow(
            id: UUID(),
            code: "NCH3M5RT8W",
            maxUses: 25,
            useCount: 4,
            expiresAt: Date().addingTimeInterval(20 * 86_400),
            revokedAt: nil,
            createdAt: Date().addingTimeInterval(-3 * 86_400)
        )
    ]

    // MARK: - CommunityServiceProtocol

    func fetchMyMemberships() async throws -> [CommunityMembership] { memberships }

    func createCommunity(name: String, description: String?, joinPolicy: CommunityJoinPolicy) async throws -> CreatedCommunity {
        CreatedCommunity(communityId: UUID())
    }

    func fetchMyCommunityLimits() async throws -> CommunityLimits { limits }

    func requestOwnedCommunityLimit(requested: Int, reason: String) async throws -> LimitRequestReceipt {
        LimitRequestReceipt(requestId: UUID())
    }

    func createInvite(communityId: UUID, maxUses: Int?, expiresAt: Date?) async throws -> CommunityInvite { invite }

    func fetchLiveInvites(communityId: UUID, createdBy: UUID) async throws -> [CommunityInviteRow] { liveInvites }

    func revokeInvite(inviteId: UUID) async throws {}

    func validateInvite(code: String) async throws -> InvitePreview { invitePreview }

    func redeemInvite(code: String, heardAbout: String?, joinReason: String?) async throws -> JoinResult {
        JoinResult(communityId: UUID(), status: joinStatus)
    }

    func fetchPublicCommunities() async throws -> [PublicCommunity] {
        if failPublicCommunities { throw URLError(.notConnectedToInternet) }
        return publicCommunities
    }

    func requestToJoin(communityId: UUID, heardAbout: String?, joinReason: String?) async throws -> JoinResult {
        JoinResult(communityId: communityId, status: joinStatus)
    }

    func leaveCommunity(communityId: UUID) async throws -> LeaveResult {
        LeaveResult(reopened: 0, removed: 0, cancelled: 0, archived: false)
    }

    func setCommunityMuted(communityId: UUID, muted: Bool) async throws {}

    func reportCommunity(communityId: UUID?, code: String?, type: MessageService.ReportType, description: String?) async throws -> CommunityReportResult {
        CommunityReportResult(reportId: nil, duplicate: false)
    }
}

// MARK: - Admin

extension PreviewCommunityService: CommunityAdminServiceProtocol {
    static let seattleSampleId = UUID(uuidString: "5EA77100-0000-4000-8000-000000000001")!

    static let sampleApplicants: [CommunityMember] = [
        CommunityMember(
            id: UUID(), name: "Dana Rivera", avatarUrl: nil, car: "Green Subaru", role: .member, status: .pending,
            joinedAt: Date(timeIntervalSince1970: 1_790_100_000), activatedAt: nil,
            heardAbout: "A neighbor told me about it at the block party.",
            joinReason: "I drive to the airport often and would like to share rides.",
            invitedByName: "Sam Neighbor", removalReason: nil
        ),
        CommunityMember(
            id: UUID(), name: "Lee Park", avatarUrl: nil, car: nil, role: .member, status: .pending,
            joinedAt: Date(timeIntervalSince1970: 1_790_200_000), activatedAt: nil,
            heardAbout: "Found the community in the app.",
            joinReason: "New to the neighborhood.",
            invitedByName: nil, removalReason: nil
        )
    ]

    static let samplePlatformCommunities = PlatformCommunities(
        communities: [
            PlatformCommunity(
                id: seattleSampleId, name: "Naar's Cars Seattle", description: nil, createdBy: nil, creatorName: nil,
                createdAt: Date(timeIntervalSince1970: 1_780_000_000), isPublic: true, isDefault: true,
                joinPolicy: "approve", archivedAt: nil, archivedBy: nil,
                memberCount: 140, pendingCount: 0, ownerCount: 1, openReportCount: 0
            ),
            PlatformCommunity(
                id: UUID(), name: "Ballard Neighbors", description: "Ballard rides and favors.", createdBy: UUID(), creatorName: "Sam Neighbor",
                createdAt: Date(timeIntervalSince1970: 1_789_000_000), isPublic: false, isDefault: false,
                joinPolicy: "approve", archivedAt: nil, archivedBy: nil,
                memberCount: 12, pendingCount: 2, ownerCount: 1, openReportCount: 0
            ),
            PlatformCommunity(
                id: UUID(), name: "Old Carpool", description: nil, createdBy: UUID(), creatorName: "Pat Quinn",
                createdAt: Date(timeIntervalSince1970: 1_785_000_000), isPublic: false, isDefault: false,
                joinPolicy: "invite", archivedAt: Date(timeIntervalSince1970: 1_790_000_000), archivedBy: nil,
                memberCount: 3, pendingCount: 0, ownerCount: 0, openReportCount: 1
            )
        ],
        limitRequests: [
            PlatformLimitRequest(
                requestId: UUID(), userId: UUID(), userName: "Sam Neighbor", requestedMax: 5,
                reason: "I run three neighborhood groups.", createdAt: Date(timeIntervalSince1970: 1_790_300_000),
                currentMax: 3, ownedCount: 3
            )
        ]
    )

    func fetchCommunityMembers(communityId: UUID, status: MembershipStatus, limit: Int, offset: Int) async throws -> [CommunityMember] {
        members
    }

    func approveMember(communityId: UUID, userId: UUID) async throws {
        if let adminRefusal { throw adminRefusal }
    }

    func rejectMember(communityId: UUID, userId: UUID) async throws {
        if let adminRefusal { throw adminRefusal }
    }

    func fetchDefaultCommunityId() async throws -> UUID? { PreviewCommunityService.seattleSampleId }

    func fetchPlatformCommunities() async throws -> PlatformCommunities { platformCommunities }

    func archiveCommunity(communityId: UUID) async throws {
        if let adminRefusal { throw adminRefusal }
    }

    func unarchiveCommunity(communityId: UUID) async throws {}

    func setCommunityPublic(communityId: UUID, isPublic: Bool) async throws {}

    func decideOwnedCommunityLimit(requestId: UUID, approve: Bool) async throws -> LimitDecision {
        LimitDecision(status: approve ? .approved : .declined, maxOwned: 5)
    }
}
#endif
