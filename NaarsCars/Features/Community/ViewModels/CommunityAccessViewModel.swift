//
//  CommunityAccessViewModel.swift
//  NaarsCars
//
//  The owner's access screen: listed or hidden, how people join, and the service area. Saves the
//  three together through update_community_access; the server decides every rule.
//

internal import Combine
import Foundation

@MainActor
final class CommunityAccessViewModel: ObservableObject {
    @Published private(set) var settings: CommunitySettings?
    /// The switch as the owner left it; saved with `joinPolicy` and, when it changed, the area.
    @Published var isListed = false {
        didSet {
            // A community with no stored area must choose one before it can be listed.
            if isListed, let settings, settings.area == nil { isChangingArea = true }
        }
    }
    @Published var joinPolicy: CommunityJoinPolicy = .approve
    /// The owner is choosing a different area (or, with none stored, a first one).
    @Published var isChangingArea = false {
        didSet {
            guard oldValue != isChangingArea, !isChangingArea else { return }
            // Closing the editor drops what was typed and goes back to the stored area.
            areaDraft.reset(to: settings?.area)
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    /// Shown full screen only while `settings` is nil.
    @Published private(set) var loadError: String?
    @Published var errorMessage: String?
    @Published var toastMessage: String?

    /// The service area and the nearby check (this community left out of its own check). Its
    /// changes do not redraw a view observing only this model; the Save button observes both.
    let areaDraft: ServiceAreaDraftModel

    /// Open is not offered here; the server accepts only these two.
    let policyChoices: [CommunityJoinPolicy] = [.approve, .invite]

    let communityId: UUID

    private let adminService: any CommunityAdminServiceProtocol
    private let communityContext: CommunityContext

    init(
        communityId: UUID,
        adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
        service: any CommunityServiceProtocol = CommunityService.shared,
        geocoder: any PlaceGeocoding = PlaceGeocoder.shared,
        communityContext: CommunityContext? = nil
    ) {
        self.communityId = communityId
        self.adminService = adminService
        self.communityContext = communityContext ?? .shared
        self.areaDraft = ServiceAreaDraftModel(geocoder: geocoder, service: service, excluding: communityId)
    }

    // MARK: - Derived (the server decides; these only choose what to show)

    /// Only the owner changes access (a platform admin and a plain admin read only).
    var isOwner: Bool {
        guard let row = communityContext.membership(for: communityId), row.status == .active else { return false }
        return row.role == .owner
    }

    var isDefaultCommunity: Bool {
        settings?.isDefault == true
    }

    /// The community has no stored area, so listing it needs one.
    var hasStoredArea: Bool {
        settings?.area != nil
    }

    /// Listed, and either hidden before or choosing a different area: the nearby check must run
    /// (without this community) before saving.
    var needsNearbyCheck: Bool {
        guard let settings, isListed else { return false }
        return !settings.isPublic || isChangingArea
    }

    private var storedPolicy: CommunityJoinPolicy? {
        settings.flatMap { CommunityJoinPolicy(rawValue: $0.joinPolicy) }
    }

    /// The area to send: only while the owner is choosing one, and only when it is not the stored one.
    private var newArea: ServiceArea? {
        guard isListed, isChangingArea, let area = areaDraft.area, area != settings?.area else { return nil }
        return area
    }

    private var hasChange: Bool {
        guard let settings else { return false }
        return isListed != settings.isPublic || joinPolicy != storedPolicy || newArea != nil
    }

    var canSave: Bool {
        guard isOwner, settings != nil, !isSaving, hasChange, policyChoices.contains(joinPolicy) else { return false }
        if isDefaultCommunity && !isListed { return false }
        if needsNearbyCheck { return areaDraft.isReadyToSubmit }
        return true
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil

        if communityContext.isAwaitingMemberships {
            await communityContext.refreshMemberships()
        }
        do {
            apply(try await adminService.fetchCommunitySettings(communityId: communityId))
        } catch {
            AppLogger.error("community", "fetchCommunitySettings failed: \(error)")
            if settings == nil {
                loadError = "common_load_error".localized
            } else {
                errorMessage = "common_load_error".localized
            }
        }
    }

    private func apply(_ fetched: CommunitySettings) {
        settings = fetched
        joinPolicy = CommunityJoinPolicy(rawValue: fetched.joinPolicy) ?? .approve
        // Closing the editor first, so its reset to the stored area runs once with the new settings.
        isChangingArea = false
        areaDraft.reset(to: fetched.area)
        // Also forces the area editor open for a listed community that has no stored area.
        isListed = fetched.isPublic
    }

    // MARK: - Save

    /// One save at a time. A success applies the saved values, refreshes the memberships (their
    /// names, chips and policies), and says members were told.
    @discardableResult
    func save() async -> Bool {
        guard canSave, let current = settings else { return false }
        let area = newArea
        let reason = needsNearbyCheck && areaDraft.needsReason ? areaDraft.trimmedReason : nil
        let change = CommunityAccessChange(isListed: isListed, joinPolicy: joinPolicy, newArea: area, reason: reason)
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        do {
            try await adminService.updateCommunityAccess(communityId: communityId, change: change)
        } catch let refusal as CommunityRPCError {
            await handleRefusal(refusal)
            return false
        } catch {
            AppLogger.error("community", "updateCommunityAccess failed: \(error)")
            errorMessage = "community_error_generic".localized
            return false
        }

        let saved = CommunitySettings(
            id: current.id,
            name: current.name,
            description: current.description,
            joinPolicy: change.joinPolicy.rawValue,
            membersCanInvite: current.membersCanInvite,
            isPublic: change.isListed,
            isDefault: current.isDefault,
            timezone: current.timezone,
            area: area ?? current.area
        )
        apply(saved)
        HapticManager.success()
        toastMessage = "community_access_saved_toast".localized
        await communityContext.refreshMemberships()
        return true
    }

    // MARK: - Private

    /// A refusal shows its sentence. `reason_required` means the nearby check missed an overlap, so
    /// it runs again and the reason field appears; `not_owner` means the role changed, so the
    /// memberships are read again and the screen goes read only. `invalid` ("This code isn't valid")
    /// does not fit this screen, so it reads as the generic error.
    private func handleRefusal(_ refusal: CommunityRPCError) async {
        switch refusal.code {
        case .invalid:
            errorMessage = "community_error_generic".localized
        default:
            errorMessage = refusal.localizedMessage
        }
        switch refusal.code {
        case .reasonRequired:
            await areaDraft.checkNearby()
        case .notOwner:
            await communityContext.refreshMemberships()
        default:
            break
        }
    }
}
