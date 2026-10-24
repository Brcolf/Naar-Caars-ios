//
//  ViewedCommunityStore.swift
//  NaarsCars
//
//  The listed community a guest last looked at, offered on Get started after sign-up
//

import Foundation

/// A community page a guest opened (id, name and join policy as the preview gave them).
struct ViewedCommunity: Codable, Equatable {
    let id: UUID
    let name: String
    let joinPolicy: String
    let savedAt: Date
}

/// Keeps one viewed community on this device (spec S8: Get started "remembers the community a guest
/// was viewing").
/// Written by `CommunityPageViewModel` when a guest lands on a listed community's preview; read by
/// `CommunityOnboardingViewModel`; dropped after `Constants.Community.viewedCommunityLifetime`,
/// after a join from Get started, and on sign-out (`AuthService.clearPerAccountLocalState`).
/// Holds only what the public preview showed. Reads and writes never throw: an unreadable value
/// reads as nothing and is removed.
final class ViewedCommunityStore {
    static let key = "explore.viewedCommunity"

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// Replaces any community saved before with this one, stamped now.
    func save(id: UUID, name: String, joinPolicy: String) {
        let viewed = ViewedCommunity(id: id, name: name, joinPolicy: joinPolicy, savedAt: now())
        guard let data = try? JSONEncoder().encode(viewed) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// The saved community, or nil. One older than the lifetime (or unreadable) is removed.
    func peek() -> ViewedCommunity? {
        guard let data = defaults.data(forKey: Self.key) else {
            if defaults.object(forKey: Self.key) != nil { clear() }
            return nil
        }
        guard let viewed = try? JSONDecoder().decode(ViewedCommunity.self, from: data),
              now().timeIntervalSince(viewed.savedAt) <= Constants.Community.viewedCommunityLifetime else {
            clear()
            return nil
        }
        return viewed
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
