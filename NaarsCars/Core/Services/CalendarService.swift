//
//  CalendarService.swift
//  NaarsCars
//
//  Service for EventKit calendar operations
//

import EventKit
import Foundation

/// Service for creating calendar events from confirmed requests
/// Note: @MainActor is implicit via SWIFT_DEFAULT_ACTOR_ISOLATION build setting.
/// EventKit save() is synchronous but only runs on user-initiated actions (< 5ms typical).
final class CalendarService {

    static let shared = CalendarService()

    private let eventStore = EKEventStore()

    private init() {}

    /// Request calendar access. Returns true if granted.
    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                AppLogger.error("calendar", "Failed to request calendar access: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error {
                        AppLogger.error("calendar", "Failed to request calendar access: \(error)")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Check if calendar access is currently authorized
    var hasAccess: Bool {
        if #available(iOS 17.0, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        } else {
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }

    /// Create a calendar event for a ride request
    /// - Returns: The event identifier if created successfully
    func createEvent(
        title: String,
        location: String?,
        startDate: Date,
        endDate: Date?,
        notes: String?
    ) async -> String? {
        // Request access if not already granted
        let granted = hasAccess ? true : await requestAccess()
        guard granted else {
            AppLogger.info("calendar", "Calendar access denied")
            return nil
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            AppLogger.error("calendar", "No default calendar available")
            return nil
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.location = location
        event.startDate = startDate
        event.endDate = endDate ?? startDate.addingTimeInterval(3600) // Default 1 hour
        event.notes = notes
        event.calendar = calendar

        // Add 1-hour reminder
        let alarm = EKAlarm(relativeOffset: -3600)
        event.addAlarm(alarm)

        do {
            try eventStore.save(event, span: .thisEvent)
            AppLogger.info("calendar", "Calendar event created: \(event.eventIdentifier ?? "unknown")")
            return event.eventIdentifier
        } catch {
            AppLogger.error("calendar", "Failed to create calendar event: \(error)")
            return nil
        }
    }

    /// Create a calendar event from a Ride
    func createEventForRide(_ ride: Ride) async -> String? {
        let eventTime = RequestItem.ride(ride).eventTime
        return await createEvent(
            title: "Ride: \(ride.pickup) → \(ride.destination)",
            location: ride.pickup,
            startDate: eventTime,
            endDate: nil,
            notes: ride.notes
        )
    }

    /// Create a calendar event from a Favor
    func createEventForFavor(_ favor: Favor) async -> String? {
        let eventTime = RequestItem.favor(favor).eventTime
        let durationInterval: TimeInterval = {
            switch favor.duration {
            case .underHour: return 3600
            case .coupleHours: return 7200
            case .coupleDays: return 86400
            case .notSure: return 3600
            }
        }()
        return await createEvent(
            title: "Favor: \(favor.title)",
            location: favor.location,
            startDate: eventTime,
            endDate: eventTime.addingTimeInterval(durationInterval),
            notes: favor.description
        )
    }

    /// Create a calendar event from push notification data (when user taps "Add to Calendar" action)
    func createEventFromPushData(_ userInfo: [AnyHashable: Any]) async -> String? {
        guard let title = userInfo["event_title"] as? String,
              let dateString = userInfo["event_date"] as? String else {
            AppLogger.error("calendar", "Missing event data in push payload")
            return nil
        }

        let formatter = ISO8601DateFormatter()
        guard let startDate = formatter.date(from: dateString) else {
            AppLogger.error("calendar", "Invalid event date in push payload: \(dateString)")
            return nil
        }

        let location = userInfo["event_location"] as? String
        let notes = userInfo["event_notes"] as? String

        return await createEvent(
            title: title,
            location: location,
            startDate: startDate,
            endDate: nil,
            notes: notes
        )
    }
}
