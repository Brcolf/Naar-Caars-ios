//
//  RequestItem.swift
//  NaarsCars
//
//  Unified type for representing both Ride and Favor requests
//

import Foundation

/// Unified request type that can represent either a Ride or Favor
enum RequestItem: Identifiable, Equatable {
    case ride(Ride)
    case favor(Favor)
    
    var id: UUID {
        switch self {
        case .ride(let ride):
            return ride.id
        case .favor(let favor):
            return favor.id
        }
    }

    var notificationKey: String {
        switch self {
        case .ride(let ride):
            return "ride:\(ride.id)"
        case .favor(let favor):
            return "favor:\(favor.id)"
        }
    }
    
    var userId: UUID {
        switch self {
        case .ride(let ride):
            return ride.userId
        case .favor(let favor):
            return favor.userId
        }
    }
    
    var claimedBy: UUID? {
        switch self {
        case .ride(let ride):
            return ride.claimedBy
        case .favor(let favor):
            return favor.claimedBy
        }
    }
    
    var status: RequestStatus {
        switch self {
        case .ride(let ride):
            return RequestStatus.fromRideStatus(ride.status)
        case .favor(let favor):
            return RequestStatus.fromFavorStatus(favor.status)
        }
    }
    
    /// The request's timezone
    var timeZone: TimeZone {
        switch self {
        case .ride(let ride): return ride.timeZone
        case .favor(let favor): return favor.timeZone
        }
    }

    /// Event time for sorting (combines date + time using stored timezone)
    var eventTime: Date {
        switch self {
        case .ride(let ride):
            return combineDateAndTime(date: ride.date, time: ride.time, timeZone: ride.timeZone) ?? ride.date
        case .favor(let favor):
            // A favor without a time starts at midnight in its own zone, the same rule the
            // server's expiry job uses (20261005_0010).
            return combineDateAndTime(date: favor.date, time: favor.time ?? "00:00:00", timeZone: favor.timeZone) ?? favor.date
        }
    }

    /// When the request's window closes: its event time, or for a favor with no time the end
    /// of its day. The "12 hours past" visibility rule and upcoming/past ordering count from
    /// here, so a favor posted for "today" is not treated as over at 12:01 AM (it used to drop
    /// below tomorrow's requests and vanish from every list at noon). The server's expiry job
    /// uses the same rule (20261006_0004).
    var windowEnd: Date {
        if case .favor(let favor) = self, favor.time == nil {
            return eventTime.addingTimeInterval(24 * 60 * 60)
        }
        return eventTime
    }

    /// Combine date and time string into a Date using the request's timezone
    private func combineDateAndTime(date: Date, time: String, timeZone: TimeZone) -> Date? {
        // The DATE column is decoded as midnight in the device's zone (DateDecoderFactory), so
        // the calendar day has to be read back in that same zone. Reading it in the request's
        // zone put the event a day early on a phone east of the request (New York phone,
        // Pacific request). The instant is then built in the request's own zone.
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = .current
        let dateComponents = deviceCalendar.dateComponents([.year, .month, .day], from: date)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        // Parse time string (format: "HH:mm:ss" or "HH:mm")
        let timeParts = time.split(separator: ":")
        guard timeParts.count >= 2,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]) else {
            return nil
        }

        var components = DateComponents()
        components.year = dateComponents.year
        components.month = dateComponents.month
        components.day = dateComponents.day
        components.hour = hour
        components.minute = minute
        components.second = timeParts.count > 2 ? Int(timeParts[2]) : 0
        components.timeZone = timeZone

        return calendar.date(from: components)
    }
    
    var isCompleted: Bool {
        switch self {
        case .ride(let ride):
            return ride.status == .completed
        case .favor(let favor):
            return favor.status == .completed
        }
    }
    
    /// Check if a user is participating in this request (is poster OR in participants array)
    func isParticipating(userId: UUID) -> Bool {
        // Check if user is the poster
        if self.userId == userId {
            return true
        }
        
        // Check if user is in participants array
        switch self {
        case .ride(let ride):
            return ride.participants?.contains(where: { $0.id == userId }) ?? false
        case .favor(let favor):
            return favor.participants?.contains(where: { $0.id == userId }) ?? false
        }
    }
    
    /// Check if request is unclaimed (claimedBy is nil)
    var isUnclaimed: Bool {
        return claimedBy == nil
    }
    
    static func == (lhs: RequestItem, rhs: RequestItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Unified status type for requests
enum RequestStatus: Equatable {
    case open
    case pending
    case confirmed
    case completed
    
    static func fromRideStatus(_ status: RideStatus) -> RequestStatus {
        switch status {
        case .open: return .open
        case .pending: return .pending
        case .confirmed: return .confirmed
        case .completed: return .completed
        }
    }
    
    static func fromFavorStatus(_ status: FavorStatus) -> RequestStatus {
        switch status {
        case .open: return .open
        case .pending: return .pending
        case .confirmed: return .confirmed
        case .completed: return .completed
        }
    }
}

