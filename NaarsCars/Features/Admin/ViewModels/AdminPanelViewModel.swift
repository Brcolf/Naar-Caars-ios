//
//  AdminPanelViewModel.swift
//  NaarsCars
//
//  ViewModel for admin panel dashboard: every community for platform admins, one community for
//  its owners and admins
//

import Foundation
internal import Combine

/// What the admin panel shows: every community (platform admins only) or one community.
enum AdminPanelScope: Hashable {
    case all
    case community(UUID)

    /// nil for `.all` (every community).
    var communityId: UUID? {
        if case .community(let id) = self { return id }
        return nil
    }

    /// The scope the Profile row opens: a platform admin gets `.all`; anyone else the first
    /// community they own or administer; nil hides the row. The server decides every action.
    static func initial(isPlatformAdmin: Bool, administered: [CommunityMembership]) -> AdminPanelScope? {
        if isPlatformAdmin { return .all }
        return administered.first.map { .community($0.communityId) }
    }
}

/// One row of the panel's title menu.
struct AdminPanelMenuEntry: Identifiable, Equatable {
    let scope: AdminPanelScope
    let title: String
    var id: AdminPanelScope { scope }
}

/// The community an announcement from this panel goes to.
struct BroadcastTarget: Equatable {
    let communityId: UUID
    let communityName: String
}

/// ViewModel for admin panel dashboard
@MainActor
final class AdminPanelViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Starts true: until the check has run the screen is "verifying", not "access denied".
    @Published var isVerifyingAdmin: Bool = true
    @Published var isAdmin: Bool = false
    @Published var fulfilledCount: Int = 0
    @Published var totalSavings: Double = 0
    @Published var activeRidesCount: Int = 0
    @Published var error: AppError?
    @Published var isLoading: Bool = false
    /// Set when the admin check could not be completed (offline, server error). That is not
    /// an answer about admin status, so the screen offers a retry instead of "Access Denied".
    @Published var verificationErrorMessage: String?
    /// Set when the dashboard figures could not be loaded
    @Published var statsErrorMessage: String?
    /// True once the figures have loaded; until then the tiles show a dash rather than 0
    @Published var hasLoadedStats: Bool = false

    @Published private(set) var scope: AdminPanelScope
    /// The shown community's name (nil for `.all`).
    @Published private(set) var communityName: String?
    /// Where an announcement goes; nil until resolved, and when it could not be.
    @Published private(set) var broadcastTarget: BroadcastTarget?

    // MARK: - Private Properties

    private let adminService: any AdminServiceProtocol
    private let communityAdminService: any CommunityAdminServiceProtocol
    private let communityContext: CommunityContext
    private let verifyPlatformAdmin: @MainActor () async throws -> Void
    /// The community the panel was opened on, kept in the menu even when it is not a membership
    /// (a platform admin opening it from Admin → Communities).
    private let openedCommunity: (id: UUID, name: String)?
    private var hasVerified = false
    /// Bumped on every scope change; a check or load started under an older value writes nothing.
    private var generation = 0

    // MARK: - Init

    init(
        initialScope: AdminPanelScope = .all,
        communityName: String? = nil,
        adminService: any AdminServiceProtocol = AdminService.shared,
        communityAdminService: any CommunityAdminServiceProtocol = CommunityService.shared,
        communityContext: CommunityContext? = nil,
        verifyPlatformAdmin: @escaping @MainActor () async throws -> Void = { try await AdminService.shared.verifyAdminStatus() }
    ) {
        let context = communityContext ?? .shared
        self.scope = initialScope
        self.adminService = adminService
        self.communityAdminService = communityAdminService
        self.communityContext = context
        self.verifyPlatformAdmin = verifyPlatformAdmin
        if let id = initialScope.communityId {
            let name = communityName ?? context.name(for: id)
            self.communityName = name
            self.openedCommunity = name.map { (id, $0) }
        } else {
            self.communityName = nil
            self.openedCommunity = nil
        }
    }

    // MARK: - Computed Properties

    /// Formatted savings string (e.g. "$1,234")
    var formattedSavings: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD" // estimates are US dollars; the region must not relabel them
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: totalSavings)) ?? "$0"
    }

    /// "Admin Panel" for every community; the community's name for one.
    var title: String {
        guard let id = scope.communityId else { return "admin_panel_title".localized }
        return communityName ?? displayName(for: id) ?? "admin_panel_title".localized
    }

    /// Platform admins: All communities, then every active membership. Anyone else: the
    /// communities they own or administer. The current (and the opened) community is always included.
    var menuEntries: [AdminPanelMenuEntry] {
        var entries: [AdminPanelMenuEntry] = []
        if communityContext.isPlatformAdmin {
            entries.append(AdminPanelMenuEntry(scope: .all, title: "admin_panel_all_communities".localized))
            entries += communityContext.activeMemberships.map {
                AdminPanelMenuEntry(scope: .community($0.communityId), title: $0.name)
            }
        } else {
            entries += communityContext.administeredCommunities.map {
                AdminPanelMenuEntry(scope: .community($0.communityId), title: $0.name)
            }
        }
        var extras: [AdminPanelMenuEntry] = []
        if let opened = openedCommunity {
            extras.append(AdminPanelMenuEntry(scope: .community(opened.id), title: opened.name))
        }
        if scope.communityId != nil {
            extras.append(AdminPanelMenuEntry(scope: scope, title: title))
        }
        for extra in extras where !entries.contains(where: { $0.scope == extra.scope }) {
            entries.append(extra)
        }
        return entries
    }

    /// Requests to join waiting in the shown community (nil for `.all`).
    var pendingCount: Int? {
        communityContext.membership(for: scope.communityId)?.pendingCount
    }

    // MARK: - Public Methods

    /// Verify admin access for the current scope, then load its figures and announcement target.
    /// `.all` asks the server whether the caller is a platform admin; a community scope checks the
    /// caller's membership (after the first membership load, when it is still running).
    func verifyAdminAccess() async {
        guard !hasVerified else { return }
        let generation = self.generation
        let requested = scope

        isVerifyingAdmin = true
        error = nil
        verificationErrorMessage = nil

        let allowed: Bool
        switch requested {
        case .all:
            do {
                try await verifyPlatformAdmin()
                allowed = true
            } catch {
                guard generation == self.generation else { return }
                isAdmin = false
                isVerifyingAdmin = false
                // verifyAdminStatus throws .unauthorized only for a confirmed "not an admin" (or no
                // session). Anything else is a network or server failure and must stay retryable.
                if let appError = error as? AppError, case .unauthorized = appError {
                    self.error = appError
                    AppLogger.error("security", "Non-admin accessed admin panel view")
                } else {
                    self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
                    verificationErrorMessage = "admin_verify_failed".localized
                    AppLogger.error("admin", "Admin check failed: \(error.localizedDescription)")
                }
                return
            }
        case .community(let id):
            if communityContext.isAwaitingMemberships {
                await communityContext.refreshMemberships()
            }
            allowed = communityContext.isAdmin(of: id)
        }

        guard generation == self.generation else { return }
        isVerifyingAdmin = false
        guard allowed else {
            isAdmin = false
            error = .unauthorized
            AppLogger.error("security", "Non-admin opened the admin panel of a community")
            return
        }

        hasVerified = true
        isAdmin = true
        if communityName == nil, let id = requested.communityId {
            communityName = displayName(for: id)
        }
        await loadStats()
        guard generation == self.generation, isAdmin else { return }
        await resolveBroadcastTarget()
    }

    /// Switches the panel to another scope: the previous figures are dropped at once, so the
    /// tiles never show one community's numbers under another's title.
    func select(_ newScope: AdminPanelScope) async {
        guard newScope != scope else { return }
        generation += 1
        scope = newScope
        communityName = newScope.communityId.flatMap { displayName(for: $0) }
        hasVerified = false
        isAdmin = false
        error = nil
        verificationErrorMessage = nil
        fulfilledCount = 0
        totalSavings = 0
        activeRidesCount = 0
        hasLoadedStats = false
        statsErrorMessage = nil
        isLoading = false
        broadcastTarget = nil
        await verifyAdminAccess()
    }

    /// Load the dashboard figures of the current scope. Applied only while the scope is unchanged.
    func loadStats() async {
        let generation = self.generation
        let requested = scope
        isLoading = true
        error = nil
        statsErrorMessage = nil
        defer { if generation == self.generation { isLoading = false } }

        do {
            let stats = try await adminService.fetchDashboardStats(communityId: requested.communityId)
            guard generation == self.generation else { return }
            fulfilledCount = stats.fulfilledCount
            totalSavings = stats.totalSavings
            activeRidesCount = stats.activeRidesCount
            hasLoadedStats = true
        } catch let refusal as CommunityRPCError where refusal.code == nil && requested.communityId != nil {
            // The server's unauthorized answer carries no code: the caller's role is gone.
            AppLogger.warning("admin", "get_community_stats refused: \(refusal.serverMessage)")
            guard generation == self.generation else { return }
            hasVerified = false
            isAdmin = false
            self.error = .unauthorized
        } catch {
            guard generation == self.generation else { return }
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            statsErrorMessage = "admin_stats_load_failed".localized
            AppLogger.error("admin", "Error loading stats: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func displayName(for communityId: UUID) -> String? {
        if let name = communityContext.name(for: communityId) { return name }
        if let opened = openedCommunity, opened.id == communityId { return opened.name }
        return nil
    }

    /// A community scope announces to that community; `.all` to the default community. A failure
    /// leaves the target nil (the announcement row is then hidden).
    private func resolveBroadcastTarget() async {
        let generation = self.generation
        let target: BroadcastTarget?
        switch scope {
        case .community(let id):
            if let name = communityName ?? displayName(for: id) {
                target = BroadcastTarget(communityId: id, communityName: name)
            } else {
                target = await namedTarget(id)
            }
        case .all:
            if let row = communityContext.memberships.first(where: \.isDefault) {
                target = BroadcastTarget(communityId: row.communityId, communityName: row.name)
            } else {
                do {
                    if let id = try await communityAdminService.fetchDefaultCommunityId() {
                        target = await namedTarget(id)
                    } else {
                        target = nil
                    }
                } catch {
                    AppLogger.warning("admin", "fetchDefaultCommunityId failed: \(error.localizedDescription)")
                    target = nil
                }
            }
        }
        guard generation == self.generation else { return }
        broadcastTarget = target
    }

    private func namedTarget(_ communityId: UUID) async -> BroadcastTarget? {
        do {
            let settings = try await communityAdminService.fetchCommunitySettings(communityId: communityId)
            return BroadcastTarget(communityId: communityId, communityName: settings.name)
        } catch {
            AppLogger.warning("admin", "fetchCommunitySettings for the announcement failed: \(error.localizedDescription)")
            return nil
        }
    }
}
