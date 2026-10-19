//
//  CommunitySettingsViewModel.swift
//  NaarsCars
//
//  One community's name, description, who joins, who invites, time zone, and archive
//

internal import Combine
import Foundation

@MainActor
final class CommunitySettingsViewModel: ObservableObject {
    enum Access: Equatable { case checking, allowed, notAdmin }

    @Published private(set) var access: Access = .checking
    @Published private(set) var settings: CommunitySettings?
    @Published var name = ""
    @Published var description = ""
    @Published var requiresApproval = true
    @Published var membersCanInvite = true
    /// IANA identifier; edited only by the owner or a platform admin (`canEdit`).
    @Published var timezone = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isArchiving = false
    /// Shown full screen only while `settings` is nil.
    @Published private(set) var loadError: String?
    /// Shown in the error banner.
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    /// The confirmation shown after an archive ("<name> was archived."). Set before `didArchive`,
    /// because the screen closes as soon as `didArchive` turns true and hands this text to its
    /// presenter (`CommunitySettingsView.onArchived`); this screen's own toast is gone by then.
    @Published private(set) var archiveConfirmation: String?
    @Published private(set) var didArchive = false

    let communityId: UUID

    private let adminService: any CommunityAdminServiceProtocol
    private let communityContext: CommunityContext
    private let refreshDashboard: @MainActor (String) async -> Void
    /// Only the newest load writes its result (pull-to-refresh can overlap the reload after a save).
    private var loadGeneration = 0

    init(
        communityId: UUID,
        adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
        communityContext: CommunityContext? = nil,
        refreshDashboard: @escaping @MainActor (String) async -> Void = {
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.dashboard, trigger: $0)
        }
    ) {
        self.communityId = communityId
        self.adminService = adminService
        self.communityContext = communityContext ?? .shared
        self.refreshDashboard = refreshDashboard
    }

    // MARK: - Derived (the server decides; these only choose what to show)

    /// The caller's role here, only while the membership is active.
    private var callerRole: CommunityRole? {
        guard let row = communityContext.membership(for: communityId), row.status == .active else { return nil }
        return row.role
    }

    /// The owner or a platform admin (update_community, 20261017_0005 :694-697); a plain admin reads only.
    var canEdit: Bool {
        access == .allowed && (callerRole == .owner || communityContext.isPlatformAdmin)
    }

    /// The owner or a platform admin, never the default community (archive_community :784-794).
    var canArchive: Bool {
        canEdit && settings?.isDefault == false
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Only the fields that differ from `settings` after trimming. An emptied description is sent
    /// as "" (which clears it).
    var change: CommunitySettingsChange {
        guard let settings else { return CommunitySettingsChange() }
        var change = CommunitySettingsChange()
        if trimmedName != settings.name { change.name = trimmedName }
        if trimmedDescription != (settings.description ?? "") { change.description = trimmedDescription }
        let policy: CommunityJoinPolicy = requiresApproval ? .approve : .invite
        if policy.rawValue != settings.joinPolicy { change.joinPolicy = policy }
        if membersCanInvite != settings.membersCanInvite { change.membersCanInvite = membersCanInvite }
        if !timezone.isEmpty, timezone != settings.timezone { change.timezone = timezone }
        return change
    }

    var canSave: Bool {
        canEdit
            && !isSaving
            && !isArchiving
            && !change.isEmpty
            && Constants.Community.nameLength.contains(trimmedName.count)
            && trimmedDescription.count <= Constants.Community.descriptionMaxLength
    }

    // MARK: - Load

    func load() async {
        await reload(reportingErrors: true)
    }

    /// `reportingErrors` is false for the reload after a save: its failure changes nothing shown.
    private func reload(reportingErrors: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        if reportingErrors { loadError = nil }

        if communityContext.isAwaitingMemberships {
            await communityContext.refreshMemberships()
        }

        guard communityContext.isAdmin(of: communityId) else {
            guard generation == loadGeneration else { return }
            access = .notAdmin
            return
        }
        access = .allowed

        do {
            let fetched = try await adminService.fetchCommunitySettings(communityId: communityId)
            guard generation == loadGeneration else { return }
            apply(fetched)
            loadError = nil
        } catch {
            AppLogger.error("community", "fetchCommunitySettings failed: \(error)")
            guard reportingErrors, generation == loadGeneration else { return }
            if settings == nil {
                loadError = "common_load_error".localized
            } else {
                errorMessage = "common_load_error".localized
            }
        }
    }

    private func apply(_ fetched: CommunitySettings) {
        settings = fetched
        name = fetched.name
        description = fetched.description ?? ""
        requiresApproval = fetched.joinPolicy == CommunityJoinPolicy.approve.rawValue
        membersCanInvite = fetched.membersCanInvite
        timezone = fetched.timezone
    }

    // MARK: - Save

    /// One save at a time. A success applies the saved values before the follow-up reload, so a
    /// reload that fails leaves the screen showing what was saved, with no error.
    @discardableResult
    func save() async -> Bool {
        guard canSave, let current = settings else { return false }
        let change = self.change
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        do {
            try await adminService.updateCommunity(communityId: communityId, change: change)
        } catch let refusal as CommunityRPCError {
            await handleRefusal(refusal)
            return false
        } catch {
            AppLogger.error("community", "updateCommunity failed: \(error)")
            errorMessage = "community_error_generic".localized
            return false
        }

        let saved = CommunitySettings(
            id: current.id,
            name: change.name ?? current.name,
            description: change.description.map { $0.isEmpty ? nil : $0 } ?? current.description,
            joinPolicy: change.joinPolicy?.rawValue ?? current.joinPolicy,
            membersCanInvite: change.membersCanInvite ?? current.membersCanInvite,
            isPublic: current.isPublic,
            isDefault: current.isDefault,
            timezone: change.timezone ?? current.timezone
        )
        apply(saved)
        HapticManager.success()
        toastMessage = "community_settings_saved_toast".localized
        // Names in menus and chips come from the memberships.
        await communityContext.refreshMemberships()
        await reload(reportingErrors: false)
        return true
    }

    // MARK: - Archive

    /// Archives the community. A success sets `archiveConfirmation`, then `didArchive` (the screen
    /// closes and its presenter shows the confirmation), then forgets the membership locally before
    /// the refreshes, so a refresh that fails cannot bring it back; forgetting the last active
    /// membership runs `onActiveMembershipsEmpty` (account status re-check).
    @discardableResult
    func archive() async -> Bool {
        guard canArchive, !isArchiving, !isSaving else { return false }
        let communityName = settings?.name ?? communityContext.name(for: communityId) ?? ""
        isArchiving = true
        defer { isArchiving = false }
        errorMessage = nil

        do {
            try await adminService.archiveCommunity(communityId: communityId)
        } catch let refusal as CommunityRPCError {
            await handleRefusal(refusal)
            return false
        } catch {
            AppLogger.error("community", "archiveCommunity failed: \(error)")
            errorMessage = "community_error_generic".localized
            return false
        }

        HapticManager.success()
        archiveConfirmation = String(format: "community_settings_archived_toast".localized, communityName)
        didArchive = true
        await communityContext.forgetMembership(communityId)
        await communityContext.refreshMemberships()
        await refreshDashboard("archivedCommunity")
        return true
    }

    // MARK: - Private

    /// `update_community` and `archive_community` send no refusal code, and their code-less refusals
    /// are not all about roles ("already archived", "the default community cannot be archived",
    /// "not found", a name, description or time zone the server rejects), so a code-less refusal
    /// reads as the generic error (`localizedMessage` gives it for a nil code), never as "your role
    /// may have changed": for these RPCs a missing code does not identify a role change. The screen
    /// still reloads after one, so a role that did change lands it in the read-only or not-admin state.
    private func handleRefusal(_ refusal: CommunityRPCError) async {
        errorMessage = refusal.localizedMessage
        guard refusal.code == nil else { return }
        await communityContext.refreshMemberships()
        await reload(reportingErrors: false)
    }
}
