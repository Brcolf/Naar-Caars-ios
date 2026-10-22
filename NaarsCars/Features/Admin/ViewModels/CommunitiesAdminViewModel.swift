//
//  CommunitiesAdminViewModel.swift
//  NaarsCars
//
//  Platform admins: every community, archive and restore, public or private, and owned-limit requests
//

internal import Combine
import Foundation

enum CommunityAdminAction: Equatable {
    case requestsToJoin, archive, restore, makePrivate, makePublic, openAdminPanel
}

@MainActor
final class CommunitiesAdminViewModel: ObservableObject {
    @Published private(set) var communities: [PlatformCommunity] = []
    @Published private(set) var limitRequests: [PlatformLimitRequest] = []
    /// Merge proposals still pending, or decided or expired within 30 days, newest first.
    @Published private(set) var mergeProposals: [PlatformMergeProposal] = []
    @Published private(set) var isLoading = false
    /// True once one load has succeeded; until then an empty list shows the skeleton.
    @Published private(set) var hasLoaded = false
    /// Shown full screen only while nothing has loaded.
    @Published var loadError: String?
    /// Shown in the error banner.
    @Published var actionErrorMessage: String?
    @Published var toastMessage: String?
    /// The community or limit request an action is running on (one at a time).
    @Published private(set) var busyId: UUID?

    private let adminService: any CommunityAdminServiceProtocol

    init(adminService: any CommunityAdminServiceProtocol = CommunityService.shared) {
        self.adminService = adminService
    }

    /// The actions a row offers. The default community is never offered Archive or Make private:
    /// the server refuses both (it stays public and is never archived while a member remains).
    /// Every community that is not archived opens its Admin panel (first in the menu), including
    /// one the platform admin does not belong to. A community merged into another is never offered Restore.
    static func actions(for community: PlatformCommunity) -> [CommunityAdminAction] {
        let isArchived = community.archivedAt != nil
        var actions: [CommunityAdminAction] = []
        if !isArchived {
            actions.append(.openAdminPanel)
        }
        if community.pendingCount > 0 && !isArchived {
            actions.append(.requestsToJoin)
        }
        if !isArchived {
            if community.isPublic {
                if !community.isDefault { actions.append(.makePrivate) }
            } else {
                actions.append(.makePublic)
            }
        }
        if isArchived {
            // A merged community stays archived: `unarchive_community` refuses it (20261021_0022).
            if community.mergedIntoName == nil { actions.append(.restore) }
        } else if !community.isDefault {
            actions.append(.archive)
        }
        return actions
    }

    /// The status of a merge proposal as the list shows it; a status this build does not know is
    /// shown as the server wrote it.
    static func mergeStatusText(_ status: String) -> String {
        switch status {
        case "pending": return "admin_communities_merge_status_pending".localized
        case "accepted": return "admin_communities_merge_status_accepted".localized
        case "declined": return "admin_communities_merge_status_declined".localized
        case "withdrawn": return "admin_communities_merge_status_withdrawn".localized
        case "expired": return "admin_communities_merge_status_expired".localized
        default: return status
        }
    }

    // MARK: - Load

    func load() async {
        await fetch(reportingFailure: true)
    }

    /// `reportingFailure: false` is the refresh after an action that succeeded: its failure is only
    /// logged, so no error appears for the action that worked.
    private func fetch(reportingFailure: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await adminService.fetchPlatformCommunities()
            communities = result.communities
            limitRequests = result.limitRequests
            mergeProposals = result.mergeProposals
            loadError = nil
            hasLoaded = true
        } catch let refusal as CommunityRPCError {
            AppLogger.warning("community", "fetchPlatformCommunities refused: \(refusal.serverMessage)")
            if reportingFailure { reportLoadFailure(refusal.localizedMessage) }
        } catch {
            AppLogger.error("community", "fetchPlatformCommunities failed: \(error)")
            if reportingFailure { reportLoadFailure("community_error_generic".localized) }
        }
    }

    /// A list that has rows keeps them and shows a banner; an empty one shows the full-screen error.
    private func reportLoadFailure(_ message: String) {
        if hasLoaded {
            actionErrorMessage = message
        } else {
            loadError = message
        }
    }

    // MARK: - Community actions

    /// Runs one action. Requests to join and Open admin panel are navigation and do nothing here. The action is checked
    /// again against the row as last loaded, so a stale menu cannot archive the default community.
    func perform(_ action: CommunityAdminAction, on community: PlatformCommunity) async {
        guard busyId == nil, action != .requestsToJoin, action != .openAdminPanel else { return }
        let current = communities.first(where: { $0.id == community.id }) ?? community
        guard Self.actions(for: current).contains(action) else { return }

        busyId = current.id
        defer { busyId = nil }
        actionErrorMessage = nil

        do {
            switch action {
            case .archive:
                try await adminService.archiveCommunity(communityId: current.id)
            case .restore:
                try await adminService.unarchiveCommunity(communityId: current.id)
            case .makePrivate:
                try await adminService.setCommunityPublic(communityId: current.id, isPublic: false)
            case .makePublic:
                try await adminService.setCommunityPublic(communityId: current.id, isPublic: true)
            case .requestsToJoin, .openAdminPanel:
                return
            }
        } catch let refusal as CommunityRPCError {
            // These RPCs refuse with no code, so this is the generic message; the server's text is logged.
            AppLogger.warning("community", "\(action) refused: \(refusal.serverMessage)")
            actionErrorMessage = refusal.localizedMessage
            await fetch(reportingFailure: false)
            return
        } catch {
            AppLogger.error("community", "\(action) failed: \(error)")
            actionErrorMessage = "community_error_generic".localized
            return
        }

        // Show the new state at once, so a refresh that fails cannot leave a stale menu behind.
        replaceRow(current.applying(action))
        HapticManager.success()
        toastMessage = String(format: Self.successKey(for: action).localized, current.name)
        await fetch(reportingFailure: false)
    }

    private func replaceRow(_ row: PlatformCommunity) {
        guard let index = communities.firstIndex(where: { $0.id == row.id }) else { return }
        communities[index] = row
    }

    private static func successKey(for action: CommunityAdminAction) -> String {
        switch action {
        case .archive: return "admin_communities_archived_toast"
        case .restore: return "admin_communities_restored_toast"
        case .makePrivate: return "admin_communities_made_private_toast"
        case .makePublic, .requestsToJoin, .openAdminPanel: return "admin_communities_made_public_toast"
        }
    }

    // MARK: - Limit requests

    /// A decided request leaves the list at once, whatever a later refresh returns.
    func decide(_ request: PlatformLimitRequest, approve: Bool) async {
        guard busyId == nil else { return }
        busyId = request.id
        defer { busyId = nil }
        actionErrorMessage = nil

        do {
            let decision = try await adminService.decideOwnedCommunityLimit(requestId: request.id, approve: approve)
            limitRequests.removeAll { $0.id == request.id }
            HapticManager.success()
            toastMessage = approve
                ? String(format: "admin_communities_limit_approved_toast".localized, decision.maxOwned)
                : "admin_communities_limit_declined_toast".localized
        } catch let refusal as CommunityRPCError {
            // "Already decided" also lands here; the reload drops a request someone else decided.
            AppLogger.warning("community", "decideOwnedCommunityLimit refused: \(refusal.serverMessage)")
            actionErrorMessage = refusal.localizedMessage
            await fetch(reportingFailure: false)
        } catch {
            AppLogger.error("community", "decideOwnedCommunityLimit failed: \(error)")
            actionErrorMessage = "community_error_generic".localized
        }
    }
}

private extension PlatformCommunity {
    /// The row as it reads after `action` succeeded.
    func applying(_ action: CommunityAdminAction) -> PlatformCommunity {
        var isPublic = self.isPublic
        var archivedAt = self.archivedAt
        switch action {
        case .archive: archivedAt = Date()
        case .restore: archivedAt = nil
        case .makePrivate: isPublic = false
        case .makePublic: isPublic = true
        case .requestsToJoin, .openAdminPanel: break
        }
        return PlatformCommunity(
            id: id, name: name, description: description, createdBy: createdBy, creatorName: creatorName,
            createdAt: createdAt, isPublic: isPublic, isDefault: isDefault, joinPolicy: joinPolicy,
            archivedAt: archivedAt, archivedBy: archivedAt == nil ? nil : archivedBy,
            memberCount: memberCount, pendingCount: pendingCount, ownerCount: ownerCount,
            openReportCount: openReportCount, area: area, isTest: isTest, mergedIntoName: mergedIntoName,
            listingReason: listingReason, listingOverlaps: listingOverlaps, listingEventAt: listingEventAt
        )
    }
}
