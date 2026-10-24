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
    /// The answer to `fetchCommunityPreview`; nil previews the "not listed" refusal.
    var preview: CommunityPreview?
    /// Previews the preview-load-failure state.
    var failPreview = false
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
    /// Active members (`fetchCommunityMembers` with `.active`).
    var activeMembers: [CommunityMember] = PreviewCommunityService.sampleActiveMembers
    /// Removed members (`fetchCommunityMembers` with `.removed`).
    var removedMembers: [CommunityMember] = PreviewCommunityService.sampleRemovedMembers
    var settings: CommunitySettings = PreviewCommunityService.sampleSettings
    var removal = RemovalResult(reopened: 1, removed: 0, cancelled: 0)
    /// When set, approve, reject, archive and the member-management and settings writes throw it
    /// (the not-admin preview).
    var adminRefusal: CommunityRPCError?
    var applicantContact = ApplicantContact(email: "dana.rivera@example.com", phoneNumber: "+1 206 555 0142")
    /// The answer to the three discovery searches.
    var searchResults: [CommunitySearchResult] = PreviewCommunityService.sampleSearchResults
    /// The answer to `checkCommunityArea` (overlapping communities); empty previews "no overlap".
    var overlappingCommunities: [CommunitySearchResult] = []
    var serviceArea: ServiceArea? = PreviewCommunityService.sampleArea
    /// The answer to `searchMergeTargets`.
    var mergeTargets: [MergeTarget] = PreviewCommunityService.sampleMergeTargets
    /// The answer to `fetchMergeProposal`; nil previews "no open proposal".
    var mergeProposal: CommunityMergeProposal?
    /// The answer to `fetchMyCommunityMerges`.
    var myCommunityMerges: [CommunityMerge] = []

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

    static let sampleArea = ServiceArea(
        name: "Ballard", center: GeoPoint(latitude: 47.6687, longitude: -122.3847), radiusMiles: 2
    )

    static let sampleSearchResults: [CommunitySearchResult] = [
        CommunitySearchResult(
            id: UUID(), name: "Ballard Neighbors", description: "Rides and favors around Ballard.",
            joinPolicy: CommunityJoinPolicy.approve.rawValue, areaName: "Ballard", radiusMiles: 2,
            memberCount: 214, distanceMiles: 0.4
        ),
        CommunitySearchResult(
            id: UUID(), name: "Fremont Porch Club", description: nil,
            joinPolicy: CommunityJoinPolicy.invite.rawValue, areaName: "Fremont", radiusMiles: 5,
            memberCount: 38, distanceMiles: 1.8
        ),
        CommunitySearchResult(
            id: UUID(), name: "Test Community", description: "Example requests to look around.",
            joinPolicy: CommunityJoinPolicy.approve.rawValue, areaName: "Seattle", radiusMiles: 10,
            memberCount: 3, distanceMiles: nil
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

    func createCommunity(_ draft: NewCommunityDraft) async throws -> CreatedCommunity {
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

    func fetchCommunityPreview(communityId: UUID) async throws -> CommunityPreview {
        if failPreview { throw URLError(.notConnectedToInternet) }
        guard let preview else { throw CommunityRPCError(code: .notListed) }
        return preview
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

    func searchCommunities(name: String) async throws -> [CommunitySearchResult] {
        searchResults.filter { $0.name.localizedCaseInsensitiveContains(name) }
    }

    func findCommunitiesNear(_ point: GeoPoint) async throws -> [CommunitySearchResult] {
        searchResults.filter { $0.distanceMiles != nil }
    }

    func checkCommunityArea(_ area: ServiceArea, excluding communityId: UUID?) async throws -> [CommunitySearchResult] {
        overlappingCommunities.filter { $0.id != communityId }
    }

    func fetchServiceArea(communityId: UUID) async throws -> ServiceArea? { serviceArea }
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

    static let sampleActiveMembers: [CommunityMember] = [
        CommunityMember(
            id: UUID(), name: "Sam Neighbor", avatarUrl: nil, car: "Blue Civic", role: .owner, status: .active,
            joinedAt: Date(timeIntervalSince1970: 1_789_000_000), activatedAt: Date(timeIntervalSince1970: 1_789_000_100),
            heardAbout: nil, joinReason: nil, invitedByName: nil, removalReason: nil
        ),
        CommunityMember(
            id: UUID(), name: "Pat Quinn", avatarUrl: nil, car: nil, role: .admin, status: .active,
            joinedAt: Date(timeIntervalSince1970: 1_789_100_000), activatedAt: Date(timeIntervalSince1970: 1_789_100_100),
            heardAbout: "Sam told me about it.", joinReason: "Help run the group.", invitedByName: "Sam Neighbor", removalReason: nil
        ),
        CommunityMember(
            id: UUID(), name: "Dana Rivera", avatarUrl: nil, car: "Green Subaru", role: .member, status: .active,
            joinedAt: Date(timeIntervalSince1970: 1_790_100_000), activatedAt: Date(timeIntervalSince1970: 1_790_100_100),
            heardAbout: "A neighbor told me about it at the block party.",
            joinReason: "I drive to the airport often and would like to share rides.",
            invitedByName: "Sam Neighbor", removalReason: nil
        ),
        CommunityMember(
            id: UUID(), name: "Maximiliana Alexandrina Featherstonehaugh-Wolfeschlegelstein",
            avatarUrl: nil, car: nil, role: .member, status: .active,
            joinedAt: Date(timeIntervalSince1970: 1_790_200_000), activatedAt: Date(timeIntervalSince1970: 1_790_200_100),
            heardAbout: nil, joinReason: nil, invitedByName: nil, removalReason: nil
        )
    ]

    static let sampleRemovedMembers: [CommunityMember] = [
        CommunityMember(
            id: UUID(), name: "Jordan Lee", avatarUrl: nil, car: nil, role: .member, status: .removed,
            joinedAt: Date(timeIntervalSince1970: 1_789_500_000), activatedAt: Date(timeIntervalSince1970: 1_789_500_100),
            heardAbout: nil, joinReason: nil, invitedByName: nil,
            removalReason: "Missed three confirmed rides without telling anyone."
        )
    ]

    static let sampleSettings = CommunitySettings(
        id: UUID(), name: "Ballard Neighbors", description: "Ballard rides and favors.",
        joinPolicy: CommunityJoinPolicy.approve.rawValue, membersCanInvite: true,
        isPublic: false, isDefault: false, timezone: "America/Los_Angeles"
    )

    func fetchCommunityMembers(communityId: UUID, status: MembershipStatus, limit: Int, offset: Int) async throws -> [CommunityMember] {
        switch status {
        case .active: return activeMembers
        case .removed: return removedMembers
        case .pending, .left: return members
        }
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

    func removeMember(communityId: UUID, userId: UUID, reason: String?) async throws -> RemovalResult {
        if let adminRefusal { throw adminRefusal }
        return removal
    }

    func readmitMember(communityId: UUID, userId: UUID) async throws {
        if let adminRefusal { throw adminRefusal }
    }

    func setMemberRole(communityId: UUID, userId: UUID, role: CommunityRole) async throws {
        if let adminRefusal { throw adminRefusal }
    }

    func transferOwnership(communityId: UUID, userId: UUID) async throws {
        if let adminRefusal { throw adminRefusal }
    }

    func fetchCommunitySettings(communityId: UUID) async throws -> CommunitySettings {
        if let adminRefusal { throw adminRefusal }
        return settings
    }

    func updateCommunity(communityId: UUID, change: CommunitySettingsChange) async throws {
        if let adminRefusal { throw adminRefusal }
    }

    func updateCommunityAccess(communityId: UUID, change: CommunityAccessChange) async throws {
        if let adminRefusal { throw adminRefusal }
    }
}

// MARK: - Merge

extension PreviewCommunityService: CommunityMergeServiceProtocol {
    static let sampleMergeTargets: [MergeTarget] = [
        MergeTarget(
            id: UUID(), name: "Fremont Porch Club", joinPolicy: CommunityJoinPolicy.open.rawValue,
            isPublic: true, memberCount: 31, areaName: "Fremont"
        ),
        MergeTarget(
            id: UUID(), name: "Harbor Riders", joinPolicy: CommunityJoinPolicy.invite.rawValue,
            isPublic: false, memberCount: 14, areaName: nil
        )
    ]

    func searchMergeTargets(communityId: UUID, query: String) async throws -> [MergeTarget] { mergeTargets }

    func proposeMerge(communityId: UUID, otherId: UUID, survivorId: UUID, note: String?) async throws -> UUID {
        if let adminRefusal { throw adminRefusal }
        return UUID()
    }

    func fetchMergeProposal(communityId: UUID) async throws -> CommunityMergeProposal? { mergeProposal }

    func respondToMerge(proposalId: UUID, accept: Bool) async throws -> CommunityMergeOutcome? {
        if let adminRefusal { throw adminRefusal }
        guard accept, let proposal = mergeProposal else { return nil }
        return CommunityMergeOutcome(survivorId: proposal.survivorId, mergedId: proposal.merged.id)
    }

    func withdrawMerge(proposalId: UUID) async throws {
        if let adminRefusal { throw adminRefusal }
    }

    func fetchMyCommunityMerges() async throws -> [CommunityMerge] { myCommunityMerges }
}

// MARK: - Applicant contact

extension PreviewCommunityService: ApplicantContactFetching {
    func fetchApplicantContact(userId: UUID) async throws -> ApplicantContact { applicantContact }
}
#endif
