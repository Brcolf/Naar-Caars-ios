//
//  NotificationTypeRegistry.swift
//  NaarsCars
//
//  Canonical notification type registry and debug validation.
//

import Foundation

/// Canonical list of notification type raw values used across Swift, SQL, and edge functions.
enum NotificationTypeRegistry {
    static let allTypes: Set<String> = [
        "message",
        "added_to_conversation",
        "new_ride",
        "ride_update",
        "ride_claimed",
        "ride_unclaimed",
        "ride_completed",
        "new_favor",
        "favor_update",
        "favor_claimed",
        "favor_unclaimed",
        "favor_completed",
        "completion_reminder",
        "qa_activity",
        "qa_question",
        "qa_answer",
        "review",
        "review_received",
        "review_reminder",
        "review_request",
        "town_hall_post",
        "town_hall_comment",
        "town_hall_reaction",
        "announcement",
        "admin_announcement",
        "broadcast",
        "pending_approval",
        "user_approved",
        "user_rejected",
        "other"
    ]

    #if DEBUG
    static func validateRegistry() {
        let enumCases = Set(NotificationType.allCases.map(\.rawValue))
        assert(
            enumCases == allTypes,
            """
            NotificationType enum (\(enumCases.count) cases) and registry (\(allTypes.count) types) are out of sync.
            Missing from registry: \(enumCases.subtracting(allTypes)).
            Missing from enum: \(allTypes.subtracting(enumCases)).
            """
        )
    }
    #endif
}
