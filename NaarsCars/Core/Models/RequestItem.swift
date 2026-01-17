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
    
    /// Event time for sorting (combines date + time)
    var eventTime: Date {
        switch self {
        case .ride(let ride):
            return combineDateAndTime(date: ride.date, time: ride.time) ?? ride.date
        case .favor(let favor):
            if let time = favor.time {
                return combineDateAndTime(date: favor.date, time: time) ?? favor.date
            }
            return favor.date
        }
    }
    
    /// Combine date and time string into a Date
    private func combineDateAndTime(date: Date, time: String) -> Date? {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        
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

