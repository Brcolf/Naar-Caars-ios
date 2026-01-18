//
//  RideService.swift
//  NaarsCars
//
//  Service for ride-related operations with caching
//

import Foundation
import Supabase

/// Service for ride-related operations
/// Handles fetching, creating, updating, deleting rides, and Q&A operations
@MainActor
final class RideService {
    
    // MARK: - Singleton
    
    static let shared = RideService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let cacheManager = CacheManager.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Ride Fetching
    
    /// Fetch rides with optional filters
    /// Checks cache first, then fetches from network if needed
    /// - Parameters:
    ///   - status: Optional status filter
    ///   - userId: Optional user ID filter (rides posted by this user)
    ///   - claimedBy: Optional claimed by filter (rides claimed by this user)
    /// - Returns: Array of rides ordered by date ascending
    /// - Throws: AppError if fetch fails
    func fetchRides(
        status: RideStatus? = nil,
        userId: UUID? = nil,
        claimedBy: UUID? = nil
    ) async throws -> [Ride] {
        // Check cache first
        if let cachedRides = await cacheManager.getCachedRides() {
            // Apply filters to cached data
            var filtered = cachedRides
            
            if let status = status {
                filtered = filtered.filter { $0.status == status }
            }
            if let userId = userId {
                filtered = filtered.filter { $0.userId == userId }
            }
            if let claimedBy = claimedBy {
                filtered = filtered.filter { $0.claimedBy == claimedBy }
            }
            
            // If cache hit and we have results, return cached data
            if !filtered.isEmpty {
                return filtered.sorted { $0.date < $1.date }
            }
        }
        
        // Build query
        var query = supabase
            .from("rides")
            .select()
        
        // Apply filters
        if let status = status {
            query = query.eq("status", value: status.rawValue)
        }
        if let userId = userId {
            query = query.eq("user_id", value: userId.uuidString)
        }
        if let claimedBy = claimedBy {
            query = query.eq("claimed_by", value: claimedBy.uuidString)
        }
        
        // Execute query
        let response = try await query
            .order("date", ascending: true)
            .execute()
        
        // Decode rides with custom date decoder
        let rides: [Ride] = try createDecoder().decode([Ride].self, from: response.data)
        
        // Enrich with profiles
        let enrichedRides = await enrichRidesWithProfiles(rides)
        
        // Cache results
        await cacheManager.cacheRides(enrichedRides)
        
        return enrichedRides
    }
    
    /// Fetch a single ride by ID with all related data
    /// - Parameter id: Ride ID
    /// - Returns: Ride with poster, claimer, participants, and qaCount populated
    /// - Throws: AppError if fetch fails
    func fetchRide(id: UUID) async throws -> Ride {
        // Fetch ride
        let response = try await supabase
            .from("rides")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
        
        var ride: Ride = try createDecoder().decode(Ride.self, from: response.data)
        
        // Enrich with profiles
        ride = await enrichRideWithProfiles(ride)
        
        // Fetch Q&A count
        let qaCount = try await fetchQACount(requestId: id, requestType: "ride")
        ride.qaCount = qaCount
        
        return ride
    }
    
    // MARK: - Ride Creation
    
    /// Create a new ride request
    /// - Parameters:
    ///   - userId: User ID of the poster
    ///   - date: Ride date
    ///   - time: Ride time (formatted as "HH:mm:ss")
    ///   - pickup: Pickup location
    ///   - destination: Destination location
    ///   - seats: Number of seats (default: 1)
    ///   - notes: Optional notes
    ///   - gift: Optional gift/compensation
    /// - Returns: Created ride
    /// - Throws: AppError if creation fails
    func createRide(
        userId: UUID,
        date: Date,
        time: String,
        pickup: String,
        destination: String,
        seats: Int = 1,
        notes: String? = nil,
        gift: String? = nil
    ) async throws -> Ride {
        // Format date as "yyyy-MM-dd"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        // Create ride data
        let rideData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId.uuidString),
            "type": AnyCodable("request"),
            "date": AnyCodable(dateString),
            "time": AnyCodable(time),
            "pickup": AnyCodable(pickup),
            "destination": AnyCodable(destination),
            "seats": AnyCodable(seats),
            "notes": AnyCodable(notes),
            "gift": AnyCodable(gift),
            "status": AnyCodable("open")
        ]
        
        // Insert ride
        let response = try await supabase
            .from("rides")
            .insert(rideData)
            .select()
            .single()
            .execute()
        
        let ride: Ride = try createDecoder().decode(Ride.self, from: response.data)
        
        // Invalidate cache
        await cacheManager.invalidateRides()
        
        // Calculate and save estimated cost asynchronously (don't block ride creation)
        Task.detached {
            await self.calculateAndSaveEstimatedCost(for: ride)
        }
        
        return ride
    }
    
    /// Calculate and save estimated cost for a ride (asynchronous, non-blocking)
    /// - Parameter ride: The ride to calculate cost for
    private func calculateAndSaveEstimatedCost(for ride: Ride) async {
        do {
            // Calculate cost using route calculation
            guard let estimatedCost = await RideCostEstimator.estimateCost(
                pickup: ride.pickup,
                destination: ride.destination
            ) else {
                // If calculation fails, just log and return (ride is still created)
                print("⚠️ [RideService] Failed to calculate estimated cost for ride \(ride.id)")
                return
            }
            
            // Update the ride with calculated cost
            let updateData: [String: AnyCodable] = [
                "estimated_cost": AnyCodable(estimatedCost)
            ]
            
            try await supabase
                .from("rides")
                .update(updateData)
                .eq("id", value: ride.id.uuidString)
                .execute()
            
            print("✅ [RideService] Calculated and saved estimated cost: $\(String(format: "%.2f", estimatedCost)) for ride \(ride.id)")
            
            // Invalidate cache so the updated ride is fetched next time
            await cacheManager.invalidateRides()
            
        } catch {
            // If update fails, just log (ride is still created)
            print("⚠️ [RideService] Failed to save estimated cost for ride \(ride.id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Ride Updates
    
    /// Update an existing ride
    /// - Parameters:
    ///   - id: Ride ID
    ///   - date: Optional new date
    ///   - time: Optional new time
    ///   - pickup: Optional new pickup location
    ///   - destination: Optional new destination
    ///   - seats: Optional new seat count
    ///   - notes: Optional new notes
    ///   - gift: Optional new gift
    /// - Returns: Updated ride
    /// - Throws: AppError if update fails
    func updateRide(
        id: UUID,
        date: Date? = nil,
        time: String? = nil,
        pickup: String? = nil,
        destination: String? = nil,
        seats: Int? = nil,
        notes: String? = nil,
        gift: String? = nil
    ) async throws -> Ride {
        var updates: [String: AnyCodable] = [:]
        
        if let date = date {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            updates["date"] = AnyCodable(dateFormatter.string(from: date))
        }
        if let time = time {
            updates["time"] = AnyCodable(time)
        }
        if let pickup = pickup {
            updates["pickup"] = AnyCodable(pickup)
        }
        if let destination = destination {
            updates["destination"] = AnyCodable(destination)
        }
        if let seats = seats {
            updates["seats"] = AnyCodable(seats)
        }
        if let notes = notes {
            updates["notes"] = AnyCodable(notes)
        }
        if let gift = gift {
            updates["gift"] = AnyCodable(gift)
        }
        
        // Always update updated_at
        let dateFormatter = ISO8601DateFormatter()
        updates["updated_at"] = AnyCodable(dateFormatter.string(from: Date()))
        
        guard !updates.isEmpty else {
            throw AppError.invalidInput("No fields to update")
        }
        
        // Fetch original ride to check if claimer needs notification
        let originalRide = try? await fetchRide(id: id)
        
        // Update ride
        let response = try await supabase
            .from("rides")
            .update(updates)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
        
        let ride: Ride = try createDecoder().decode(Ride.self, from: response.data)
        
        // Notify claimer if ride is claimed and details changed
        if let claimedBy = ride.claimedBy,
           let original = originalRide,
           original.claimedBy == claimedBy {
            // Check if any important details changed
            let detailsChanged = (date != nil && original.date != ride.date) ||
                                (time != nil && original.time != ride.time) ||
                                (pickup != nil && original.pickup != ride.pickup) ||
                                (destination != nil && original.destination != ride.destination) ||
                                (seats != nil && original.seats != ride.seats)
            
            if detailsChanged {
                // Create notification for claimer
                // Note: In production, this would typically be handled by a database trigger
                // or backend function. For now, we'll create an in-app notification.
                do {
                    let notificationData: [String: AnyCodable] = [
                        "user_id": AnyCodable(claimedBy.uuidString),
                        "type": AnyCodable("ride_update"),
                        "title": AnyCodable("Ride Details Updated"),
                        "body": AnyCodable("The ride you claimed has been updated. Check the details."),
                        "ride_id": AnyCodable(id.uuidString),
                        "read": AnyCodable(false),
                        "pinned": AnyCodable(false)
                    ]
                    
                    // Insert notification (if notifications table exists)
                    try? await supabase
                        .from("notifications")
                        .insert(notificationData)
                        .execute()
                } catch {
                    // Notification creation is optional - don't fail the update
                    print("⚠️ Failed to create notification for claimer: \(error)")
                }
            }
        }
        
        // Invalidate cache
        await cacheManager.invalidateRides()
        
        return ride
    }
    
    // MARK: - Ride Deletion
    
    /// Delete a ride by ID
    /// - Parameter id: Ride ID
    /// - Throws: AppError if deletion fails
    func deleteRide(id: UUID) async throws {
        try await supabase
            .from("rides")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
        
        // Invalidate cache
        await cacheManager.invalidateRides()
    }
    
    // MARK: - Q&A Operations
    
    /// Fetch Q&A for a ride or favor request
    /// - Parameters:
    ///   - requestId: Request ID
    ///   - requestType: "ride" or "favor"
    /// - Returns: Array of Q&A items
    /// - Throws: AppError if fetch fails
    func fetchQA(requestId: UUID, requestType: String) async throws -> [RequestQA] {
        var query = supabase
            .from("request_qa")
            .select()
        
        // Use the correct column based on request type
        if requestType == "ride" {
            query = query.eq("ride_id", value: requestId.uuidString)
        } else if requestType == "favor" {
            query = query.eq("favor_id", value: requestId.uuidString)
        } else {
            throw AppError.invalidInput("Invalid request type: \(requestType)")
        }
        
        let response = try await query
            .order("created_at", ascending: true)
            .execute()
        
        var qaItems: [RequestQA] = try createDecoder().decode([RequestQA].self, from: response.data)
        
        // Enrich with asker profiles
        for (index, qa) in qaItems.enumerated() {
            if let asker = try? await ProfileService.shared.fetchProfile(userId: qa.userId) {
                qaItems[index].asker = asker
            }
        }
        
        return qaItems
    }
    
    /// Post a question on a ride or favor request
    /// - Parameters:
    ///   - requestId: Request ID
    ///   - requestType: "ride" or "favor"
    ///   - userId: User ID asking the question
    ///   - question: Question text
    /// - Returns: Created Q&A item
    /// - Throws: AppError if posting fails
    func postQuestion(
        requestId: UUID,
        requestType: String,
        userId: UUID,
        question: String
    ) async throws -> RequestQA {
        var qaData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId.uuidString),
            "question": AnyCodable(question)
        ]
        
        // Use the correct column based on request type
        if requestType == "ride" {
            qaData["ride_id"] = AnyCodable(requestId.uuidString)
        } else if requestType == "favor" {
            qaData["favor_id"] = AnyCodable(requestId.uuidString)
        } else {
            throw AppError.invalidInput("Invalid request type: \(requestType)")
        }
        
        let response = try await supabase
            .from("request_qa")
            .insert(qaData)
            .select()
            .single()
            .execute()
        
        var qa: RequestQA = try createDecoder().decode(RequestQA.self, from: response.data)
        
        // Enrich with asker profile
        if let asker = try? await ProfileService.shared.fetchProfile(userId: userId) {
            qa.asker = asker
        }
        
        return qa
    }
    
    /// Post an answer to a question
    /// - Parameters:
    ///   - qaId: Q&A ID
    ///   - answer: Answer text
    /// - Returns: Updated Q&A item
    /// - Throws: AppError if posting fails
    func postAnswer(qaId: UUID, answer: String) async throws -> RequestQA {
        let updates: [String: AnyCodable] = [
            "answer": AnyCodable(answer)
        ]
        
        let response = try await supabase
            .from("request_qa")
            .update(updates)
            .eq("id", value: qaId.uuidString)
            .select()
            .single()
            .execute()
        
        var qa: RequestQA = try createDecoder().decode(RequestQA.self, from: response.data)
        
        // Enrich with asker profile
        if let asker = try? await ProfileService.shared.fetchProfile(userId: qa.userId) {
            qa.asker = asker
        }
        
        return qa
    }
    
    // MARK: - Participants
    
    /// Fetch participants for a ride
    /// - Parameter rideId: Ride ID
    /// - Returns: Array of participant profiles
    /// - Throws: AppError if operation fails
    func fetchRideParticipants(rideId: UUID) async throws -> [Profile] {
        let response = try await supabase
            .from("ride_participants")
            .select("user_id")
            .eq("ride_id", value: rideId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let rows = try createDecoder().decode([ParticipantRow].self, from: response.data)
        
        var profiles: [Profile] = []
        for row in rows {
            if let profile = try? await ProfileService.shared.fetchProfile(userId: row.userId) {
                profiles.append(profile)
            }
        }
        
        return profiles
    }
    
    /// Fetch rides where a user is a participant
    /// - Parameter userId: User ID
    /// - Returns: Array of rides where the user is a participant
    /// - Throws: AppError if fetch fails
    func fetchRidesByParticipant(userId: UUID) async throws -> [Ride] {
        // Query ride_participants to get ride IDs
        let response = try await supabase
            .from("ride_participants")
            .select("ride_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let rideId: UUID
            enum CodingKeys: String, CodingKey {
                case rideId = "ride_id"
            }
        }
        
        let rows = try createDecoder().decode([ParticipantRow].self, from: response.data)
        let rideIds = rows.map { $0.rideId }
        
        guard !rideIds.isEmpty else {
            return []
        }
        
        // Fetch rides by IDs - fetch individually to avoid .in() syntax issues
        var allRides: [Ride] = []
        for rideId in rideIds {
            if let ride = try? await fetchRide(id: rideId) {
                allRides.append(ride)
            }
        }
        
        // Sort by date
        allRides.sort { $0.date < $1.date }
        
        return allRides
    }
    
    /// Add participants to a ride
    /// - Parameters:
    ///   - rideId: Ride ID
    ///   - userIds: Array of user IDs to add
    ///   - addedBy: User ID adding the participants
    /// - Throws: AppError if operation fails
    func addRideParticipants(rideId: UUID, userIds: [UUID], addedBy: UUID) async throws {
        guard !userIds.isEmpty else { return }
        
        // Check if user is the ride creator
        let ride = try await fetchRide(id: rideId)
        guard ride.userId == addedBy else {
            throw AppError.permissionDenied("Only the ride creator can add participants")
        }
        
        // Get existing participants to avoid duplicates
        let existingResponse = try? await supabase
            .from("ride_participants")
            .select("user_id")
            .eq("ride_id", value: rideId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let existingParticipants: [UUID] = (try? JSONDecoder().decode([ParticipantRow].self, from: existingResponse?.data ?? Data()))?.map { $0.userId } ?? []
        
        // Filter out users who are already participants
        let newUserIds = userIds.filter { !existingParticipants.contains($0) }
        
        guard !newUserIds.isEmpty else {
            print("ℹ️ [RideService] All users are already participants")
            return
        }
        
        // Insert new participants
        let inserts = newUserIds.map { userId in
            [
                "ride_id": AnyCodable(rideId.uuidString),
                "user_id": AnyCodable(userId.uuidString),
                "added_by": AnyCodable(addedBy.uuidString)
            ]
        }
        
        try await supabase
            .from("ride_participants")
            .insert(inserts)
            .execute()
        
        // Invalidate cache
        await cacheManager.invalidateRides()
        
        print("✅ [RideService] Added \(newUserIds.count) participant(s) to ride \(rideId)")
    }
    
    // MARK: - Private Helpers
    
    /// Create a JSON decoder configured for Supabase date formats
    private func createDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 with fractional seconds (for TIMESTAMP fields)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            
            // Try ISO8601 without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            
            // Try DATE format (YYYY-MM-DD)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }
    
    /// Enrich rides with profile data (poster, claimer, participants)
    private func enrichRidesWithProfiles(_ rides: [Ride]) async -> [Ride] {
        var enriched: [Ride] = []
        
        for ride in rides {
            let enrichedRide = await enrichRideWithProfiles(ride)
            enriched.append(enrichedRide)
        }
        
        return enriched
    }
    
    /// Enrich a single ride with profile data
    private func enrichRideWithProfiles(_ ride: Ride) async -> Ride {
        var enriched = ride
        
        // Fetch poster profile
        if let poster = try? await ProfileService.shared.fetchProfile(userId: ride.userId) {
            enriched.poster = poster
        }
        
        // Fetch claimer profile if claimed
        if let claimedBy = ride.claimedBy,
           let claimer = try? await ProfileService.shared.fetchProfile(userId: claimedBy) {
            enriched.claimer = claimer
        }
        
        // Fetch participants
        if let participants = try? await fetchRideParticipants(rideId: ride.id) {
            enriched.participants = participants
        }
        
        return enriched
    }
    
    /// Fetch Q&A count for a request
    private func fetchQACount(requestId: UUID, requestType: String) async throws -> Int {
        var query = supabase
            .from("request_qa")
            .select("id", head: true, count: .exact)
        
        // Use the correct column based on request type
        if requestType == "ride" {
            query = query.eq("ride_id", value: requestId.uuidString)
        } else if requestType == "favor" {
            query = query.eq("favor_id", value: requestId.uuidString)
        } else {
            return 0
        }
        
        let response = try await query.execute()
        return response.count ?? 0
    }
}

