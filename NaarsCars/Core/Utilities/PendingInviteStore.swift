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
struct PendingInviteStore {
    static let codeKey = "community.pendingInviteCode"
    static let savedAtKey = "community.pendingInviteSavedAt"

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// Stores the normalized form of `raw` and the time it was saved.
    func save(_ raw: String) {
        let normalized = CommunityInviteCode.normalize(raw)
        guard !normalized.isEmpty else { return }
        defaults.set(normalized, forKey: Self.codeKey)
        defaults.set(now(), forKey: Self.savedAtKey)
    }

    /// The stored code, or nil. A code older than the lifetime (or with no save time) is removed.
    func peek() -> String? {
        guard let code = defaults.string(forKey: Self.codeKey), !code.isEmpty else {
            if defaults.object(forKey: Self.savedAtKey) != nil { clear() }
            return nil
        }
        guard let savedAt = defaults.object(forKey: Self.savedAtKey) as? Date,
              now().timeIntervalSince(savedAt) <= Constants.Community.pendingInviteLifetime else {
            clear()
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
        defaults.removeObject(forKey: Self.codeKey)
        defaults.removeObject(forKey: Self.savedAtKey)
    }
}
