//
//  BadgeCountManaging.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol BadgeCountManaging: AnyObject {
    func refreshAllBadges(reason: String) async
    func clearMessagesBadge(for conversationId: UUID?) async
    func clearCommunityBadge() async
    func fetchBadgeCountsPayload(includeDetails: Bool) async throws -> String
}
