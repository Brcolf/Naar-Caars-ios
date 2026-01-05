# PRD: Favor Requests

## Document Information
- **Feature Name**: Favor Requests
- **Phase**: 1 (Core Experience)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`, `prd-user-profile.md`
- **Estimated Effort**: 1 week
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines the favor request functionality for the Naar's Cars iOS app. Favors are general help requests - anything that isn't specifically a ride. Examples include: picking up groceries, helping move furniture, pet sitting, etc.

### Why does this matter?
While rides are the core feature, favors extend the app's usefulness to general community mutual aid. This makes the app more valuable and encourages daily engagement beyond just transportation needs.

### What problem does it solve?
- Users need help with tasks beyond transportation
- Community members want to help neighbors with various needs
- Coordination of one-time tasks that require someone's time and effort
- Building community through mutual aid

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Users can create favor requests | Request appears in dashboard |
| Users can view all open favors | List displays all open favors |
| Users can view favor details | Detail page shows all info |
| Users can edit their favors | Changes save correctly |
| Users can delete their favors | Favor removed from system |
| Users can add co-requestors | Multiple people linked to one request |
| Users can ask questions on favors | Q&A displayed on detail page |
| Favors support real-time updates | Changes appear without refresh |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| FAV-01 | User | Post a favor request with title and description | Others understand what I need help with |
| FAV-02 | User | Specify where the favor is needed | Helpers know the location |
| FAV-03 | User | Estimate how long it will take | Helpers can plan their time |
| FAV-04 | User | Set a date for when I need help | Helpers know when it's needed |
| FAV-05 | User | Add special requirements | Helpers know if they qualify |
| FAV-06 | User | Offer a gift/compensation | I can show appreciation |
| FAV-07 | User | See all open favor requests | I can find favors to help with |
| FAV-08 | User | Filter favors I've posted | I can manage my own requests |
| FAV-09 | User | Add co-requestors to my favor | Multiple people can share the request |
| FAV-10 | User | Edit my favor request | I can update details if plans change |
| FAV-11 | User | Delete my favor request | I can cancel if I no longer need it |
| FAV-12 | User | Ask a question on a favor | I can get clarification before claiming |
| FAV-13 | Poster | Answer questions on my favor | I can help clarify for potential helpers |

---

## 4. Functional Requirements

### 4.1 Favor Data Model

**Requirement FAV-FR-001**: The Favor model MUST be defined:

```swift
// Core/Models/Favor.swift
import Foundation
import SwiftUI

/// Represents a favor request in the community.
/// Maps to the `favors` table in Supabase.
struct Favor: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var title: String
    var description: String?
    var location: String
    var duration: FavorDuration
    var requirements: String?
    var date: Date
    var time: Date?
    var gift: String?
    var status: FavorStatus
    var claimedBy: UUID?
    var reviewed: Bool
    var reviewSkipped: Bool?
    var reviewSkippedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    
    // Joined data (populated when fetched with joins)
    var poster: Profile?
    var claimer: Profile?
    var participants: [Profile]?
    var qaCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case location
        case duration
        case requirements
        case date
        case time
        case gift
        case status
        case claimedBy = "claimed_by"
        case reviewed
        case reviewSkipped = "review_skipped"
        case reviewSkippedAt = "review_skipped_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Possible durations for a favor
enum FavorDuration: String, Codable, CaseIterable {
    case underHour = "under_hour"
    case coupleHours = "couple_hours"
    case coupleDays = "couple_days"
    case notSure = "not_sure"
    
    var displayText: String {
        switch self {
        case .underHour: return "Under an hour"
        case .coupleHours: return "A couple of hours"
        case .coupleDays: return "A couple of days"
        case .notSure: return "Not sure, could be a while"
        }
    }
    
    var icon: String {
        switch self {
        case .underHour: return "clock"
        case .coupleHours: return "clock.badge"
        case .coupleDays: return "calendar"
        case .notSure: return "questionmark.circle"
        }
    }
}

/// Possible statuses for a favor
enum FavorStatus: String, Codable {
    case open = "open"
    case confirmed = "confirmed"
    case completed = "completed"
    case cancelled = "cancelled"
    
    var displayText: String {
        switch self {
        case .open: return "Open"
        case .confirmed: return "Claimed"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: Color {
        switch self {
        case .open: return .green
        case .confirmed: return .blue
        case .completed: return .gray
        case .cancelled: return .red
        }
    }
}
```

---

### 4.2 Favor Service

**Requirement FAV-FR-002**: The app MUST have a `FavorService` for all favor operations:

```swift
// Core/Services/FavorService.swift
import Foundation
import Supabase

/// Service for favor-related operations.
@MainActor
final class FavorService {
    private let supabase = SupabaseService.shared.client
    
    static let shared = FavorService()
    private init() {}
    
    // MARK: - Fetch Operations
    
    /// Fetch all favors with optional filters
    func fetchFavors(
        status: FavorStatus? = nil,
        userId: UUID? = nil,
        claimedBy: UUID? = nil
    ) async throws -> [Favor] {
        var query = supabase
            .from("favors")
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
        
        var favors = try JSONDecoder().decode([Favor].self, from: response.data)
        
        // Fetch related profiles
        favors = try await enrichFavorsWithProfiles(favors)
        
        return favors
    }
    
    /// Fetch a single favor by ID
    func fetchFavor(id: UUID) async throws -> Favor {
        let response = try await supabase
            .from("favors")
            .select()
            .eq("id", id.uuidString)
            .single()
            .execute()
        
        var favor = try JSONDecoder().decode(Favor.self, from: response.data)
        
        // Fetch poster profile
        favor.poster = try? await ProfileService.shared.fetchProfile(userId: favor.userId)
        
        // Fetch claimer profile if claimed
        if let claimedBy = favor.claimedBy {
            favor.claimer = try? await ProfileService.shared.fetchProfile(userId: claimedBy)
        }
        
        // Fetch participants
        favor.participants = try await fetchFavorParticipants(favorId: id)
        
        // Fetch Q&A count
        favor.qaCount = try await fetchQACount(favorId: id)
        
        return favor
    }
    
    // MARK: - Create/Update/Delete
    
    /// Create a new favor request
    func createFavor(
        userId: UUID,
        title: String,
        description: String?,
        location: String,
        duration: FavorDuration,
        requirements: String?,
        date: Date,
        time: Date?,
        gift: String?,
        coRequestorIds: [UUID]?
    ) async throws -> Favor {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        var insertData: [String: Any] = [
            "user_id": userId.uuidString,
            "title": title,
            "location": location,
            "duration": duration.rawValue,
            "date": dateString,
            "status": "open",
            "reviewed": false
        ]
        
        if let description = description { insertData["description"] = description }
        if let requirements = requirements { insertData["requirements"] = requirements }
        if let gift = gift { insertData["gift"] = gift }
        
        if let time = time {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            insertData["time"] = timeFormatter.string(from: time)
        }
        
        let response = try await supabase
            .from("favors")
            .insert(insertData)
            .select()
            .single()
            .execute()
        
        var favor = try JSONDecoder().decode(Favor.self, from: response.data)
        
        // Add co-requestors if specified
        if let coRequestorIds = coRequestorIds, !coRequestorIds.isEmpty {
            try await addFavorParticipants(favorId: favor.id, userIds: coRequestorIds, addedBy: userId)
        }
        
        // Create conversation for this favor
        try await createFavorConversation(favorId: favor.id, createdBy: userId, participantIds: coRequestorIds ?? [])
        
        return favor
    }
    
    /// Update an existing favor
    func updateFavor(
        id: UUID,
        title: String?,
        description: String?,
        location: String?,
        duration: FavorDuration?,
        requirements: String?,
        date: Date?,
        time: Date?,
        gift: String?
    ) async throws {
        var updates: [String: Any] = [
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let title = title { updates["title"] = title }
        if let description = description { updates["description"] = description }
        if let location = location { updates["location"] = location }
        if let duration = duration { updates["duration"] = duration.rawValue }
        if let requirements = requirements { updates["requirements"] = requirements }
        if let gift = gift { updates["gift"] = gift }
        
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
        
        try await supabase
            .from("favors")
            .update(updates)
            .eq("id", id.uuidString)
            .execute()
    }
    
    /// Delete a favor request
    func deleteFavor(id: UUID) async throws {
        try await supabase
            .from("favors")
            .delete()
            .eq("id", id.uuidString)
            .execute()
    }
    
    // MARK: - Participants
    
    /// Fetch participants for a favor
    func fetchFavorParticipants(favorId: UUID) async throws -> [Profile] {
        let response = try await supabase
            .from("favor_participants")
            .select("user_id")
            .eq("favor_id", favorId.uuidString)
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
    
    /// Add participants to a favor
    func addFavorParticipants(favorId: UUID, userIds: [UUID], addedBy: UUID) async throws {
        let inserts = userIds.map { userId in
            [
                "favor_id": favorId.uuidString,
                "user_id": userId.uuidString,
                "added_by": addedBy.uuidString
            ]
        }
        
        try await supabase
            .from("favor_participants")
            .insert(inserts)
            .execute()
    }
    
    // MARK: - Q&A
    
    /// Fetch Q&A count for a favor
    func fetchQACount(favorId: UUID) async throws -> Int {
        let response = try await supabase
            .from("request_qa")
            .select("id", head: true, count: .exact)
            .eq("favor_id", favorId.uuidString)
            .execute()
        
        return response.count ?? 0
    }
    
    /// Fetch Q&A for a favor
    func fetchQA(favorId: UUID) async throws -> [RequestQA] {
        let response = try await supabase
            .from("request_qa")
            .select("*, user:profiles!request_qa_user_id_fkey(id, name, avatar_url)")
            .eq("favor_id", favorId.uuidString)
            .is("parent_id", value: nil)
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
    
    /// Post a question on a favor
    func postQuestion(favorId: UUID, userId: UUID, content: String) async throws -> RequestQA {
        let response = try await supabase
            .from("request_qa")
            .insert([
                "favor_id": favorId.uuidString,
                "user_id": userId.uuidString,
                "content": content
            ])
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(RequestQA.self, from: response.data)
    }
    
    /// Reply to a question
    func postReply(favorId: UUID, parentId: UUID, userId: UUID, content: String) async throws -> RequestQA {
        let response = try await supabase
            .from("request_qa")
            .insert([
                "favor_id": favorId.uuidString,
                "user_id": userId.uuidString,
                "content": content,
                "parent_id": parentId.uuidString
            ])
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(RequestQA.self, from: response.data)
    }
    
    // MARK: - Private Helpers
    
    private func enrichFavorsWithProfiles(_ favors: [Favor]) async throws -> [Favor] {
        var userIds = Set<UUID>()
        for favor in favors {
            userIds.insert(favor.userId)
            if let claimedBy = favor.claimedBy {
                userIds.insert(claimedBy)
            }
        }
        
        let response = try await supabase
            .from("profiles")
            .select()
            .in("id", userIds.map { $0.uuidString })
            .execute()
        
        let profiles = try JSONDecoder().decode([Profile].self, from: response.data)
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        
        return favors.map { favor in
            var enriched = favor
            enriched.poster = profileMap[favor.userId]
            if let claimedBy = favor.claimedBy {
                enriched.claimer = profileMap[claimedBy]
            }
            return enriched
        }
    }
    
    private func createFavorConversation(favorId: UUID, createdBy: UUID, participantIds: [UUID]) async throws {
        let convoResponse = try await supabase
            .from("conversations")
            .insert(["favor_id": favorId.uuidString, "created_by": createdBy.uuidString])
            .select()
            .single()
            .execute()
        
        struct ConvoRow: Codable { let id: UUID }
        let convo = try JSONDecoder().decode(ConvoRow.self, from: convoResponse.data)
        
        try await supabase
            .from("conversation_participants")
            .insert([
                "conversation_id": convo.id.uuidString,
                "user_id": createdBy.uuidString,
                "is_admin": true
            ])
            .execute()
        
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
}
```

---

### 4.3 Favor List View (Dashboard)

**Requirement FAV-FR-003**: Favors MUST be displayed alongside rides in the same dashboard using a combined filter:

| Filter Tab | Shows |
|------------|-------|
| All Open | Open rides AND open favors |
| My Requests | User's rides AND favors |
| Helping | Rides AND favors claimed by user |
| Completed | Completed rides AND favors |

**Requirement FAV-FR-004**: Favor card appearance:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ› ï¸ Favor           [Open]  â”‚   â”‚
â”‚   â”‚ [Avatar] Jane D.            â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚ Help moving boxes           â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â”‚ ðŸ“ Capitol Hill             â”‚   â”‚
â”‚   â”‚ ðŸ“… Sat, Jan 11 â€¢ 10:00 AM   â”‚   â”‚
â”‚   â”‚ â±ï¸ A couple of hours        â”‚   â”‚
â”‚   â”‚ ðŸŽ Pizza and beer! ðŸ•ðŸº     â”‚   â”‚
â”‚   â”‚                    ðŸ’¬ 1     â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
```

**Requirement FAV-FR-005**: Favor cards MUST show:
- Type badge ("Favor" with wrench icon)
- Status badge
- Poster avatar(s)
- Title (bold)
- Location
- Date and time (if specified)
- Duration estimate
- Gift (if specified)
- Q&A count (if any)

---

### 4.4 Create Favor Request

**Requirement FAV-FR-006**: The create favor form MUST collect:

| Field | Required | Type | Validation |
|-------|----------|------|------------|
| Title | Yes | TextField | 3-100 characters |
| Description | No | TextEditor | Max 500 characters |
| Location | Yes | TextField | 2-200 characters |
| Duration | Yes | Picker | Select from predefined options |
| Date | Yes | DatePicker | Must be today or future |
| Time | No | TimePicker | - |
| Requirements | No | TextEditor | Max 300 characters |
| Gift/Compensation | No | TextField | Max 100 characters |
| Co-requestors | No | Multi-select | Select from community members |

**Requirement FAV-FR-007**: Create Favor wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â†  New Favor Request     [Post]   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   What do you need help with?       â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Title (e.g., Help moving)   â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Description (optional)            â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Describe what you need...   â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Where?                            â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ“ Location                 â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   How long will it take?            â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ â±ï¸ A couple of hours      â–¼ â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   When do you need help?            â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ“…  January 11, 2025        â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸ•  10:00 AM  (optional)    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Requirements (optional)           â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ e.g., Need a car/truck      â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Gift/Compensation (optional)      â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ ðŸŽ e.g., Pizza, $30         â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Co-requestors (optional)          â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [+] Add people              â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

### 4.5 Favor Detail View

**Requirement FAV-FR-008**: The favor detail page MUST display:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â†  Favor Details          [Edit]  â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   ðŸ› ï¸ Favor                  [Open]  â”‚
â”‚                                     â”‚
â”‚   Help moving boxes                 â”‚
â”‚                                     â”‚
â”‚   Requested by:                     â”‚
â”‚   [Avatar] Jane D.                  â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   ðŸ“ Description                    â”‚
â”‚   I'm moving to a new apartment     â”‚
â”‚   and need help carrying boxes      â”‚
â”‚   from my car to the 3rd floor.     â”‚
â”‚   About 15 boxes total.             â”‚
â”‚                                     â”‚
â”‚   ðŸ“ Capitol Hill (near Cal        â”‚
â”‚      Anderson Park)                 â”‚
â”‚                                     â”‚
â”‚   ðŸ“… Sat, Jan 11, 2025              â”‚
â”‚   ðŸ• 10:00 AM                       â”‚
â”‚   â±ï¸ A couple of hours              â”‚
â”‚                                     â”‚
â”‚   âš ï¸ Requirements                   â”‚
â”‚   Comfortable lifting 30+ lbs       â”‚
â”‚                                     â”‚
â”‚   ðŸŽ Gift                           â”‚
â”‚   Pizza and beer after! ðŸ•ðŸº        â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   ðŸ’¬ Questions & Answers            â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Bob M. asked:               â”‚   â”‚
â”‚   â”‚ "Do you have a dolly?"      â”‚   â”‚
â”‚   â”‚   â†³ Jane D.: "Yes I do!"    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   [Ask a Question]                  â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚      ðŸ™Œ I Can Help!         â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

### 4.6 Q&A for Favors

**Requirement FAV-FR-009**: Q&A for favors works identically to rides (see `prd-ride-requests.md` section 4.6).

The `RequestQA` model supports both via `rideId` and `favorId` fields:
- For rides: `rideId` is set, `favorId` is null
- For favors: `favorId` is set, `rideId` is null

---

### 4.7 Unified Activity Type

**Requirement FAV-FR-010**: The app SHOULD define a unified `Activity` type for displaying mixed ride/favor lists:

```swift
// Core/Models/Activity.swift
import Foundation

/// Represents either a ride or favor request.
/// Used for displaying mixed lists in the dashboard.
enum Activity: Identifiable, Equatable {
    case ride(Ride)
    case favor(Favor)
    
    var id: UUID {
        switch self {
        case .ride(let ride): return ride.id
        case .favor(let favor): return favor.id
        }
    }
    
    var date: Date {
        switch self {
        case .ride(let ride): return ride.date
        case .favor(let favor): return favor.date
        }
    }
    
    var isOpen: Bool {
        switch self {
        case .ride(let ride): return ride.status == .open
        case .favor(let favor): return favor.status == .open
        }
    }
    
    var poster: Profile? {
        switch self {
        case .ride(let ride): return ride.poster
        case .favor(let favor): return favor.poster
        }
    }
    
    var claimedBy: UUID? {
        switch self {
        case .ride(let ride): return ride.claimedBy
        case .favor(let favor): return favor.claimedBy
        }
    }
    
    var userId: UUID {
        switch self {
        case .ride(let ride): return ride.userId
        case .favor(let favor): return favor.userId
        }
    }
}
```

---

### 4.8 Edit/Delete Favor

**Requirement FAV-FR-011**: Edit/delete permissions and behavior are identical to rides:
- Only poster (or co-requestors) can edit
- Only poster (or co-requestors) can delete
- Show confirmation before delete
- If claimed, notify claimer of changes/deletion

---

### 4.9 Real-time Updates

**Requirement FAV-FR-012**: Subscribe to favor changes similarly to rides:

```swift
func subscribeToFavorChanges() {
    let channel = supabase.channel("favors-changes")
    
    channel.on("postgres_changes",
               filter: ChannelFilter(event: "*", schema: "public", table: "favors")) { payload in
        Task { @MainActor in
            await self.refreshFavors()
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
| Location autocomplete | Future enhancement |
| Map view of favors | Future enhancement |
| Recurring favors | Future enhancement |
| Categories/tags for favors | Keeping it simple |
| Bidding/multiple offers | One claimer at a time |

---

## 6. Design Considerations

### Visual Differentiation from Rides

| Element | Ride | Favor |
|---------|------|-------|
| Icon | ðŸš— Car | ðŸ› ï¸ Wrench |
| Badge text | "Need Ride" | "Favor" |
| Primary color accent | Red/Primary | Amber/Orange |
| Key info | Pickup â†’ Destination | Title + Location |

### iOS-Native Patterns

| Pattern | Implementation |
|---------|---------------|
| `Picker` | For duration selection |
| `Form` | For create/edit layout |
| Toggle visibility | Optional time field |

---

## 7. Technical Considerations

### Shared Components

Both rides and favors use:
- `RequestQA` model
- `UserAvatarLink` component
- `ActivityCard` base component (polymorphic)
- Real-time subscription pattern

### Dashboard ViewModel

The dashboard should fetch both rides and favors, then merge into a single sorted list:

```swift
func fetchAllActivities() async throws -> [Activity] {
    async let rides = RideService.shared.fetchRides(status: .open)
    async let favors = FavorService.shared.fetchFavors(status: .open)
    
    let (ridesList, favorsList) = try await (rides, favors)
    
    let activities: [Activity] = 
        ridesList.map { .ride($0) } + 
        favorsList.map { .favor($0) }
    
    return activities.sorted { $0.date < $1.date }
}
```

---

## 8. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-authentication.md`
- `prd-user-profile.md`

### Used By
- `prd-request-claiming.md`
- `prd-messaging.md`
- `prd-reviews-ratings.md`

---

## 9. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Create favor request | Works end-to-end | Post new favor, appears in list |
| View favor details | All info displays | Open favor, verify all fields |
| Duration picker works | Selection persists | Select duration, verify on detail |
| Edit favor | Changes persist | Edit and verify changes saved |
| Delete favor | Removed from system | Delete and verify gone |
| Q&A works | Same as rides | Post question, verify visible |
| Real-time updates | List updates live | Create favor elsewhere, verify appears |

---

## 10. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Should favors have a separate tab from rides? | **No** | Mixed list, sorted by date |
| Can duration be changed after creation? | **Yes** | Editable like other fields |
| Should requirements be visible before claiming? | **Yes** | Help users self-select |

---

*End of PRD: Favor Requests*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Realtime Updates Section

**Replace/enhance existing realtime subscription with:**

```markdown
### Realtime Updates

**Requirement FAV-FR-015**: Subscribe to realtime favor updates using `RealtimeManager`:

```swift
// In FavorListViewModel
func subscribeToFavorUpdates() async {
    await RealtimeManager.shared.subscribe(
        channelName: "favors:open",
        table: "favors",
        filter: "status=eq.open",
        onInsert: { [weak self] payload in
            Task { @MainActor in
                await self?.handleNewFavor(payload)
            }
        },
        onUpdate: { [weak self] payload in
            Task { @MainActor in
                await self?.handleFavorUpdate(payload)
            }
        },
        onDelete: { [weak self] payload in
            Task { @MainActor in
                await self?.handleFavorDelete(payload)
            }
        }
    )
}

func unsubscribeFromFavorUpdates() async {
    await RealtimeManager.shared.unsubscribe(channelName: "favors:open")
}
```

**Requirement FAV-FR-015a**: Subscription cleanup MUST occur:
- When user navigates away from favors list (`onDisappear`)
- When app enters background (handled by `RealtimeManager`)
- When user logs out

**Requirement FAV-FR-015b**: View implementation pattern:

```swift
struct FavorsListView: View {
    @StateObject private var viewModel = FavorsListViewModel()
    
    var body: some View {
        // ... view content ...
        .task {
            await viewModel.loadFavors()
            await viewModel.subscribeToFavorUpdates()
        }
        .onDisappear {
            Task {
                await viewModel.unsubscribeFromFavorUpdates()
            }
        }
    }
}
```
```

---

## ADD: Loading with Skeleton UI

**Insert in appropriate section**

```markdown
### Favors List Loading

**Requirement FAV-FR-001a**: Favors list load sequence:

1. Show skeleton cards immediately (0ms)
2. Check cache for favors (< 50ms)
3. If cached: show cached data, fetch fresh in background
4. If not cached: show skeleton until network responds
5. Animate transition from skeleton to real data

**Requirement FAV-FR-001b**: Implementation:

```swift
struct FavorsListView: View {
    @StateObject private var viewModel = FavorsListViewModel()
    
    var body: some View {
        List {
            if viewModel.isLoading && viewModel.favors.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonFavorCard()
                        .listRowSeparator(.hidden)
                }
            } else if viewModel.favors.isEmpty {
                EmptyStateView(
                    icon: "hand.raised",
                    title: "No Favors Yet",
                    message: "Need help with something? Post a favor!"
                )
            } else {
                ForEach(viewModel.favors) { favor in
                    FavorCard(favor: favor)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .task {
            await viewModel.loadFavors()
        }
        .refreshable {
            await viewModel.refreshFavors()
        }
    }
}
```

**Requirement FAV-FR-001c**: ViewModel caching integration:

```swift
@MainActor
final class FavorsListViewModel: ObservableObject {
    @Published var favors: [Favor] = []
    @Published var isLoading = false
    @Published var error: AppError?
    
    func loadFavors() async {
        if let cached = await CacheManager.shared.getCachedFavors() {
            favors = cached
            Task { await fetchFreshFavors(showLoading: false) }
            return
        }
        await fetchFreshFavors(showLoading: true)
    }
    
    func refreshFavors() async {
        await CacheManager.shared.invalidateFavors()
        await fetchFreshFavors(showLoading: false)
    }
    
    private func fetchFreshFavors(showLoading: Bool) async {
        if showLoading { isLoading = true }
        defer { if showLoading { isLoading = false } }
        
        do {
            let freshFavors = try await FavorService.shared.fetchOpenFavors()
            favors = freshFavors
            await CacheManager.shared.cacheFavors(freshFavors)
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}
```
```

---

## ADD: Security Considerations

**Insert in Security section or create new section**

```markdown
### Security Considerations

**Requirement FAV-SEC-001**: Favor access controlled by RLS:
- Only approved users can view favors
- Users can only create favors as themselves
- Users can only update their own favors or favors they've claimed
- See `SECURITY.md` for RLS policy details

**Requirement FAV-SEC-002**: Client-side defense-in-depth:

```swift
func updateFavor(_ favor: Favor) async throws {
    guard favor.userId == AuthService.shared.currentUserId ||
          favor.claimedBy == AuthService.shared.currentUserId else {
        Log.security("Attempted to update favor without permission: \(favor.id)")
        throw AppError.unauthorized
    }
    
    try await supabase
        .from("favors")
        .update(/* ... */)
        .eq("id", favor.id.uuidString)
        .execute()
}
```

**Requirement FAV-SEC-003**: Invalidate cache after mutations:

```swift
func createFavor(_ favor: FavorCreate) async throws {
    try await supabase.from("favors").insert(favor).execute()
    await CacheManager.shared.invalidateFavors()
}
```
```

---

*End of Favor Requests Addendum*
