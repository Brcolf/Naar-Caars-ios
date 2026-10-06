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
final class FavorService {
    
    // MARK: - Singleton
    
    static let shared = FavorService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Favor Fetching
    
    /// Fetch favors with optional filters
    /// - Parameters:
    ///   - status: Optional status filter
    ///   - userId: Optional user ID filter (favors posted by this user)
    ///   - claimedBy: Optional claimed by filter (favors claimed by this user)
    /// - Returns: Array of favors ordered by date ascending
    /// - Throws: AppError if fetch fails
    func fetchFavors(
        status: FavorStatus? = nil,
        userId: UUID? = nil,
        claimedBy: UUID? = nil,
        excludeStatus: FavorStatus? = nil
    ) async throws -> [Favor] {
        // Build query
        var query = supabase
            .from(supabase.favorsReadSource)
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
        if let excludeStatus = excludeStatus {
            query = query.neq("status", value: excludeStatus.rawValue)
        }
        
        // Execute query
        let response = try await query
            .order("date", ascending: true)
            .execute()
        
        // Decode favors with custom date decoder
        let favors: [Favor] = try createDecoder().decode([Favor].self, from: response.data)
        
        // Enrich with profiles
        let enrichedFavors = await enrichFavorsWithProfiles(favors)
        
        return enrichedFavors
    }
    
    /// Fetch a single favor by ID with all related data
    /// - Parameter id: Favor ID
    /// - Returns: Favor with poster, claimer, participants, and qaCount populated
    /// - Throws: AppError if fetch fails
    func fetchFavor(id: UUID) async throws -> Favor {
        // Fetch favor. A deleted favor, or one hidden by moderators from everyone but its
        // poster, comes back as zero rows; `.single()` turned that into a raw PostgREST error
        // that the detail screen showed with a Retry that could never succeed.
        let response = try await supabase
            .from(supabase.favorsReadSource)
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()

        guard let fetchedFavor = try createDecoder().decode([Favor].self, from: response.data).first else {
            throw AppError.notFound("Favor")
        }

        // Enrich with profiles and fetch the Q&A count concurrently (independent requests)
        async let enrichedFavor = enrichFavorWithProfiles(fetchedFavor)
        async let qaCount = fetchQACount(requestId: id, requestType: "favor")
        
        var favor = await enrichedFavor
        favor.qaCount = try await qaCount
        
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
    ///   - timezone: IANA timezone identifier (e.g. "America/Los_Angeles")
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
        gift: String? = nil,
        timezone: String
    ) async throws -> Favor {
        // Format date as "yyyy-MM-dd" using local timezone
        // Important: Use local timezone to match what the user selected in DatePicker
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current  // Use local timezone to avoid off-by-one day issues
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = dateFormatter.string(from: date)
        
        // Create favor data
        var favorData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId.uuidString),
            "title": AnyCodable(title),
            "location": AnyCodable(location),
            "duration": AnyCodable(duration.rawValue),
            "date": AnyCodable(dateString),
            "status": AnyCodable("open"),
            "timezone": AnyCodable(timezone)
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
    ///   - timezone: Optional new IANA timezone identifier
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
        gift: String? = nil,
        timezone: String? = nil
    ) async throws -> Favor {
        var updates: [String: AnyCodable] = [:]
        
        // nil leaves an optional column unchanged; an empty string means the poster cleared it
        // (description, requirements, gift, or the time with "Specify Time" switched off),
        // which is stored as NULL so it reads as absent everywhere.
        let cleared = AnyCodable(String?.none as Any)

        if let title = title {
            updates["title"] = AnyCodable(title)
        }
        if let description = description {
            updates["description"] = description.isEmpty ? cleared : AnyCodable(description)
        }
        if let location = location {
            updates["location"] = AnyCodable(location)
        }
        if let duration = duration {
            updates["duration"] = AnyCodable(duration.rawValue)
        }
        if let requirements = requirements {
            updates["requirements"] = requirements.isEmpty ? cleared : AnyCodable(requirements)
        }
        if let date = date {
            // Use local timezone to match what the user selected in DatePicker
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd"
            dateFmt.timeZone = .current  // Use local timezone to avoid off-by-one day issues
            dateFmt.locale = Locale(identifier: "en_US_POSIX")
            updates["date"] = AnyCodable(dateFmt.string(from: date))
        }
        if let time = time {
            updates["time"] = time.isEmpty ? cleared : AnyCodable(time)
        }
        if let gift = gift {
            updates["gift"] = gift.isEmpty ? cleared : AnyCodable(gift)
        }
        if let timezone = timezone {
            updates["timezone"] = AnyCodable(timezone)
        }

        // Always update updated_at
        let dateFormatter = ISO8601DateFormatter()
        updates["updated_at"] = AnyCodable(dateFormatter.string(from: Date()))

        guard !updates.isEmpty else {
            throw AppError.invalidInput("No fields to update")
        }

        // Snapshot only the columns compared below to decide whether the claimer
        // needs a notification (no profile/participant/Q&A enrichment)
        let originalFavor = try? await fetchFavorUpdateSnapshot(id: id)
        
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
                // Tell the claimer through the server-side RPC. A direct insert into
                // `notifications` for another user is rejected by RLS (service-only insert),
                // so the claimer was never told. The RPC builds the text itself, respects
                // blocks and keeps at most one unread notice per request.
                do {
                    let params: [String: AnyCodable] = [
                        "p_ride_id": AnyCodable(nil as String? as Any),
                        "p_favor_id": AnyCodable(id.uuidString),
                        "p_title": AnyCodable(""),
                        "p_body": AnyCodable("")
                    ]
                    try await supabase
                        .rpc("notify_claimer_of_request_update", params: params)
                        .execute()
                } catch {
                    AppLogger.warning("favors", "Failed to create notification for claimer: \(error)")
                }
            }
        }
        
        return favor
    }
    
    // MARK: - Favor Deletion
    
    /// Delete a favor by ID
    /// - Parameter id: Favor ID
    /// - Throws: AppError if deletion fails
    func deleteFavor(id: UUID) async throws {
        let response = try await supabase
            .from("favors")
            .delete()
            .eq("id", value: id.uuidString)
            .select("id")
            .execute()

        // The delete policy matches only the poster's own row. For anyone else PostgREST still
        // answers 200 with an empty array, and the screen showed the success checkmark for a
        // favor that was never deleted.
        if let rows = try? JSONSerialization.jsonObject(with: response.data) as? [Any], rows.isEmpty {
            throw AppError.permissionDenied("request_delete_not_allowed".localized)
        }
    }
    
    // MARK: - Participants
    
    /// Add participants to a favor
    /// Fetch participants for a favor
    /// - Parameter favorId: Favor ID
    /// - Returns: Array of participant profiles
    /// - Throws: AppError if operation fails
    func fetchFavorParticipants(favorId: UUID) async throws -> [Profile] {
        let response = try await supabase
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
        
        let rows = try createDecoder().decode([ParticipantRow].self, from: response.data)
        
        let userIds = rows.map { $0.userId }
        return try await ProfileService.shared.fetchProfiles(userIds: userIds)
    }
    
    /// Batch fetch participants for multiple favors in 2 queries (participants table + profiles)
    /// - Parameter favorIds: Array of favor UUIDs
    /// - Returns: Dictionary mapping each favor ID to its participant profiles
    private func fetchFavorParticipantsBatch(favorIds: [UUID]) async -> [UUID: [Profile]] {
        guard !favorIds.isEmpty else { return [:] }

        struct BatchParticipantRow: Codable {
            let favorId: UUID
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case favorId = "favor_id"
                case userId = "user_id"
            }
        }

        do {
            let response = try await supabase
                .from("favor_participants")
                .select("favor_id, user_id")
                .in("favor_id", values: favorIds.map { $0.uuidString })
                .execute()

            let rows = try createDecoder().decode([BatchParticipantRow].self, from: response.data)
            guard !rows.isEmpty else { return [:] }

            let grouped = Dictionary(grouping: rows, by: { $0.favorId })
            let allUserIds = Array(Set(rows.map { $0.userId }))
            let profiles = try await ProfileService.shared.fetchProfiles(userIds: allUserIds)
            let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

            var result: [UUID: [Profile]] = [:]
            for (favorId, participantRows) in grouped {
                result[favorId] = participantRows.compactMap { profileLookup[$0.userId] }
            }
            return result
        } catch {
            AppLogger.error("favors", "Error batch fetching favor participants: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Fetch favors where a user is a participant
    /// - Parameter userId: User ID
    /// - Returns: Array of favors where the user is a participant
    /// - Throws: AppError if fetch fails
    func fetchFavorsByParticipant(userId: UUID) async throws -> [Favor] {
        // Query favor_participants to get favor IDs
        let response = try await supabase
            .from("favor_participants")
            .select("favor_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let favorId: UUID
            enum CodingKeys: String, CodingKey {
                case favorId = "favor_id"
            }
        }
        
        let rows = try createDecoder().decode([ParticipantRow].self, from: response.data)
        let favorIds = rows.map { $0.favorId }
        
        guard !favorIds.isEmpty else {
            return []
        }
        
        // Fetch favors by IDs - fetch individually to avoid .in() syntax issues
        var allFavors: [Favor] = []
        for favorId in favorIds {
            if let favor = try? await fetchFavor(id: favorId) {
                allFavors.append(favor)
            }
        }
        
        // Sort by date
        allFavors.sort { $0.date < $1.date }
        
        return allFavors
    }
    
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
            AppLogger.info("favors", "All users are already participants")
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
        
        AppLogger.info("favors", "Added \(newUserIds.count) participant(s) to favor \(favorId)")
    }
    
    // MARK: - Private Helpers
    
    /// Create a JSON decoder configured for Supabase date formats
    private func createDecoder() -> JSONDecoder {
        DateDecoderFactory.makeSupabaseDecoder()
    }
    
    /// The favor columns updateFavor compares before/after to decide whether the claimer is notified
    private struct FavorUpdateSnapshot: Decodable {
        let title: String
        let location: String
        let duration: FavorDuration
        let date: Date
        let time: String?
        let claimedBy: UUID?
        
        enum CodingKeys: String, CodingKey {
            case title
            case location
            case duration
            case date
            case time
            case claimedBy = "claimed_by"
        }
    }
    
    /// Fetch only the favor columns needed by updateFavor's change check
    private func fetchFavorUpdateSnapshot(id: UUID) async throws -> FavorUpdateSnapshot {
        let response = try await supabase
            .from("favors")
            .select("title, location, duration, date, time, claimed_by")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
        
        return try createDecoder().decode(FavorUpdateSnapshot.self, from: response.data)
    }
    
    /// Enrich favors with profile data (poster, claimer, participants)
    /// Uses a single batched profile fetch to avoid N+1 queries
    private func enrichFavorsWithProfiles(_ favors: [Favor]) async -> [Favor] {
        guard !favors.isEmpty else { return [] }
        
        // Collect all unique user IDs (posters + claimers) for a single batch fetch
        var allUserIds = Set<UUID>()
        for favor in favors {
            allUserIds.insert(favor.userId)
            if let claimedBy = favor.claimedBy {
                allUserIds.insert(claimedBy)
            }
        }
        
        // Batch fetch all profiles in one query
        let profiles = (try? await ProfileService.shared.fetchProfiles(userIds: Array(allUserIds))) ?? []
        let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        
        // Batch fetch all participants in 2 queries (participants table + profiles)
        let participantsByFavor = await fetchFavorParticipantsBatch(favorIds: favors.map { $0.id })

        // Map profiles and participants back to favors
        var enriched: [Favor] = []
        for var favor in favors {
            favor.poster = profileLookup[favor.userId]
            if let claimedBy = favor.claimedBy {
                favor.claimer = profileLookup[claimedBy]
            }
            favor.participants = participantsByFavor[favor.id] ?? []
            enriched.append(favor)
        }

        return enriched
    }
    
    /// Enrich a single favor with profile data
    /// Poster and claimer come from one batched profile fetch that runs alongside the participants fetch
    private func enrichFavorWithProfiles(_ favor: Favor) async -> Favor {
        var enriched = favor
        
        // Collect unique profile IDs (poster + claimer) for a single batch fetch
        var profileIds: Set<UUID> = [favor.userId]
        if let claimedBy = favor.claimedBy {
            profileIds.insert(claimedBy)
        }
        let profileUserIds = Array(profileIds)
        
        // Fetch profiles and participants concurrently (independent requests)
        async let profilesTask = ProfileService.shared.fetchProfiles(userIds: profileUserIds)
        async let participantsTask = fetchFavorParticipants(favorId: favor.id)
        
        let profiles = (try? await profilesTask) ?? []
        let profileLookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        
        if let poster = profileLookup[favor.userId] {
            enriched.poster = poster
        }
        if let claimedBy = favor.claimedBy, let claimer = profileLookup[claimedBy] {
            enriched.claimer = claimer
        }
        
        if let participants = try? await participantsTask {
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

extension FavorService: FavorServiceProtocol {}



