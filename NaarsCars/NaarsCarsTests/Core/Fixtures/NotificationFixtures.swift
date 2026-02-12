//
//  NotificationFixtures.swift
//  NaarsCars
//
//  Fixture data for notification type contract tests
//

import Foundation

enum NotificationFixtures {
    static let allRawValues: [String] = [
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

    static let mandatoryTypes: Set<String> = [
        "new_ride",
        "new_favor",
        "announcement",
        "admin_announcement",
        "broadcast",
        "pending_approval",
        "user_approved",
        "user_rejected"
    ]

    static let preferenceMapping: [String: String?] = [
        "message": "notifyMessages",
        "added_to_conversation": "notifyMessages",
        "new_ride": nil,
        "ride_update": "notifyRideUpdates",
        "ride_claimed": "notifyRideUpdates",
        "ride_unclaimed": "notifyRideUpdates",
        "ride_completed": "notifyRideUpdates",
        "new_favor": nil,
        "favor_update": "notifyRideUpdates",
        "favor_claimed": "notifyRideUpdates",
        "favor_unclaimed": "notifyRideUpdates",
        "favor_completed": "notifyRideUpdates",
        "completion_reminder": "notifyReviewReminders",
        "qa_activity": "notifyQaActivity",
        "qa_question": "notifyQaActivity",
        "qa_answer": "notifyQaActivity",
        "review": "notifyReviewReminders",
        "review_received": "notifyReviewReminders",
        "review_reminder": "notifyReviewReminders",
        "review_request": "notifyReviewReminders",
        "town_hall_post": "notifyTownHall",
        "town_hall_comment": "notifyTownHall",
        "town_hall_reaction": "notifyTownHall",
        "announcement": nil,
        "admin_announcement": nil,
        "broadcast": nil,
        "pending_approval": nil,
        "user_approved": nil,
        "user_rejected": nil,
        "other": nil
    ]
}
