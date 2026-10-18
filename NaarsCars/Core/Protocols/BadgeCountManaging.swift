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
}
