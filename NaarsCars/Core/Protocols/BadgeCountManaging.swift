//
//  BadgeCountManaging.swift
//  NaarsCars
//

import Foundation

protocol BadgeCountManaging: AnyObject {
    func refreshAllBadges(reason: String) async
    func clearMessagesBadge(for conversationId: UUID?) async
    func clearCommunityBadge(visibleCommunityId: UUID?) async
    func fetchBadgeCountsPayload(includeDetails: Bool) async throws -> String
    /// The bell badge from the last `get_badge_counts` (`bell_total`: unread groups, grouped as the
    /// bell list groups them). Read only; nothing on the client recomputes it.
    @MainActor var bellBadgeCount: Int { get }
}
