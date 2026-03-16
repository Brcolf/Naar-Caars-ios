//
//  DashboardPayloadMapper.swift
//  NaarsCars
//
//  Maps Supabase realtime payloads (RealtimeRecord) into Ride/Favor model
//  objects for incremental local upserts, avoiding a full network refetch.
//

import Foundation

enum DashboardPayloadMapper {

    // MARK: - Public API

    /// Parse a Ride from a realtime record. Returns nil if required fields are missing.
    static func ride(from record: RealtimeRecord) -> Ride? {
        let dict = record.record
        guard let id = uuid(dict, "id"),
              let userId = uuid(dict, "user_id"),
              let type = string(dict, "type"),
              let rideDate = date(dict, "date"),
              let time = string(dict, "time"),
              let timezone = string(dict, "timezone"),
              let pickup = string(dict, "pickup"),
              let destination = string(dict, "destination"),
              let seats = int(dict, "seats"),
              let statusRaw = string(dict, "status"),
              let status = RideStatus(rawValue: statusRaw),
              let createdAt = date(dict, "created_at"),
              let updatedAt = date(dict, "updated_at") else {
            return nil
        }

        return Ride(
            id: id,
            userId: userId,
            type: type,
            date: rideDate,
            time: time,
            timezone: timezone,
            pickup: pickup,
            destination: destination,
            seats: seats,
            notes: string(dict, "notes"),
            gift: string(dict, "gift"),
            status: status,
            claimedBy: uuid(dict, "claimed_by"),
            reviewed: bool(dict, "reviewed") ?? false,
            reviewSkipped: bool(dict, "review_skipped"),
            reviewSkippedAt: date(dict, "review_skipped_at"),
            estimatedCost: double(dict, "estimated_cost"),
            flightNormalized: string(dict, "flight_normalized"),
            createdAt: createdAt,
            updatedAt: updatedAt
            // poster, claimer, participants, qaCount are not in realtime payloads
        )
    }

    /// Parse a Favor from a realtime record. Returns nil if required fields are missing.
    static func favor(from record: RealtimeRecord) -> Favor? {
        let dict = record.record
        guard let id = uuid(dict, "id"),
              let userId = uuid(dict, "user_id"),
              let title = string(dict, "title"),
              let location = string(dict, "location"),
              let durationRaw = string(dict, "duration"),
              let duration = FavorDuration(rawValue: durationRaw),
              let favorDate = date(dict, "date"),
              let timezone = string(dict, "timezone"),
              let statusRaw = string(dict, "status"),
              let status = FavorStatus(rawValue: statusRaw),
              let createdAt = date(dict, "created_at"),
              let updatedAt = date(dict, "updated_at") else {
            return nil
        }

        return Favor(
            id: id,
            userId: userId,
            title: title,
            description: string(dict, "description"),
            location: location,
            duration: duration,
            requirements: string(dict, "requirements"),
            date: favorDate,
            time: string(dict, "time"),
            timezone: timezone,
            gift: string(dict, "gift"),
            status: status,
            claimedBy: uuid(dict, "claimed_by"),
            reviewed: bool(dict, "reviewed") ?? false,
            reviewSkipped: bool(dict, "review_skipped"),
            reviewSkippedAt: date(dict, "review_skipped_at"),
            createdAt: createdAt,
            updatedAt: updatedAt
            // poster, claimer, participants, qaCount are not in realtime payloads
        )
    }

    // MARK: - Extraction Helpers

    private static func string(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }

    private static func uuid(_ dict: [String: Any], _ key: String) -> UUID? {
        guard let str = dict[key] as? String else { return nil }
        return UUID(uuidString: str)
    }

    private static func int(_ dict: [String: Any], _ key: String) -> Int? {
        if let v = dict[key] as? Int { return v }
        if let v = dict[key] as? Double { return Int(v) }
        if let v = dict[key] as? String, let parsed = Int(v) { return parsed }
        return nil
    }

    private static func double(_ dict: [String: Any], _ key: String) -> Double? {
        if let v = dict[key] as? Double { return v }
        if let v = dict[key] as? Int { return Double(v) }
        if let v = dict[key] as? String, let parsed = Double(v) { return parsed }
        return nil
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

    /// ISO8601 formatter with fractional seconds (matches Supabase TIMESTAMPTZ output).
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO8601 formatter without fractional seconds.
    private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Plain date formatter for DATE columns (YYYY-MM-DD).
    private static let plainDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func date(_ dict: [String: Any], _ key: String) -> Date? {
        guard let str = dict[key] as? String else { return nil }
        if let d = isoFractional.date(from: str) { return d }
        if let d = isoStandard.date(from: str) { return d }
        if let d = plainDate.date(from: str) { return d }
        return nil
    }
}
