//
//  ReviewService+Prompt.swift
//  NaarsCars
//
//  Extension for review prompt logic
//

import Foundation

extension ReviewService {
    
    /// Find requests that need review prompts (30 minutes after request time)
    /// - Parameter userId: User ID of the poster
    /// - Returns: Array of (requestType, requestId, requestTitle, fulfillerId, fulfillerName) tuples
    func findPendingReviewPrompts(userId: UUID) async throws -> [(requestType: String, requestId: UUID, requestTitle: String, fulfillerId: UUID, fulfillerName: String)] {
        let rideService = RideService.shared
        let favorService = FavorService.shared
        let profileService = ProfileService.shared
        
        var pendingPrompts: [(requestType: String, requestId: UUID, requestTitle: String, fulfillerId: UUID, fulfillerName: String)] = []
        
        // Fetch completed rides posted by user
        let completedRides = try await rideService.fetchRides(userId: userId)
            .filter { $0.status == .completed && $0.claimedBy != nil && !$0.reviewed && ($0.reviewSkipped == nil || $0.reviewSkipped == false) }
        
        // Fetch completed favors posted by user
        let completedFavors = try await favorService.fetchFavors(userId: userId)
            .filter { $0.status == .completed && $0.claimedBy != nil && !$0.reviewed && ($0.reviewSkipped == nil || $0.reviewSkipped == false) }
        
        let now = Date()
        let thirtyMinutesInSeconds: TimeInterval = 30 * 60
        
        // Check rides
        for ride in completedRides {
            // Calculate event time (date + time)
            guard let eventTime = combineDateAndTime(date: ride.date, time: ride.time) else {
                continue
            }
            
            // Check if 30 minutes have passed since event time
            let timeSinceEvent = now.timeIntervalSince(eventTime)
            guard timeSinceEvent >= thirtyMinutesInSeconds else {
                continue
            }
            
            // Check if can still review (within 7 days)
            guard try await canStillReview(requestType: "ride", requestId: ride.id) else {
                continue
            }
            
            // Get fulfiller profile
            guard let fulfillerId = ride.claimedBy else { continue }
            let fulfillerProfile = try? await profileService.fetchProfile(userId: fulfillerId)
            let fulfillerName = fulfillerProfile?.name ?? "Someone"
            
            let requestTitle = "\(ride.pickup) → \(ride.destination)"
            
            pendingPrompts.append((
                requestType: "ride",
                requestId: ride.id,
                requestTitle: requestTitle,
                fulfillerId: fulfillerId,
                fulfillerName: fulfillerName
            ))
        }
        
        // Check favors
        for favor in completedFavors {
            // Calculate event time (date + time if available, else just date)
            let eventTime: Date
            if let time = favor.time, let combinedTime = combineDateAndTime(date: favor.date, time: time) {
                eventTime = combinedTime
            } else {
                eventTime = favor.date
            }
            
            // Check if 30 minutes have passed since event time
            let timeSinceEvent = now.timeIntervalSince(eventTime)
            guard timeSinceEvent >= thirtyMinutesInSeconds else {
                continue
            }
            
            // Check if can still review (within 7 days) - skip check for now since we're checking 30 min after event time
            // The 7-day window is for past requests, not for the 30-minute prompt
            // guard try await reviewService.canStillReview(requestType: "favor", requestId: favor.id) else {
            //     continue
            // }
            
            // Get fulfiller profile
            guard let fulfillerId = favor.claimedBy else { continue }
            let fulfillerProfile = try? await profileService.fetchProfile(userId: fulfillerId)
            let fulfillerName = fulfillerProfile?.name ?? "Someone"
            
            let requestTitle = favor.title
            
            pendingPrompts.append((
                requestType: "favor",
                requestId: favor.id,
                requestTitle: requestTitle,
                fulfillerId: fulfillerId,
                fulfillerName: fulfillerName
            ))
        }
        
        // Sort by event time (oldest first - show earliest prompts first)
        // Note: We can't easily sort without recalculating event times, so just return in order
        return pendingPrompts
    }
    
    /// Combine date and time string into a Date
    /// - Parameters:
    ///   - date: Date component
    ///   - time: Time string (format: "HH:mm:ss" or "HH:mm")
    /// - Returns: Combined Date, or nil if parsing fails
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
}

