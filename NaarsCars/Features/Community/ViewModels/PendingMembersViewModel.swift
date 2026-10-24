//
//  PendingMembersViewModel.swift
//  NaarsCars
//
//  Lists one community's requests to join and approves or declines them
//

internal import Combine
import Foundation

/// Which community's requests to join the screen shows.
enum PendingMembersTarget: Hashable {
    case community(UUID, name: String?)
    /// The platform admins' Pending approvals row: the default community.
    case defaultCommunity
}

@MainActor
final class PendingMembersViewModel: ObservableObject {
    enum Access: Equatable { case checking, allowed, notAdmin }

    @Published private(set) var access: Access = .checking
    @Published private(set) var communityId: UUID?
    @Published private(set) var communityName: String?
    @Published private(set) var applicants: [CommunityMember] = []
    @Published private(set) var isLoading = false
    /// Shown full screen only while `applicants` is empty.
    @Published var loadError: String?
    /// Shown in the error banner.
    @Published var actionErrorMessage: String?
    @Published private(set) var actingOnUserId: UUID?
    @Published private(set) var contacts: [UUID: ApplicantContact] = [:]

    let target: PendingMembersTarget

    private let adminService: any CommunityAdminServiceProtocol
    private let communityContext: CommunityContext
    private let contactFetcher: any ApplicantContactFetching
    private let refreshBadges: @MainActor () async -> Void

    init(
        target: PendingMembersTarget,
        adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
        communityContext: CommunityContext? = nil,
        contactFetcher: any ApplicantContactFetching = AdminService.shared,
        refreshBadges: @escaping @MainActor () async -> Void = {
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "communityMemberDecision")
        }
    ) {
        self.target = target
        self.adminService = adminService
        self.communityContext = communityContext ?? .shared
        self.contactFetcher = contactFetcher
        self.refreshBadges = refreshBadges
    }

    /// True for a platform admin, who also sees an applicant's email and phone on the detail.
    var showsContact: Bool { communityContext.isPlatformAdmin }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        loadError = nil

        // Memberships first: both the default-community lookup and the admin check read them.
        if communityContext.isAwaitingMemberships {
            await communityContext.refreshMemberships()
        }

        if communityId == nil {
            switch target {
            case .community(let id, _):
                communityId = id
            case .defaultCommunity:
                if let id = communityContext.memberships.first(where: \.isDefault)?.communityId {
                    communityId = id
                } else {
                    do {
                        communityId = try await adminService.fetchDefaultCommunityId()
                    } catch {
                        AppLogger.error("community", "fetchDefaultCommunityId failed: \(error)")
                    }
                }
            }
        }
        guard let communityId else {
            loadError = "community_error_generic".localized
            return
        }

        if case .community(_, let name?) = target {
            communityName = name
        } else {
            communityName = communityContext.name(for: communityId)
        }

        // `get_community_members` answers [] to a non-admin, which would read as "no requests".
        guard communityContext.isAdmin(of: communityId) else {
            access = .notAdmin
            applicants = []
            return
        }
        access = .allowed

        do {
            applicants = try await adminService.fetchCommunityMembers(
                communityId: communityId,
                status: .pending,
                limit: Constants.Community.pendingMembersPageSize,
                offset: 0
            )
        } catch let refusal as CommunityRPCError {
            loadError = refusal.localizedMessage
        } catch {
            AppLogger.error("community", "fetchCommunityMembers failed: \(error)")
            loadError = "community_error_generic".localized
        }
    }

    // MARK: - Decisions

    func approve(_ member: CommunityMember) async {
        await decide(member, approve: true)
    }

    func reject(_ member: CommunityMember) async {
        await decide(member, approve: false)
    }

    /// One decision at a time. A success removes the row before the follow-up refreshes, so a
    /// refresh that fails cannot bring the applicant back or show an error for a decision that worked.
    private func decide(_ member: CommunityMember, approve: Bool) async {
        guard actingOnUserId == nil, let communityId else { return }
        actingOnUserId = member.id
        defer { actingOnUserId = nil }
        actionErrorMessage = nil

        do {
            if approve {
                try await adminService.approveMember(communityId: communityId, userId: member.id)
            } else {
                try await adminService.rejectMember(communityId: communityId, userId: member.id)
            }
        } catch let refusal as CommunityRPCError {
            switch refusal.code {
            case nil:
                // The server's unauthorized answer carries no code.
                access = .notAdmin
            case .notPending?:
                // Already handled (by another admin, or the applicant left).
                applicants.removeAll { $0.id == member.id }
            default:
                actionErrorMessage = refusal.localizedMessage
            }
            return
        } catch {
            AppLogger.error("community", "\(approve ? "approve" : "reject") member failed: \(error)")
            actionErrorMessage = "community_error_generic".localized
            return
        }

        applicants.removeAll { $0.id == member.id }
        HapticManager.success()
        await communityContext.refreshMemberships()
        await refreshBadges()
    }

    // MARK: - Contact

    /// Platform admins only; a failure leaves the contact unknown and the detail shows no contact section.
    func loadContact(for member: CommunityMember) async {
        guard communityContext.isPlatformAdmin, contacts[member.id] == nil else { return }
        do {
            contacts[member.id] = try await contactFetcher.fetchApplicantContact(userId: member.id)
        } catch {
            AppLogger.warning("community", "fetchApplicantContact failed: \(error)")
        }
    }
}
