//
//  CommunityMembersViewModel.swift
//  NaarsCars
//
//  One community's members and removed members, with remove, let back in, roles and ownership
//

internal import Combine
import Foundation

/// An action a community admin can take on one member.
enum CommunityMemberAction: Hashable {
    case remove, readmit, makeAdmin, makeMember, transferOwnership
}

/// Which list the Members screen shows.
enum CommunityMembersList: Hashable, CaseIterable {
    case active, removed
}

/// What the client offers on a member. The server decides every action; this only chooses what to
/// show and never offers what the server refuses.
enum CommunityMemberActions {
    /// Mirrors the server (20261017_0005): remove_community_member :1466-1490, readmit :1536-1546,
    /// set_member_role :1602-1632, transfer_community_ownership :1664-1681. Pure; tested as a table.
    static func available(
        for member: CommunityMember,
        callerId: UUID?,
        callerRole: CommunityRole?,
        isPlatformAdmin: Bool
    ) -> [CommunityMemberAction] {
        if let callerId, member.id == callerId { return [] }
        let isOwner = callerRole == .owner
        let isAdmin = isOwner || callerRole == .admin || isPlatformAdmin
        guard isAdmin else { return [] }

        switch member.status {
        case .pending, .left:
            return []
        case .removed:
            return [.readmit]
        case .active:
            break
        }

        // Role changes: the owner, or a platform admin (set_member_role).
        let canChangeRoles = isOwner || isPlatformAdmin
        var actions: [CommunityMemberAction] = []
        // Only the community's owner hands over ownership; a platform admin who is not the owner cannot.
        if isOwner && member.role != .owner {
            actions.append(.transferOwnership)
        }
        if canChangeRoles && (member.role == .member || member.role == .owner) {
            actions.append(.makeAdmin)
        }
        if canChangeRoles && member.role == .admin {
            actions.append(.makeMember)
        }
        // An admin removes members; only the owner or a platform admin removes an admin or an owner.
        if member.role == .member || canChangeRoles {
            actions.append(.remove)
        }
        return actions
    }
}

extension CommunityMember {
    /// The name shown on the Members screens; a blank profile name reads as "Former member".
    var membersDisplayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "community_former_member".localized : trimmed
    }
}

@MainActor
final class CommunityMembersViewModel: ObservableObject {
    enum Access: Equatable { case checking, allowed, notAdmin }

    @Published private(set) var access: Access = .checking
    /// Changing the list clears the rows; the view then calls `load()`.
    @Published var list: CommunityMembersList = .active {
        didSet {
            guard list != oldValue else { return }
            members = []
            loadError = nil
        }
    }
    @Published var query = ""
    @Published private(set) var members: [CommunityMember] = []
    @Published private(set) var isLoading = false
    /// Shown full screen only while `members` is empty.
    @Published var loadError: String?
    /// Shown in the error banner.
    @Published var actionErrorMessage: String?
    @Published var toastMessage: String?
    @Published private(set) var actingOnUserId: UUID?

    let communityId: UUID
    let communityName: String?

    private let adminService: any CommunityAdminServiceProtocol
    private let communityContext: CommunityContext
    private let authService: any AuthServiceProtocol
    private let refreshDashboard: @MainActor (String) async -> Void
    /// Only the newest load writes its result (a list switch or pull-to-refresh can overlap one).
    private var loadGeneration = 0

    init(
        communityId: UUID,
        communityName: String?,
        adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
        communityContext: CommunityContext? = nil,
        authService: any AuthServiceProtocol = AuthService.shared,
        refreshDashboard: @escaping @MainActor (String) async -> Void = {
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.dashboard, trigger: $0)
        }
    ) {
        self.communityId = communityId
        self.communityName = communityName
        self.adminService = adminService
        self.communityContext = communityContext ?? .shared
        self.authService = authService
        self.refreshDashboard = refreshDashboard
    }

    // MARK: - Derived

    /// `members` matched against the query by name, ignoring case and diacritics.
    var filteredMembers: [CommunityMember] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return members }
        return members.filter {
            $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// The caller's role here, only while the membership is active.
    private var callerRole: CommunityRole? {
        guard let row = communityContext.membership(for: communityId), row.status == .active else { return nil }
        return row.role
    }

    func actions(for member: CommunityMember) -> [CommunityMemberAction] {
        CommunityMemberActions.available(
            for: member,
            callerId: authService.currentUserId,
            callerRole: callerRole,
            isPlatformAdmin: communityContext.isPlatformAdmin
        )
    }

    // MARK: - Load

    func load() async {
        await reload(reportingErrors: true)
    }

    /// `reportingErrors` is false for the reload after an action: its failure changes nothing shown.
    private func reload(reportingErrors: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedList = list
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        if reportingErrors { loadError = nil }

        if communityContext.isAwaitingMemberships {
            await communityContext.refreshMemberships()
        }

        // `get_community_members` answers the active directory to a plain member, which would read
        // as an admin list; check the role first.
        guard communityContext.isAdmin(of: communityId) else {
            guard generation == loadGeneration else { return }
            access = .notAdmin
            members = []
            return
        }
        access = .allowed

        do {
            let rows = try await adminService.fetchCommunityMembers(
                communityId: communityId,
                status: requestedList == .active ? .active : .removed,
                limit: Constants.Community.membersPageSize,
                offset: 0
            )
            guard generation == loadGeneration, requestedList == list else { return }
            members = rows
            loadError = nil
        } catch {
            AppLogger.error("community", "fetchCommunityMembers(\(requestedList)) failed: \(error)")
            guard reportingErrors, generation == loadGeneration, requestedList == list else { return }
            if members.isEmpty {
                loadError = "common_load_error".localized
            } else {
                actionErrorMessage = "common_load_error".localized
            }
        }
    }

    // MARK: - Actions

    /// One action at a time. A success changes the row before the follow-up reloads, so a reload
    /// that fails cannot bring a removed member back or show an error for an action that worked.
    @discardableResult
    func perform(_ action: CommunityMemberAction, on member: CommunityMember, reason: String? = nil) async -> Bool {
        guard actingOnUserId == nil, actions(for: member).contains(action) else { return false }
        actingOnUserId = member.id
        actionErrorMessage = nil
        let name = member.membersDisplayName

        do {
            switch action {
            case .remove:
                _ = try await adminService.removeMember(
                    communityId: communityId,
                    userId: member.id,
                    reason: Self.removalNote(from: reason)
                )
            case .readmit:
                try await adminService.readmitMember(communityId: communityId, userId: member.id)
            case .makeAdmin:
                try await adminService.setMemberRole(communityId: communityId, userId: member.id, role: .admin)
            case .makeMember:
                try await adminService.setMemberRole(communityId: communityId, userId: member.id, role: .member)
            case .transferOwnership:
                try await adminService.transferOwnership(communityId: communityId, userId: member.id)
            }
        } catch let refusal as CommunityRPCError {
            actingOnUserId = nil
            switch refusal.code {
            case nil:
                // The server's unauthorized answer carries no code: the caller's role changed.
                actionErrorMessage = "community_member_action_not_allowed".localized
                await reloadAfterAction()
            case .notActive?, .notRemoved?:
                // Someone else already changed this member.
                actionErrorMessage = refusal.localizedMessage
                await reloadAfterAction()
            default:
                actionErrorMessage = refusal.localizedMessage
            }
            return false
        } catch {
            actingOnUserId = nil
            AppLogger.error("community", "member action \(action) failed: \(error)")
            actionErrorMessage = "community_error_generic".localized
            return false
        }

        actingOnUserId = nil
        switch action {
        case .remove:
            members.removeAll { $0.id == member.id }
            toastMessage = String(format: "community_member_removed_toast".localized, name)
            await refreshDashboard("removedMember")
        case .readmit:
            members.removeAll { $0.id == member.id }
            toastMessage = String(format: "community_member_readmitted_toast".localized, name)
        case .makeAdmin:
            replaceRow(member.id, role: .admin)
            toastMessage = String(format: "community_member_role_changed_toast".localized, name)
        case .makeMember:
            replaceRow(member.id, role: .member)
            toastMessage = String(format: "community_member_role_changed_toast".localized, name)
        case .transferOwnership:
            toastMessage = String(format: "community_member_transferred_toast".localized, name)
        }
        HapticManager.success()
        await reloadAfterAction()
        return true
    }

    private func reloadAfterAction() async {
        await communityContext.refreshMemberships()
        await reload(reportingErrors: false)
    }

    private func replaceRow(_ userId: UUID, role: CommunityRole) {
        guard let index = members.firstIndex(where: { $0.id == userId }) else { return }
        members[index] = members[index].replacingRole(role)
    }

    /// Trimmed and sanitized to `removalNoteMaxLength`; nil when nothing is left.
    static func removalNote(from raw: String?) -> String? {
        guard let raw else { return nil }
        let note = Validators.sanitizeUserInput(raw, maxLength: Constants.Community.removalNoteMaxLength)
        return note.isEmpty ? nil : note
    }
}
