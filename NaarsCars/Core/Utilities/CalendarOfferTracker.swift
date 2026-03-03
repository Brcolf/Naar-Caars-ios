//
//  CalendarOfferTracker.swift
//  NaarsCars
//
//  Tracks calendar event offer state per request to limit prompts
//

import Foundation

/// Tracks how many times a user has been offered to add a request to their calendar,
/// and whether they accepted. Persists via UserDefaults.
final class CalendarOfferTracker {

    static let shared = CalendarOfferTracker()

    private let defaults = UserDefaults.standard
    private let storageKey = "calendarOfferState"
    private let maxDismissals = 2

    private init() {}

    // MARK: - State

    private struct OfferState: Codable {
        var dismissCount: Int = 0
        var eventCreated: Bool = false
    }

    private func key(requestType: String, requestId: UUID) -> String {
        "\(requestType)_\(requestId.uuidString)"
    }

    private func loadState() -> [String: OfferState] {
        guard let data = defaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode([String: OfferState].self, from: data) else {
            return [:]
        }
        return state
    }

    private func saveState(_ state: [String: OfferState]) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: - Public API

    /// Whether we should offer the calendar event for this request
    func shouldOffer(requestType: String, requestId: UUID) -> Bool {
        let k = key(requestType: requestType, requestId: requestId)
        let allState = loadState()
        guard let state = allState[k] else { return true } // Never offered
        return !state.eventCreated && state.dismissCount < maxDismissals
    }

    /// Record that the user dismissed the calendar offer
    func recordDismissal(requestType: String, requestId: UUID) {
        let k = key(requestType: requestType, requestId: requestId)
        var allState = loadState()
        var state = allState[k] ?? OfferState()
        state.dismissCount += 1
        allState[k] = state
        saveState(allState)
    }

    /// Record that the user created the calendar event
    func recordEventCreated(requestType: String, requestId: UUID) {
        let k = key(requestType: requestType, requestId: requestId)
        var allState = loadState()
        var state = allState[k] ?? OfferState()
        state.eventCreated = true
        allState[k] = state
        saveState(allState)
    }

    /// Check if an event was already created for this request
    func eventAlreadyCreated(requestType: String, requestId: UUID) -> Bool {
        let k = key(requestType: requestType, requestId: requestId)
        return loadState()[k]?.eventCreated ?? false
    }
}
