//
//  PromptSideEffects.swift
//  NaarsCars
//
//  Real implementation of PromptSideEffects protocol
//

import Foundation
import Supabase

@MainActor
final class DefaultPromptSideEffects: PromptSideEffects {
    private let notificationService = NotificationService.shared
    private let badgeManager = BadgeCountManager.shared
    private let supabase = SupabaseService.shared.client

    func markReviewNotificationsRead(requestType: RequestType, requestId: UUID) async {
        await notificationService.markReviewRequestAsRead(
            requestType: requestType.rawValue,
            requestId: requestId
        )
    }

    func markCompletionNotificationsRead(requestType: RequestType, requestId: UUID) async {
        _ = await notificationService.markRequestScopedRead(
            requestType: requestType.rawValue,
            requestId: requestId,
            notificationTypes: [.completionReminder]
        )
    }

    func refreshBadges(reason: String) async {
        await badgeManager.refreshAllBadges(reason: reason)
    }

    func sendCompletionResponse(reminderId: UUID, completed: Bool) async throws {
        let params: [String: AnyCodable] = [
            "p_reminder_id": AnyCodable(reminderId.uuidString),
            "p_completed": AnyCodable(completed)
        ]
        _ = try await supabase
            .rpc("handle_completion_response", params: params)
            .execute()
    }
}
