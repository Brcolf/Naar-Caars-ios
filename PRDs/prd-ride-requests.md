# PRD: Ride Requests

## Document Information
- **Feature Name**: Ride Requests
- **Phase**: 1 (Core Experience)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`, `prd-user-profile.md`
- **Estimated Effort**: 1.5-2 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines the ride request functionality for the Naar's Cars iOS app. Ride requests are the core feature - users post when they need a ride somewhere, and other community members can volunteer to help.

### Why does this matter?
Ride requests are the primary use case for Naar's Cars. The app was built specifically to help neighbors share rides, especially for airport trips and carpooling.

### What problem does it solve?
- Users need transportation but don't want to use expensive ride services
- Community members want to help neighbors
- Coordination of shared rides (e.g., multiple people going to the same event)
- Building community through mutual aid

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Users can create ride requests | Request appears in dashboard |
| Users can view all open requests | List displays all open rides |
| Users can view request details | Detail page shows all info |
| Users can edit their requests | Changes save correctly |
| Users can delete their requests | Request removed from system |
| Users can add co-requestors | Multiple people linked to one request |
| Users can ask questions on requests | Q&A displayed on detail page |
| Requests support real-time updates | Changes appear without refresh |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| RIDE-01 | User | Post a ride request with pickup/destination | Others know where I need to go |
| RIDE-02 | User | Specify date and time for my ride | Others know when I need the ride |
| RIDE-03 | User | Add notes to my request | I can explain special circumstances |
| RIDE-04 | User | Offer a gift/compensation | I can show appreciation |
| RIDE-05 | User | See all open ride requests | I can find rides to help with |
| RIDE-06 | User | Filter requests I've posted | I can manage my own requests |
| RIDE-07 | User | Add co-requestors to my ride | Multiple people can share the ride |
| RIDE-08 | User | Edit my ride request | I can update details if plans change |
| RIDE-09 | User | Delete my ride request | I can cancel if I no longer need it |
| RIDE-10 | User | Ask a question on a request | I can get clarification before claiming |
| RIDE-11 | Poster | Answer questions on my request | I can help clarify for potential helpers |
| RIDE-12 | User | See request status | I know if it's open, claimed, or completed |
| RIDE-13 | User | See who posted the request | I know who I'd be helping |

---

## 4. Functional Requirements

### 4.1 Ride Data Model

**Requirement RIDE-FR-001**: The Ride model MUST be defined:

```swift
// Core/Models/Ride.swift
import Foundation

/// Represents a ride request in the community.
/// Maps to the `rides` table in Supabase.
struct Ride: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let type: String  // Always "request" for now
    var date: Date
    var time: Date  // Store as Date for easier handling
    var pickup: String
    var destination: String
    var seats: Int?
    var notes: String?
    var gift: String?
    var status: RideStatus
    var claimedBy: UUID?
    var reviewed: Bool
    var reviewSkipped: Bool?
    var reviewSkippedAt: Date?
    let createdAt: Date
    
    // Joined data (populated when fetched with joins)
    var poster: Profile?
    var claimer: Profile?
    var participants: [Profile]?
    var qaCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case date
        case time
        case pickup
        case destination
        case seats
        case notes
        case gift
        case status
        case claimedBy = "claimed_by"
        case reviewed
        case reviewSkipped = "review_skipped"
        case reviewSkippedAt = "review_skipped_at"
        case createdAt = "created_at"
    }
}

/// Possible statuses for a ride
enum RideStatus: String, Codable {
    case open = "open"
    case pending = "pending"  // Legacy, may not be used
    case confirmed = "confirmed"
    case completed = "completed"
    
    var displayText: String {
        switch self {
        case .open: return "Open"
        case .pending: return "Pending"
        case .confirmed: return "Claimed"
        case .completed: return "Completed"
        }
    }
    
    var color: Color {
        switch self {
        case .open: return .green
        case .pending: return .orange
        case .confirmed: return .blue
        case .completed: return .gray
        }
    }
}
```

---

### 4.2 Ride Service

**Requirement RIDE-FR-002**: The app MUST have a `RideService` for all ride operations:

```swift
// Core/Services/RideService.swift
import Foundation
import Supabase

/// Service for ride-related operations.
@MainActor
final class RideService {
    private let supabase = SupabaseService.shared.client
    
    static let shared = RideService()
    private init() {}
    
    // MARK: - Fetch Operations
    
    /// Fetch all rides with optional filters
    func fetchRides(
        status: RideStatus? = nil,
        userId: UUID? = nil,
        claimedBy: UUID? = nil
    ) async throws -> [Ride] {
        var query = supabase
            .from("rides")
            .select()
        
        if let status = status {
            query = query.eq("status", status.rawValue)
        }
        if let userId = userId {
            query = query.eq("user_id", userId.uuidString)
        }
        if let claimedBy = claimedBy {
            query = query.eq("claimed_by", claimedBy.uuidString)
        }
        
        let response = try await query
            .order("date", ascending: true)
            .execute()
        
        var rides = try JSONDecoder().decode([Ride].self, from: response.data)
        
        // Fetch related profiles
        rides = try await enrichRidesWithProfiles(rides)
        
        return rides
    }
    
    /// Fetch a single ride by ID
    func fetchRide(id: UUID) async throws -> Ride {
        let response = try await supabase
            .from("rides")
            .select()
            .eq("id", id.uuidString)
            .single()
            .execute()
        
        var ride = try JSONDecoder().decode(Ride.self, from: response.data)
        
        // Fetch poster profile
        ride.poster = try? await ProfileService.shared.fetchProfile(userId: ride.userId)
        
        // Fetch claimer profile if claimed
        if let claimedBy = ride.claimedBy {
            ride.claimer = try? await ProfileService.shared.fetchProfile(userId: claimedBy)
        }
        
        // Fetch participants
        ride.participants = try await fetchRideParticipants(rideId: id)
        
        // Fetch Q&A count
        ride.qaCount = try await fetchQACount(rideId: id)
        
        return ride
    }
    
    // MARK: - Create/Update/Delete
    
    /// Create a new ride request
    func createRide(
        userId: UUID,
        date: Date,
        time: Date,
        pickup: String,
        destination: String,
        seats: Int?,
        notes: String?,
        gift: String?,
        coRequestorIds: [UUID]?
    ) async throws -> Ride {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: time)
        
        let insertData: [String: Any] = [
            "user_id": userId.uuidString,
            "type": "request",
            "date": dateString,
            "time": timeString,
            "pickup": pickup,
            "destination": destination,
            "seats": seats as Any,
            "notes": notes as Any,
            "gift": gift as Any,
            "status": "open",
            "reviewed": false
        ]
        
        let response = try await supabase
            .from("rides")
            .insert(insertData)
            .select()
            .single()
            .execute()
        
        var ride = try JSONDecoder().decode(Ride.self, from: response.data)
        
        // Add co-requestors if specified
        if let coRequestorIds = coRequestorIds, !coRequestorIds.isEmpty {
            try await addRideParticipants(rideId: ride.id, userIds: coRequestorIds, addedBy: userId)
        }
        
        // Create conversation for this ride
        try await createRideConversation(rideId: ride.id, createdBy: userId, participantIds: coRequestorIds ?? [])
        
        // Notify community about new request
        try await notifyNewRideRequest(ride: ride, posterName: ride.poster?.name ?? "Someone")
        
        return ride
    }
    
    /// Update an existing ride
    func updateRide(
        id: UUID,
        date: Date?,
        time: Date?,
        pickup: String?,
        destination: String?,
        seats: Int?,
        notes: String?,
        gift: String?
    ) async throws {
        var updates: [String: Any] = [:]
        
        if let date = date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            updates["date"] = formatter.string(from: date)
        }
        if let time = time {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            updates["time"] = formatter.string(from: time)
        }
        if let pickup = pickup { updates["pickup"] = pickup }
        if let destination = destination { updates["destination"] = destination }
        if let seats = seats { updates["seats"] = seats }
        if let notes = notes { updates["notes"] = notes }
        if let gift = gift { updates["gift"] = gift }
        
        try await supabase
            .from("rides")
            .update(updates)
            .eq("id", id.uuidString)
            .execute()
    }
    
    /// Delete a ride request
    func deleteRide(id: UUID) async throws {
        try await supabase
            .from("rides")
            .delete()
            .eq("id", id.uuidString)
            .execute()
    }
    
    // MARK: - Participants
    
    /// Fetch participants for a ride
    func fetchRideParticipants(rideId: UUID) async throws -> [Profile] {
        let response = try await supabase
            .from("ride_participants")
            .select("user_id")
            .eq("ride_id", rideId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let rows = try JSONDecoder().decode([ParticipantRow].self, from: response.data)
        
        var profiles: [Profile] = []
        for row in rows {
            if let profile = try? await ProfileService.shared.fetchProfile(userId: row.userId) {
                profiles.append(profile)
            }
        }
        
        return profiles
    }
    
    /// Add participants to a ride
    func addRideParticipants(rideId: UUID, userIds: [UUID], addedBy: UUID) async throws {
        let inserts = userIds.map { userId in
            [
                "ride_id": rideId.uuidString,
                "user_id": userId.uuidString,
                "added_by": addedBy.uuidString
            ]
        }
        
        try await supabase
            .from("ride_participants")
            .insert(inserts)
            .execute()
    }
    
    // MARK: - Q&A
    
    /// Fetch Q&A count for a ride
    func fetchQACount(rideId: UUID) async throws -> Int {
        let response = try await supabase
            .from("request_qa")
            .select("id", head: true, count: .exact)
            .eq("ride_id", rideId.uuidString)
            .execute()
        
        return response.count ?? 0
    }
    
    // MARK: - Private Helpers
    
    private func enrichRidesWithProfiles(_ rides: [Ride]) async throws -> [Ride] {
        // Collect all user IDs
        var userIds = Set<UUID>()
        for ride in rides {
            userIds.insert(ride.userId)
            if let claimedBy = ride.claimedBy {
                userIds.insert(claimedBy)
            }
        }
        
        // Fetch all profiles in one query
        let response = try await supabase
            .from("profiles")
            .select()
            .in("id", userIds.map { $0.uuidString })
            .execute()
        
        let profiles = try JSONDecoder().decode([Profile].self, from: response.data)
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        
        // Enrich rides
        return rides.map { ride in
            var enriched = ride
            enriched.poster = profileMap[ride.userId]
            if let claimedBy = ride.claimedBy {
                enriched.claimer = profileMap[claimedBy]
            }
            return enriched
        }
    }
    
    private func createRideConversation(rideId: UUID, createdBy: UUID, participantIds: [UUID]) async throws {
        // Create conversation
        let convoResponse = try await supabase
            .from("conversations")
            .insert(["ride_id": rideId.uuidString, "created_by": createdBy.uuidString])
            .select()
            .single()
            .execute()
        
        struct ConvoRow: Codable { let id: UUID }
        let convo = try JSONDecoder().decode(ConvoRow.self, from: convoResponse.data)
        
        // Add creator as admin participant
        try await supabase
            .from("conversation_participants")
            .insert([
                "conversation_id": convo.id.uuidString,
                "user_id": createdBy.uuidString,
                "is_admin": true
            ])
            .execute()
        
        // Add co-requestors as participants
        for participantId in participantIds {
            try await supabase
                .from("conversation_participants")
                .insert([
                    "conversation_id": convo.id.uuidString,
                    "user_id": participantId.uuidString,
                    "is_admin": false
                ])
                .execute()
        }
    }
    
    private func notifyNewRideRequest(ride: Ride, posterName: String) async throws {
        // Notification logic - will be implemented in notifications PRD
        // For now, this is a placeholder
        Log.networkInfo("Would notify about new ride: \(ride.pickup) â†’ \(ride.destination)")
    }
}
```

---

### 4.3 Dashboard / Ride List View

**Requirement RIDE-FR-003**: The dashboard MUST display rides in a tabbed interface:

| Tab | Description | Filter |
|-----|-------------|--------|
| All Open | Rides anyone can claim | `status = 'open'` AND not past date |
| My Requests | Rides the current user posted | `user_id = currentUser` OR user is participant |
| Helping | Rides the current user claimed | `claimed_by = currentUser` |
| Completed | Past rides | `status = 'completed'` |

**Requirement RIDE-FR-004**: Dashboard wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   Requests                   [+]    â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”â”‚
â”‚  â”‚ All Open â”‚ My Requestsâ”‚ Helping â”‚â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸš— Need Ride        [Open]  â”‚   â”‚
â”‚   â”‚ [Avatar] John S.            â”‚   â”‚
â”‚   â”‚ ðŸ“ Capitol Hill â†’ SEA       â”‚   â”‚
â”‚   â”‚ ðŸ“… Mon, Jan 6 â€¢ 8:00 AM     â”‚   â”‚
â”‚   â”‚ ðŸŽ Coffee â˜•                â”‚   â”‚
â”‚   â”‚                    ðŸ’¬ 2     â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸš— Need Ride        [Open]  â”‚   â”‚
â”‚   â”‚ [Avatar] Jane D. +1         â”‚   â”‚
â”‚   â”‚ ðŸ“ Fremont â†’ Downtown       â”‚   â”‚
â”‚   â”‚ ðŸ“… Tue, Jan 7 â€¢ 6:30 PM     â”‚   â”‚
â”‚   â”‚                    ðŸ’¬ 0     â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   (Empty state if no rides)         â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement RIDE-FR-005**: Each ride card MUST display:
- Type badge ("Need Ride")
- Status badge (Open/Claimed/Completed)
- Poster avatar(s) - multiple if co-requestors
- Pickup â†’ Destination
- Date and time
- Gift (if specified)
- Q&A count (if any questions)

---

### 4.4 Create Ride Request

**Requirement RIDE-FR-006**: The create ride form MUST collect:

| Field | Required | Type | Validation |
|-------|----------|------|------------|
| Date | Yes | DatePicker | Must be today or future |
| Time | Yes | TimePicker | - |
| Pickup Location | Yes | TextField | 2-200 characters |
| Destination | Yes | TextField | 2-200 characters |
| Number of Seats | No | Stepper | 1-8 if specified |
| Notes | No | TextEditor | Max 500 characters |
| Gift/Compensation | No | TextField | Max 100 characters |
| Co-requestors | No | Multi-select | Select from community members |

**Requirement RIDE-FR-007**: Create Ride wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â†  New Ride Request      [Post]   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   When do you need a ride?          â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ“…  January 6, 2025         â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ•  8:00 AM                 â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Where are you going?              â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ“ Pickup location          â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸŽ¯ Destination              â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   How many seats do you need?       â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  [ - ]      2      [ + ]    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Additional notes (optional)       â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Gift/Compensation (optional)      â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸŽ e.g., Coffee, $20        â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Co-requestors (optional)          â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [+] Add people              â”‚   â”‚
â”‚   â”‚ [Avatar] Jane D.        [x] â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

### 4.5 Ride Detail View

**Requirement RIDE-FR-008**: The ride detail page MUST display all ride information:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â†  Ride Details           [Edit]  â”‚  (Edit only if poster)
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   ðŸš— Need Ride              [Open]  â”‚
â”‚                                     â”‚
â”‚   Requested by:                     â”‚
â”‚   [Avatar] [Avatar]                 â”‚
â”‚   John S., Jane D.                  â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   ðŸ“ Route                          â”‚
â”‚   Capitol Hill                      â”‚
â”‚         â†“                           â”‚
â”‚   Seattle-Tacoma Airport (SEA)      â”‚
â”‚                                     â”‚
â”‚   ðŸ“… Mon, Jan 6, 2025               â”‚
â”‚   ðŸ• 8:00 AM                        â”‚
â”‚   ðŸ‘¥ 2 seats needed                 â”‚
â”‚                                     â”‚
â”‚   ðŸ“ Notes                          â”‚
â”‚   We have two medium suitcases      â”‚
â”‚   each. Flight is at 11am.          â”‚
â”‚                                     â”‚
â”‚   ðŸŽ Gift                           â”‚
â”‚   Coffee and breakfast! â˜•          â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   ðŸ’¬ Questions & Answers            â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Bob M. asked:               â”‚   â”‚
â”‚   â”‚ "Is 7:30 too early to pick  â”‚   â”‚
â”‚   â”‚  you up?"                   â”‚   â”‚
â”‚   â”‚   â†³ John S.: "That works!"  â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   [Ask a Question]                  â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   (If not poster and open:)         â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚      ðŸ™Œ I Can Help!         â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   (If claimed by someone:)          â”‚
â”‚   Helped by: [Avatar] Bob M.        â”‚
â”‚   [ðŸ’¬ Message]                      â”‚
â”‚                                     â”‚
â”‚   (If poster:)                      â”‚
â”‚   [Delete Request]                  â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

### 4.6 Q&A Feature

**Requirement RIDE-FR-009**: The Q&A data model MUST be defined:

```swift
// Core/Models/RequestQA.swift
struct RequestQA: Codable, Identifiable {
    let id: UUID
    let rideId: UUID?
    let favorId: UUID?
    let userId: UUID
    let content: String
    let parentId: UUID?  // If this is a reply
    let createdAt: Date
    
    // Joined data
    var user: Profile?
    var replies: [RequestQA]?
    
    var isReply: Bool {
        parentId != nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case favorId = "favor_id"
        case userId = "user_id"
        case content
        case parentId = "parent_id"
        case createdAt = "created_at"
    }
}
```

**Requirement RIDE-FR-010**: Q&A Service methods:

```swift
extension RideService {
    /// Fetch Q&A for a ride
    func fetchQA(rideId: UUID) async throws -> [RequestQA] {
        let response = try await supabase
            .from("request_qa")
            .select("*, user:profiles!request_qa_user_id_fkey(id, name, avatar_url)")
            .eq("ride_id", rideId.uuidString)
            .is("parent_id", value: nil)  // Only top-level questions
            .order("created_at", ascending: true)
            .execute()
        
        var questions = try JSONDecoder().decode([RequestQA].self, from: response.data)
        
        // Fetch replies for each question
        for i in 0..<questions.count {
            questions[i].replies = try await fetchQAReplies(parentId: questions[i].id)
        }
        
        return questions
    }
    
    /// Fetch replies to a Q&A item
    func fetchQAReplies(parentId: UUID) async throws -> [RequestQA] {
        let response = try await supabase
            .from("request_qa")
            .select("*, user:profiles!request_qa_user_id_fkey(id, name, avatar_url)")
            .eq("parent_id", parentId.uuidString)
            .order("created_at", ascending: true)
            .execute()
        
        return try JSONDecoder().decode([RequestQA].self, from: response.data)
    }
    
    /// Post a question on a ride
    func postQuestion(rideId: UUID, userId: UUID, content: String) async throws -> RequestQA {
        let response = try await supabase
            .from("request_qa")
            .insert([
                "ride_id": rideId.uuidString,
                "user_id": userId.uuidString,
                "content": content
            ])
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(RequestQA.self, from: response.data)
    }
    
    /// Reply to a question
    func postReply(rideId: UUID, parentId: UUID, userId: UUID, content: String) async throws -> RequestQA {
        let response = try await supabase
            .from("request_qa")
            .insert([
                "ride_id": rideId.uuidString,
                "user_id": userId.uuidString,
                "content": content,
                "parent_id": parentId.uuidString
            ])
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(RequestQA.self, from: response.data)
    }
}
```

**Requirement RIDE-FR-011**: Q&A UI wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   ðŸ’¬ Questions & Answers            â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   [Avatar] Bob M.           2h ago  â”‚
â”‚   "What terminal are you flying     â”‚
â”‚    out of?"                         â”‚
â”‚                                     â”‚
â”‚      â†³ [Avatar] John S.     1h ago  â”‚
â”‚        "Terminal A - Alaska"        â”‚
â”‚                                     â”‚
â”‚      [Reply]                        â”‚
â”‚                                     â”‚
â”‚   â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”‚
â”‚                                     â”‚
â”‚   [Avatar] Sara K.          1h ago  â”‚
â”‚   "I could pick you up at 7:45,     â”‚
â”‚    would that work?"                â”‚
â”‚                                     â”‚
â”‚      (No replies yet)               â”‚
â”‚                                     â”‚
â”‚      [Reply]                        â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Ask a question...           â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                           [Post]    â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement RIDE-FR-012**: Q&A notifications:
- When a question is posted, notify the ride poster(s)
- When a reply is posted, notify the question asker

---

### 4.7 Edit Ride Request

**Requirement RIDE-FR-013**: Only the ride poster can edit a ride.

**Requirement RIDE-FR-014**: If a ride is already claimed (`status != 'open'`):
- Show warning: "This ride has been claimed. Editing may cause confusion."
- Still allow editing (claimer should be notified)

**Requirement RIDE-FR-015**: The edit form uses the same UI as create, pre-populated with existing values.

---

### 4.8 Delete Ride Request

**Requirement RIDE-FR-016**: Only the ride poster can delete a ride.

**Requirement RIDE-FR-017**: Before deletion, show confirmation:
- "Are you sure you want to delete this ride request?"
- If claimed: "This ride has been claimed by [Name]. They will be notified."

**Requirement RIDE-FR-018**: On deletion:
1. Delete the ride from database
2. If claimed, notify the claimer
3. Navigate back to dashboard

---

### 4.9 Co-Requestors

**Requirement RIDE-FR-019**: Co-requestors are stored in `ride_participants` table:

```swift
struct RideParticipant: Codable {
    let id: UUID
    let rideId: UUID
    let userId: UUID
    let addedBy: UUID
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case userId = "user_id"
        case addedBy = "added_by"
        case createdAt = "created_at"
    }
}
```

**Requirement RIDE-FR-020**: When displaying a ride with co-requestors:
- Show multiple avatars in a stack
- List all names (e.g., "John S., Jane D., +1")

**Requirement RIDE-FR-021**: Co-requestors have the same permissions as the poster:
- Can edit the ride
- Can delete the ride
- Receive Q&A notifications

---

### 4.10 Real-time Updates

**Requirement RIDE-FR-022**: The ride list MUST update in real-time when:
- A new ride is created
- A ride is claimed
- A ride is edited
- A ride is deleted

**Requirement RIDE-FR-023**: Implementation using Supabase Realtime:

```swift
// In DashboardViewModel
func subscribeToRideChanges() {
    let channel = supabase.channel("rides-changes")
    
    channel.on("postgres_changes", 
               filter: ChannelFilter(event: "*", schema: "public", table: "rides")) { payload in
        Task { @MainActor in
            await self.refreshRides()
        }
    }
    
    Task {
        await channel.subscribe()
    }
}
```

---

## 5. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Location autocomplete | Future enhancement (Google Places API) |
| Map view of rides | Future enhancement |
| Recurring rides | Future enhancement |
| Ride offers (I'm driving somewhere) | Simplified to requests only |
| Price negotiation | Gift-based, not transactional |
| In-app payments | Out of scope |

---

## 6. Design Considerations

### iOS-Native Patterns

| Pattern | Implementation |
|---------|---------------|
| `DatePicker` | Native date/time selection |
| `Form` | For create/edit ride layout |
| `.swipeActions` | Delete ride from list |
| Pull-to-refresh | `.refreshable` on ride list |
| `.sheet` | For Q&A composer |
| Context menu | Long-press on ride card for actions |

### Improvements Over Web App

| Web Behavior | iOS Improvement |
|--------------|-----------------|
| Separate date/time inputs | Combined native DatePicker |
| Modal for questions | Inline expandable Q&A section |
| Toast confirmations | Haptic feedback + animated state changes |
| Page refresh for updates | Real-time updates via Supabase |

---

## 7. Technical Considerations

### Date/Time Handling

- Store dates as `DATE` type in Supabase (`YYYY-MM-DD`)
- Store times as `TIME` type (`HH:MM:SS`)
- Convert to user's local timezone for display
- Use `ISO8601DateFormatter` for API communication

### Performance

- Paginate ride list (20 per page initially)
- Lazy load Q&A when detail view opens
- Cache profile images

---

## 8. Dependencies

### Depends On
- `prd-foundation-architecture.md` - Base components
- `prd-authentication.md` - User auth required
- `prd-user-profile.md` - Profile display in cards

### Used By
- `prd-request-claiming.md` - Claiming logic
- `prd-messaging.md` - Conversation creation
- `prd-reviews-ratings.md` - Review after completion

---

## 9. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Create ride request | Works end-to-end | Post new ride, appears in list |
| View ride details | All info displays | Open ride, verify all fields |
| Edit ride | Changes persist | Edit and verify changes saved |
| Delete ride | Removed from system | Delete and verify gone |
| Add co-requestor | Shows in ride | Add person, verify appears |
| Post question | Appears in Q&A | Post question, verify visible |
| Reply to question | Appears nested | Reply, verify nested display |
| Real-time updates | List updates live | Create ride in another session, verify appears |

---

## 10. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Should we show past rides in a separate tab? | **Yes** | "Completed" tab for history |
| Can anyone delete Q&A items? | **No** | Only the author can delete their Q&A |
| Should co-requestors be notified when ride is edited? | **Yes** | Notify all participants |

---

*End of PRD: Ride Requests*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 4.10 - Realtime Updates (or equivalent section)

**Replace/enhance existing realtime subscription with:**

```markdown
### 4.10 Realtime Updates

**Requirement RIDE-FR-015**: Subscribe to realtime ride updates using `RealtimeManager`:

```swift
// In DashboardViewModel or RideListViewModel
func subscribeToRideUpdates() async {
    await RealtimeManager.shared.subscribe(
        channelName: "rides:open",
        table: "rides",
        filter: "status=eq.open",
        onInsert: { [weak self] payload in
            Task { @MainActor in
                await self?.handleNewRide(payload)
            }
        },
        onUpdate: { [weak self] payload in
            Task { @MainActor in
                await self?.handleRideUpdate(payload)
            }
        },
        onDelete: { [weak self] payload in
            Task { @MainActor in
                await self?.handleRideDelete(payload)
            }
        }
    )
}

func unsubscribeFromRideUpdates() async {
    await RealtimeManager.shared.unsubscribe(channelName: "rides:open")
}
```

**Requirement RIDE-FR-015a**: Subscription cleanup MUST occur:
- When user navigates away from dashboard (`onDisappear`)
- When app enters background (handled by `RealtimeManager`)
- When user logs out

**Requirement RIDE-FR-015b**: View implementation pattern:

```swift
struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    
    var body: some View {
        // ... view content ...
        .task {
            await viewModel.loadRides()
            await viewModel.subscribeToRideUpdates()
        }
        .onDisappear {
            Task {
                await viewModel.unsubscribeFromRideUpdates()
            }
        }
    }
}
```

**Requirement RIDE-FR-015c**: Handle realtime updates efficiently:

```swift
private func handleNewRide(_ payload: Any) async {
    // Decode new ride from payload
    guard let ride = decodeRide(from: payload) else { return }
    
    // Insert at correct position (sorted by date)
    await MainActor.run {
        if let index = rides.firstIndex(where: { $0.date > ride.date }) {
            rides.insert(ride, at: index)
        } else {
            rides.append(ride)
        }
    }
    
    // Update cache
    await CacheManager.shared.invalidateRides()
}
```
```

---

## ADD: Section 4.1a - Dashboard Loading with Skeleton UI

**Insert after section 4.1 or in Dashboard section**

```markdown
### 4.1a Dashboard Loading

**Requirement RIDE-FR-001a**: Dashboard load sequence:

1. Show skeleton cards immediately (0ms)
2. Check cache for rides (< 50ms)
3. If cached: show cached data, fetch fresh in background
4. If not cached: show skeleton until network responds
5. Animate transition from skeleton to real data

**Requirement RIDE-FR-001b**: Implementation:

```swift
struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    
    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading && viewModel.rides.isEmpty {
                    // Skeleton state
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonRideCard()
                            .listRowSeparator(.hidden)
                    }
                } else if viewModel.rides.isEmpty {
                    // Empty state
                    EmptyStateView(
                        icon: "car",
                        title: "No Rides Yet",
                        message: "Be the first to request a ride!"
                    )
                } else {
                    // Real data
                    ForEach(viewModel.rides) { ride in
                        RideCard(ride: ride)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Rides")
            .task {
                await viewModel.loadRides()
            }
            .refreshable {
                await viewModel.refreshRides()
            }
        }
    }
}
```

**Requirement RIDE-FR-001c**: ViewModel caching integration:

```swift
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var rides: [Ride] = []
    @Published var isLoading = false
    @Published var error: AppError?
    
    func loadRides() async {
        // Check cache first
        if let cached = await CacheManager.shared.getCachedRides() {
            rides = cached
            // Refresh in background
            Task {
                await fetchFreshRides(showLoading: false)
            }
            return
        }
        
        // No cache - show loading
        await fetchFreshRides(showLoading: true)
    }
    
    func refreshRides() async {
        // Pull-to-refresh always bypasses cache
        await CacheManager.shared.invalidateRides()
        await fetchFreshRides(showLoading: false)
    }
    
    private func fetchFreshRides(showLoading: Bool) async {
        if showLoading { isLoading = true }
        defer { if showLoading { isLoading = false } }
        
        do {
            let freshRides = try await RideService.shared.fetchOpenRides()
            rides = freshRides
            await CacheManager.shared.cacheRides(freshRides)
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}
```
```

---

## ADD: Section 6.1 - Security Considerations

**Insert in Security section or create new section**

```markdown
### 6.1 Security Considerations

**Requirement RIDE-SEC-001**: Ride access controlled by RLS:
- Only approved users can view rides
- Users can only create rides as themselves
- Users can only update their own rides or rides they've claimed
- See `SECURITY.md` for RLS policy details

**Requirement RIDE-SEC-002**: Client-side defense-in-depth:

```swift
func updateRide(_ ride: Ride) async throws {
    // Verify ownership before attempting update
    guard ride.userId == AuthService.shared.currentUserId ||
          ride.claimedBy == AuthService.shared.currentUserId else {
        Log.security("Attempted to update ride without permission: \(ride.id)")
        throw AppError.unauthorized
    }
    
    // Proceed with update (RLS will also verify server-side)
    try await supabase
        .from("rides")
        .update(/* ... */)
        .eq("id", ride.id.uuidString)
        .execute()
}
```

**Requirement RIDE-SEC-003**: Invalidate cache after mutations:

```swift
func createRide(_ ride: RideCreate) async throws {
    try await supabase.from("rides").insert(ride).execute()
    
    // Invalidate cache so list refreshes
    await CacheManager.shared.invalidateRides()
}
```
```

---

*End of Ride Requests Addendum*
