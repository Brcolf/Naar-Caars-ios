//
//  PendingApprovalViewModel.swift
//  NaarsCars
//
//  The waiting screen's membership list and its relaunch decision
//

import Foundation
internal import Combine

/// What the waiting screen should do after a poll.
enum PendingApprovalOutcome: Equatable {
    /// Run `performCriticalLaunch()`: an active membership, or nothing left to wait for.
    case relaunch
    /// Stay on the waiting screen.
    case waiting
}

/// Drives the waiting screen (`.pendingApproval`). It loads the person's memberships itself,
/// because `CommunityContext` is loaded only on the authenticated path, names every community
/// that has a pending request, and decides when to relaunch: once an active membership exists,
/// or when nothing is pending and the account route no longer reads `.pendingApproval` (a
/// rejection routes to onboarding). It never relaunches while the route still says pending, and
/// it relaunches at most once per screen.
@MainActor
final class PendingApprovalViewModel: ObservableObject {
    /// Names of the communities with a pending request; empty keeps today's generic copy.
    @Published private(set) var pendingCommunityNames: [String] = []
    /// Every community the person already holds a row in (excluded from "Join another community").
    @Published private(set) var membershipIds: Set<UUID> = []

    private let service: any CommunityServiceProtocol
    private let accountRoute: @MainActor () async throws -> AuthState
    private let approvalCheck: @MainActor () async -> Bool
    /// Set once a poll decides to relaunch; later polls answer `.relaunch` without a fetch.
    private var decidedRelaunch = false

    /// - Parameters:
    ///   - service: Reads `get_my_memberships` (works while the account is unapproved)
    ///   - accountRoute: The throwing account-flags read, mapped to an `AuthState`
    ///   - approvalCheck: Today's lightweight approval check, the fallback when the list fails
    init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        accountRoute: @escaping @MainActor () async throws -> AuthState = { try await AppLaunchManager.shared.readAccountRoute() },
        approvalCheck: @escaping @MainActor () async -> Bool = { await AppLaunchManager.shared.checkApprovalStatusOnly() }
    ) {
        self.service = service
        self.accountRoute = accountRoute
        self.approvalCheck = approvalCheck
    }

    /// One check of the person's memberships (on appear, on each tick and on Refresh).
    func poll() async -> PendingApprovalOutcome {
        if decidedRelaunch { return .relaunch }

        let result: PendingApprovalOutcome
        do {
            let rows = try await service.fetchMyMemberships()
            let pending = rows.filter { $0.status == .pending }
            let names = pending.map(\.name)
            if pendingCommunityNames != names { pendingCommunityNames = names }
            let ids = Set(rows.map(\.communityId))
            if membershipIds != ids { membershipIds = ids }

            if rows.contains(where: { $0.status == .active }) {
                result = .relaunch
            } else if !pending.isEmpty {
                result = .waiting
            } else if let route = try? await accountRoute(), route != .pendingApproval {
                // Rejected, or nothing left: the relaunch routes to onboarding.
                result = .relaunch
            } else {
                // The flags still say pending (or could not be read): relaunching would land on
                // this same screen, in a loop.
                result = .waiting
            }
        } catch {
            AppLogger.warning("auth", "Waiting screen membership read failed: \(error.localizedDescription)")
            result = await approvalCheck() ? .relaunch : .waiting
        }

        if result == .relaunch { decidedRelaunch = true }
        return result
    }

    /// The confirmation left by an archive of the account's last community (`RootNotice`), once:
    /// an archive can lead here when a request is still waiting in another community. Nil
    /// afterwards, so onboarding (or a later root) does not show it again.
    func takeRootNotice() -> String? {
        RootNotice.take()
    }
}
