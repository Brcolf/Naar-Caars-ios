//
//  FavorService.swift
//  NaarsCars
//
//  Service for favor-related operations with caching
//

import Foundation
import Supabase

/// Service for favor-related operations
/// Handles fetching, creating, updating, deleting favors
@MainActor
final class FavorService {
    
    // MARK: - Singleton
    
    static let shared = FavorService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let cacheManager = CacheManager.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Favor Fetching
    
    /// Fetch favors with optional filters
    /// Checks cache first, then fetches from network if needed
    /// - Parameters:
    ///   - status: Optional status filter
    ///   - userId: Optional user ID filter (favors posted by this user)
    ///   - claimedBy: Optional claimed by filter (favors claimed by this user)
    /// - Returns: Array of favors ordered by date ascending
    /// - Throws: AppError if fetch fails
    func fetchFavors(
        status: FavorStatus? = nil,
        userId: UUID? = nil,
        claimedBy: UUID? = nil
    ) async throws -> [Favor] {
        // Check cache first
        if let cachedFavors = await cacheManager.getCachedFavors() {
            // Apply filters to cached data
            var filtered = cachedFavors
            
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
            .from("favors")
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
        
        // Decode favors with custom date decoder
        let favors: [Favor] = try createDecoder().decode([Favor].self, from: response.data)
        
        // Enrich with profiles
        let enrichedFavors = await enrichFavorsWithProfiles(favors)
        
        // Cache results
        await cacheManager.cacheFavors(enrichedFavors)
        
        return enrichedFavors
    }
    
    /// Fetch a single favor by ID with all related data
    /// - Parameter id: Favor ID
    /// - Returns: Favor with poster, claimer, participants, and qaCount populated
    /// - Throws: AppError if fetch fails
    func fetchFavor(id: UUID) async throws -> Favor {
        // Fetch favor
        let response = try await supabase
            .from("favors")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
        
        var favor: Favor = try createDecoder().decode(Favor.self, from: response.data)
        
        // Enrich with profiles
        favor = await enrichFavorWithProfiles(favor)
        
        // Fetch Q&A count
        let qaCount = try await fetchQACount(requestId: id, requestType: "favor")
        favor.qaCount = qaCount
        
        return favor
    }
    
    // MARK: - Favor Creation
    
    /// Create a new favor request
    /// - Parameters:
    ///   - userId: User ID of the poster
    ///   - title: Favor title
    ///   - description: Optional description
    ///   - location: Location where favor is needed
    ///   - duration: Estimated duration
    ///   - requirements: Optional special requirements
    ///   - date: Date when favor is needed
    ///   - time: Optional time (formatted as "HH:mm:ss")
    ///   - gift: Optional gift/compensation
    /// - Returns: Created favor
    /// - Throws: AppError if creation fails
    func createFavor(
        userId: UUID,
        title: String,
        description: String? = nil,
        location: String,
        duration: FavorDuration,
        requirements: String? = nil,
        date: Date,
        time: String? = nil,
        gift: String? = nil
    ) async throws -> Favor {
        // Format date as "yyyy-MM-dd"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        // Create favor data
        var favorData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId.uuidString),
            "title": AnyCodable(title),
            "location": AnyCodable(location),
            "duration": AnyCodable(duration.rawValue),
            "date": AnyCodable(dateString),
            "status": AnyCodable("open")
        ]
        
        if let description = description {
            favorData["description"] = AnyCodable(description)
        }
        if let requirements = requirements {
            favorData["requirements"] = AnyCodable(requirements)
        }
        if let time = time {
            favorData["time"] = AnyCodable(time)
        }
        if let gift = gift {
            favorData["gift"] = AnyCodable(gift)
        }
        
        // Insert favor
        let response = try await supabase
            .from("favors")
            .insert(favorData)
            .select()
            .single()
            .execute()
        
        let favor: Favor = try createDecoder().decode(Favor.self, from: response.data)
        
        // Invalidate cache
        await cacheManager.invalidateFavors()
        
        return favor
    }
    
    // MARK: - Favor Updates
    
    /// Update an existing favor
    /// - Parameters:
    ///   - id: Favor ID
    ///   - title: Optional new title
    ///   - description: Optional new description
    ///   - location: Optional new location
    ///   - duration: Optional new duration
    ///   - requirements: Optional new requirements
    ///   - date: Optional new date
    ///   - time: Optional new time
    ///   - gift: Optional new gift
    /// - Returns: Updated favor
    /// - Throws: AppError if update fails
    func updateFavor(
        id: UUID,
        title: String? = nil,
        description: String? = nil,
        location: String? = nil,
        duration: FavorDuration? = nil,
        requirements: String? = nil,
        date: Date? = nil,
        time: String? = nil,
        gift: String? = nil
    ) async throws -> Favor {
        var updates: [String: AnyCodable] = [:]
        
        if let title = title {
            updates["title"] = AnyCodable(title)
        }
        if let description = description {
            updates["description"] = AnyCodable(description)
        }
        if let location = location {
            updates["location"] = AnyCodable(location)
        }
        if let duration = duration {
            updates["duration"] = AnyCodable(duration.rawValue)
        }
        if let requirements = requirements {
            updates["requirements"] = AnyCodable(requirements)
        }
        if let date = date {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            updates["date"] = AnyCodable(dateFormatter.string(from: date))
        }
        if let time = time {
            updates["time"] = AnyCodable(time)
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
        
        // Fetch original favor to check if claimer needs notification
        let originalFavor = try? await fetchFavor(id: id)
        
        // Update favor
        let response = try await supabase
            .from("favors")
            .update(updates)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
        
        let favor: Favor = try createDecoder().decode(Favor.self, from: response.data)
        
        // Notify claimer if favor is claimed and details changed
        if let claimedBy = favor.claimedBy,
           let original = originalFavor,
           original.claimedBy == claimedBy {
            // Check if any important details changed
            let detailsChanged = (title != nil && original.title != favor.title) ||
                                (location != nil && original.location != favor.location) ||
                                (duration != nil && original.duration != favor.duration) ||
                                (date != nil && original.date != favor.date) ||
                                (time != nil && original.time != favor.time)
            
            if detailsChanged {
                // Create notification for claimer
                do {
                    let notificationData: [String: AnyCodable] = [
                        "user_id": AnyCodable(claimedBy.uuidString),
                        "type": AnyCodable("favor_update"),
                        "title": AnyCodable("Favor Details Updated"),
                        "body": AnyCodable("The favor you claimed has been updated. Check the details."),
                        "favor_id": AnyCodable(id.uuidString),
                        "read": AnyCodable(false),
                        "pinned": AnyCodable(false)
                    ]
                    
                    try? await supabase
                        .from("notifications")
                        .insert(notificationData)
                        .execute()
                } catch {
                    print("⚠️ Failed to create notification for claimer: \(error)")
                }
            }
        }
        
        // Invalidate cache
        await cacheManager.invalidateFavors()
        
        return favor
    }
    
    // MARK: - Favor Deletion
    
    /// Delete a favor by ID
    /// - Parameter id: Favor ID
    /// - Throws: AppError if deletion fails
    func deleteFavor(id: UUID) async throws {
        try await supabase
            .from("favors")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
        
        // Invalidate cache
        await cacheManager.invalidateFavors()
    }
    
    // MARK: - Participants
    
    /// Add participants to a favor
    /// - Parameters:
    ///   - favorId: Favor ID
    ///   - userIds: Array of user IDs to add
    ///   - addedBy: User ID adding the participants
    /// - Throws: AppError if operation fails
    func addFavorParticipants(favorId: UUID, userIds: [UUID], addedBy: UUID) async throws {
        guard !userIds.isEmpty else { return }
        
        // Check if user is the favor creator
        let favor = try await fetchFavor(id: favorId)
        guard favor.userId == addedBy else {
            throw AppError.permissionDenied("Only the favor creator can add participants")
        }
        
        // Get existing participants to avoid duplicates
        let existingResponse = try? await supabase
            .from("favor_participants")
            .select("user_id")
            .eq("favor_id", value: favorId.uuidString)
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
            print("ℹ️ [FavorService] All users are already participants")
            return
        }
        
        // Insert new participants
        let inserts = newUserIds.map { userId in
            [
                "favor_id": AnyCodable(favorId.uuidString),
                "user_id": AnyCodable(userId.uuidString),
                "added_by": AnyCodable(addedBy.uuidString)
            ]
        }
        
        try await supabase
            .from("favor_participants")
            .insert(inserts)
            .execute()
        
        // If conversation exists for this favor, add participants to conversation
        if let conversation = try? await MessageService.shared.findExistingRequestConversation(favorId: favorId) {
            do {
                try await MessageService.shared.addParticipantsToConversation(
                    conversationId: conversation.id,
                    userIds: newUserIds,
                    addedBy: addedBy,
                    createAnnouncement: true
                )
                print("✅ [FavorService] Added participants to favor and conversation")
            } catch {
                print("⚠️ [FavorService] Failed to add participants to conversation: \(error.localizedDescription)")
            }
        }
        
        // Invalidate cache
        await cacheManager.invalidateFavors()
        
        print("✅ [FavorService] Added \(newUserIds.count) participant(s) to favor \(favorId)")
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
    
    /// Enrich favors with profile data (poster, claimer, participants)
    private func enrichFavorsWithProfiles(_ favors: [Favor]) async -> [Favor] {
        var enriched: [Favor] = []
        
        for favor in favors {
            let enrichedFavor = await enrichFavorWithProfiles(favor)
            enriched.append(enrichedFavor)
        }
        
        return enriched
    }
    
    /// Enrich a single favor with profile data
    private func enrichFavorWithProfiles(_ favor: Favor) async -> Favor {
        var enriched = favor
        
        // Fetch poster profile
        if let poster = try? await ProfileService.shared.fetchProfile(userId: favor.userId) {
            enriched.poster = poster
        }
        
        // Fetch claimer profile if claimed
        if let claimedBy = favor.claimedBy,
           let claimer = try? await ProfileService.shared.fetchProfile(userId: claimedBy) {
            enriched.claimer = claimer
        }
        
        // TODO: Fetch participants from participants table
        // For now, participants is nil
        
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



