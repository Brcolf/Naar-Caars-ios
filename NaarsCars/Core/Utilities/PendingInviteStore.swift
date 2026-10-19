//
//  PendingInviteStore.swift
//  NaarsCars
//
//  An invite code typed before sign-in, kept on this device until it is redeemed
//

import Foundation

/// Keeps one invite code for a signed-out visitor (spec §3.7: device-level, cleared on redemption
/// or after `Constants.Community.pendingInviteLifetime`, and on sign-out).
///
/// There is deliberately no `take()`: handing the code to a sheet never clears it, so a sheet that
/// fails to present or is cancelled loses nothing. Only `JoinCommunityViewModel` clears it, once the
/// code is used or known to be dead, and sign-out clears it in `AuthService.clearPerAccountLocalState`.
///
/// Screens that show the saved code (Welcome, onboarding, My communities) re-read it on
/// `didChange`, so a Universal Link that arrives while one of them is on screen shows at once.
struct PendingInviteStore {
    static let codeKey = "community.pendingInviteCode"
    static let savedAtKey = "community.pendingInviteSavedAt"

    /// Posted (object nil) after `save(_:)` stores a code and after `clear()` / `clearIfMatches(_:)`
    /// remove one. Not posted when `peek()` drops an expired code: the caller already reads nil, and
    /// posting from a read could fire during a view update.
    static let didChange = Notification.Name("PendingInviteStore.didChange")

    private let defaults: UserDefaults
    private let now: () -> Date
    private let notificationCenter: NotificationCenter

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.now = now
        self.notificationCenter = notificationCenter
    }

    /// Stores the normalized form of `raw` and the time it was saved.
    func save(_ raw: String) {
        let normalized = CommunityInviteCode.normalize(raw)
        guard !normalized.isEmpty else { return }
        defaults.set(normalized, forKey: Self.codeKey)
        defaults.set(now(), forKey: Self.savedAtKey)
        notificationCenter.post(name: Self.didChange, object: nil)
    }

    /// The stored code, or nil. A code older than the lifetime (or with no save time) is removed.
    func peek() -> String? {
        guard let code = defaults.string(forKey: Self.codeKey), !code.isEmpty else {
            if defaults.object(forKey: Self.savedAtKey) != nil { removeKeys() }
            return nil
        }
        guard let savedAt = defaults.object(forKey: Self.savedAtKey) as? Date,
              now().timeIntervalSince(savedAt) <= Constants.Community.pendingInviteLifetime else {
            removeKeys()
            return nil
        }
        return code
    }

    /// Removes the stored code only when it is `normalized` (another code saved since is kept).
    func clearIfMatches(_ normalized: String) {
        guard let code = defaults.string(forKey: Self.codeKey), code == normalized else { return }
        clear()
    }

    func clear() {
        let hadCode = defaults.object(forKey: Self.codeKey) != nil
            || defaults.object(forKey: Self.savedAtKey) != nil
        removeKeys()
        if hadCode {
            notificationCenter.post(name: Self.didChange, object: nil)
        }
    }

    private func removeKeys() {
        defaults.removeObject(forKey: Self.codeKey)
        defaults.removeObject(forKey: Self.savedAtKey)
    }
}

// MARK: - Incoming join links
//
// Universal Links handed to the scene (`onOpenURL`): save the invite code, then route by launch state.
// Kept in this file because the project gets no new Swift file in this change.
/// What `IncomingLinkHandler` did with a join link. The code is saved in every case.
enum IncomingLinkDecision: Equatable {
    /// Saved, then `NavigationCoordinator.applyExternalDeepLink` (main UI: authenticated or guest).
    case route
    /// Saved only; the screen on show reads the store (Welcome, onboarding), or
    /// `MainTabView.offerPendingInviteIfNeeded` opens My communities from it.
    case saveOnly
    /// Saved; decided again once the launch state is `.ready` (cold start).
    case `defer`
}

/// The one receiver of incoming URLs (spec §4 Phase 4, D15). It holds no UI state: the code lives in
/// `PendingInviteStore`, which it writes before anything else, and every screen that shows the code
/// re-reads the store on `PendingInviteStore.didChange`. The code is never logged and never sent
/// anywhere from here; only the join sheet validates or redeems it, after the person sees it.
@MainActor
final class IncomingLinkHandler {
    static let shared = IncomingLinkHandler()

    private let store: PendingInviteStore
    private let coordinator: NavigationCoordinator
    private let launchState: @MainActor () -> LaunchState
    /// A link that arrived before the launch state was `.ready`; decided once, on the first `.ready`.
    private var hasDeferredLink = false

    /// `coordinator` nil means `NavigationCoordinator.shared`, resolved here on the main actor (a
    /// `.shared` default argument would be read from a nonisolated context).
    init(
        store: PendingInviteStore = PendingInviteStore(),
        coordinator: NavigationCoordinator? = nil,
        launchState: @escaping @MainActor () -> LaunchState = { AppLaunchManager.shared.state }
    ) {
        self.store = store
        self.coordinator = coordinator ?? .shared
        self.launchState = launchState
    }

    /// Returns what was done; a URL that is not a join link is ignored and nothing is saved.
    @discardableResult
    func handle(_ url: URL) -> IncomingLinkDecision? {
        guard case .joinCommunity(let code) = DeepLinkParser.parse(url: url) else {
            AppLogger.info("navigation", "Ignoring an incoming URL that is not a join link")
            return nil
        }
        // Save first: whatever happens next (a sheet that never presents, a relaunch), the code is kept.
        store.save(code)
        let decision = Self.decision(for: launchState())
        switch decision {
        case .route:
            hasDeferredLink = false
            coordinator.applyExternalDeepLink(.joinCommunity(code: code))
        case .saveOnly:
            hasDeferredLink = false
        case .defer:
            hasDeferredLink = true
        }
        AppLogger.info("navigation", "Incoming join link saved: \(decision)")
        return decision
    }

    /// ContentView calls this on every launch-state change; a deferred link is decided once, on the first `.ready`.
    func launchStateDidChange(_ state: LaunchState) {
        guard hasDeferredLink else { return }
        let decision = Self.replayDecision(for: state)
        guard decision != .defer else { return }
        hasDeferredLink = false
        AppLogger.info("navigation", "Deferred join link decided: \(decision)")
        // The store is the single holder: a code removed meanwhile is not routed.
        guard decision == .route, let code = store.peek() else { return }
        coordinator.applyExternalDeepLink(.joinCommunity(code: code))
    }

    /// Pure: first sight of a link.
    static func decision(for state: LaunchState) -> IncomingLinkDecision {
        switch state {
        case .ready(.authenticated), .ready(.guest):
            return .route
        case .ready:
            return .saveOnly
        case .initializing, .checkingAuth, .failed:
            return .defer
        }
    }

    /// Pure: a deferred link at the first `.ready`. Authenticated → `.saveOnly`, because
    /// `offerPendingInviteIfNeeded` opens My communities from the store on MainTabView's first
    /// appearance; routing as well would navigate twice.
    static func replayDecision(for state: LaunchState) -> IncomingLinkDecision {
        switch state {
        case .ready(.guest):
            return .route
        case .ready:
            return .saveOnly
        case .initializing, .checkingAuth, .failed:
            return .defer
        }
    }
}
