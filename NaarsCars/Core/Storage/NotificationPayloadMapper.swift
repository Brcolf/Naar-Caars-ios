//
//  NotificationPayloadMapper.swift
//  NaarsCars
//
//  Maps Supabase realtime payloads (RealtimeRecord) into AppNotification
//  model objects for incremental local upserts, avoiding a full network refetch.
//

import Foundation

enum NotificationPayloadMapper {

    // MARK: - Public API

    /// Parse an AppNotification from a realtime record.
    /// Returns nil if required fields are missing.
    static func notification(from record: RealtimeRecord) -> AppNotification? {
        let dict = record.record
        guard let id = uuid(dict, "id"),
              let userId = uuid(dict, "user_id"),
              let typeRaw = string(dict, "type"),
              let type = NotificationType(rawValue: typeRaw),
              let title = string(dict, "title"),
              let createdAt = date(dict, "created_at") else {
            return nil
        }

        return AppNotification(
            id: id,
            userId: userId,
            type: type,
            title: title,
            body: string(dict, "body"),
            read: bool(dict, "read") ?? false,
            pinned: bool(dict, "pinned") ?? false,
            createdAt: createdAt,
            rideId: uuid(dict, "ride_id"),
            favorId: uuid(dict, "favor_id"),
            conversationId: uuid(dict, "conversation_id"),
            reviewId: uuid(dict, "review_id"),
            townHallPostId: uuid(dict, "town_hall_post_id"),
            sourceUserId: uuid(dict, "source_user_id")
        )
    }

    /// Extract the notification ID from a delete event's old record.
    static func notificationId(fromDeleteEvent record: RealtimeRecord) -> UUID? {
        let dict = record.oldRecord ?? record.record
        return uuid(dict, "id")
    }

    // MARK: - Extraction Helpers (shared with DashboardPayloadMapper)

    private static func string(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }

    private static func uuid(_ dict: [String: Any], _ key: String) -> UUID? {
        guard let str = dict[key] as? String else { return nil }
        return UUID(uuidString: str)
    }

    private static func bool(_ dict: [String: Any], _ key: String) -> Bool? {
        if let v = dict[key] as? Bool { return v }
        if let v = dict[key] as? Int { return v != 0 }
        if let v = dict[key] as? String {
            switch v.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    // MARK: - Date Parsing

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func date(_ dict: [String: Any], _ key: String) -> Date? {
        guard let str = dict[key] as? String else { return nil }
        if let d = isoFractional.date(from: str) { return d }
        if let d = isoStandard.date(from: str) { return d }
        return nil
    }
}
