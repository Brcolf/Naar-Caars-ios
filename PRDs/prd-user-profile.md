# PRD: User Profile

## Document Information
- **Feature Name**: User Profile
- **Phase**: 1 (Core Experience)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`
- **Estimated Effort**: 1 week
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines the user profile functionality for the Naar's Cars iOS app. Profiles display user information, allow editing personal details, and show reviews and invite codes.

### Why does this matter?
Profiles are the identity of each community member. They help users:
- Recognize who they're getting rides from or helping
- Build trust through visible reviews and ratings
- Manage their account settings
- Invite new members to the community

### What problem does it solve?
- Users need to update their contact info (phone number for coordination)
- Users need to upload profile pictures for recognition
- Users need to see their reviews and reputation
- Users need to generate invite codes for friends

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Users can view their own profile | Profile data displays correctly |
| Users can edit their profile | Changes save and persist |
| Users can upload a profile picture | Avatar appears throughout app |
| Users can add/update phone number | Phone number saves correctly |
| Users can view their reviews | Reviews list displays |
| Users can view others' profiles | Public profile data accessible |
| Users can see their invite codes | Invite codes list displays |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| PROF-01 | User | View my profile | I can see how I appear to others |
| PROF-02 | User | Edit my name | I can fix typos or update it |
| PROF-03 | User | Upload a profile picture | Others can recognize me |
| PROF-04 | User | Add my phone number | People can contact me for ride coordination |
| PROF-05 | User | See my reviews | I know my community reputation |
| PROF-06 | User | See my average rating | I have a quick summary of my performance |
| PROF-07 | User | View another user's profile | I can learn about who I'm riding with |
| PROF-08 | User | See my invite codes | I can share them with friends |
| PROF-09 | User | Generate new invite codes | I can invite more people |
| PROF-10 | Admin | Access admin panel from profile | I can manage the community |

---

## 4. Functional Requirements

### 4.1 Profile Service

**Requirement PROF-FR-001**: The app MUST have a `ProfileService` class for profile operations:

```swift
// Core/Services/ProfileService.swift
import Foundation
import Supabase

/// Service for profile-related operations.
@MainActor
final class ProfileService {
    private let supabase = SupabaseService.shared.client
    
    static let shared = ProfileService()
    private init() {}
    
    /// Fetch a profile by user ID
    func fetchProfile(userId: UUID) async throws -> Profile {
        let response = try await supabase
            .from("profiles")
            .select()
            .eq("id", userId.uuidString)
            .single()
            .execute()
        
        let profile = try JSONDecoder().decode(Profile.self, from: response.data)
        return profile
    }
    
    /// Update the current user's profile
    func updateProfile(
        userId: UUID,
        name: String? = nil,
        phoneNumber: String? = nil,
        car: String? = nil,
        avatarUrl: String? = nil
    ) async throws {
        var updates: [String: Any] = [:]
        if let name = name { updates["name"] = name }
        if let phoneNumber = phoneNumber { updates["phone_number"] = phoneNumber }
        if let car = car { updates["car"] = car }
        if let avatarUrl = avatarUrl { updates["avatar_url"] = avatarUrl }
        
        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", userId.uuidString)
            .execute()
    }
    
    /// Upload an avatar image and return the public URL
    func uploadAvatar(userId: UUID, imageData: Data) async throws -> String {
        let fileName = "\(userId.uuidString)/avatar.jpg"
        
        try await supabase.storage
            .from("avatars")
            .upload(
                path: fileName,
                file: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        
        let publicUrl = try supabase.storage
            .from("avatars")
            .getPublicURL(path: fileName)
        
        return publicUrl.absoluteString
    }
    
    /// Fetch reviews for a user
    func fetchReviews(forUserId userId: UUID) async throws -> [Review] {
        let response = try await supabase
            .from("reviews")
            .select("*, reviewer:profiles!reviews_reviewer_id_fkey(id, name, avatar_url)")
            .eq("fulfiller_id", userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let reviews = try JSONDecoder().decode([Review].self, from: response.data)
        return reviews
    }
    
    /// Fetch invite codes created by a user
    func fetchInviteCodes(forUserId userId: UUID) async throws -> [InviteCode] {
        let response = try await supabase
            .from("invite_codes")
            .select()
            .eq("created_by", userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let codes = try JSONDecoder().decode([InviteCode].self, from: response.data)
        return codes
    }
    
    /// Generate a new invite code
    func generateInviteCode(userId: UUID) async throws -> InviteCode {
        let code = "NC" + String((0..<6).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        
        let response = try await supabase
            .from("invite_codes")
            .insert(["code": code, "created_by": userId.uuidString])
            .select()
            .single()
            .execute()
        
        let inviteCode = try JSONDecoder().decode(InviteCode.self, from: response.data)
        return inviteCode
    }
    
    /// Calculate average rating for a user
    func calculateAverageRating(userId: UUID) async throws -> Double? {
        let reviews = try await fetchReviews(forUserId: userId)
        guard !reviews.isEmpty else { return nil }
        
        let total = reviews.reduce(0) { $0 + $1.rating }
        return Double(total) / Double(reviews.count)
    }
    
    /// Count requests fulfilled by a user
    func fetchFulfilledCount(userId: UUID) async throws -> Int {
        let ridesResponse = try await supabase
            .from("rides")
            .select("id", head: true, count: .exact)
            .eq("claimed_by", userId.uuidString)
            .in("status", ["confirmed", "completed"])
            .execute()
        
        let favorsResponse = try await supabase
            .from("favors")
            .select("id", head: true, count: .exact)
            .eq("claimed_by", userId.uuidString)
            .in("status", ["confirmed", "completed"])
            .execute()
        
        return (ridesResponse.count ?? 0) + (favorsResponse.count ?? 0)
    }
}
```

---

### 4.2 Profile Data Model

**Requirement PROF-FR-002**: The Profile model MUST include all fields:

```swift
// Core/Models/Profile.swift
struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let email: String
    var car: String?
    var phoneNumber: String?
    var avatarUrl: String?
    var isAdmin: Bool
    var approved: Bool
    var invitedBy: UUID?
    let createdAt: Date
    
    // Notification preferences
    var notifyRideUpdates: Bool?
    var notifyMessages: Bool?
    var notifyAnnouncements: Bool?
    var notifyNewRequests: Bool?
    var notifyQaActivity: Bool?
    var notifyReviewReminders: Bool?
    
    // Computed properties
    var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }
    
    var formattedPhoneNumber: String? {
        guard let phone = phoneNumber else { return nil }
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 10 else { return phone }
        let last10 = String(digits.suffix(10))
        return "(\(last10.prefix(3))) \(last10.dropFirst(3).prefix(3))-\(last10.suffix(4))"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, email, car, approved
        case phoneNumber = "phone_number"
        case avatarUrl = "avatar_url"
        case isAdmin = "is_admin"
        case invitedBy = "invited_by"
        case createdAt = "created_at"
        case notifyRideUpdates = "notify_ride_updates"
        case notifyMessages = "notify_messages"
        case notifyAnnouncements = "notify_announcements"
        case notifyNewRequests = "notify_new_requests"
        case notifyQaActivity = "notify_qa_activity"
        case notifyReviewReminders = "notify_review_reminders"
    }
}
```

---

### 4.3 My Profile View

**Requirement PROF-FR-003**: The current user's profile screen MUST display:

| Section | Content |
|---------|---------|
| Header | Avatar (editable), name, email |
| Stats | Average rating, number of reviews, requests fulfilled |
| Actions | Edit Profile button |
| Invite Codes | List of codes with status (available/used), Generate button |
| Reviews | List of received reviews with rating, reviewer, summary |
| Admin Link | (If admin) Link to Admin Panel |
| Logout | Logout button at bottom |

**Requirement PROF-FR-004**: My Profile View wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   My Profile              [Logout]  â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”                 â”‚
â”‚        â”‚  Avatar  â”‚  [camera icon]  â”‚
â”‚        â”‚   (tap)  â”‚                 â”‚
â”‚        â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜                 â”‚
â”‚                                     â”‚
â”‚         John Smith                  â”‚
â”‚      john@example.com               â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚    Edit Profile    â†’        â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   ðŸ“Š Stats                          â”‚
â”‚   â˜… 4.8 average  â€¢  12 reviews      â”‚
â”‚   ðŸ† 25 requests fulfilled          â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   ðŸŽŸï¸ Invite Codes      [+ Generate] â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  NC7X9K2A      Available    â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚  NCAB3DEF      Used         â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   â­ My Reviews                      â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar] Jane D.    â˜…â˜…â˜…â˜…â˜…   â”‚   â”‚
â”‚   â”‚ "Great driver, very helpful" â”‚   â”‚
â”‚   â”‚ Dec 15, 2024                â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ [Avatar] Bob M.     â˜…â˜…â˜…â˜…â˜†   â”‚   â”‚
â”‚   â”‚ "Punctual and friendly"     â”‚   â”‚
â”‚   â”‚ Dec 10, 2024                â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   (If admin:)                       â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  ðŸ›¡ï¸ Admin Panel    â†’        â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

### 4.4 My Profile ViewModel

**Requirement PROF-FR-005**: MyProfileViewModel implementation:

```swift
// Features/Profile/ViewModels/MyProfileViewModel.swift
import Foundation
import SwiftUI

@MainActor
final class MyProfileViewModel: ObservableObject {
    @Published var profile: Profile?
    @Published var reviews: [Review] = []
    @Published var inviteCodes: [InviteCode] = []
    @Published var averageRating: Double?
    @Published var fulfilledCount: Int = 0
    
    @Published var isLoading = false
    @Published var error: AppError?
    
    private let profileService = ProfileService.shared
    
    func loadProfile(userId: UUID) async {
        isLoading = true
        
        do {
            async let profileTask = profileService.fetchProfile(userId: userId)
            async let reviewsTask = profileService.fetchReviews(forUserId: userId)
            async let codesTask = profileService.fetchInviteCodes(forUserId: userId)
            async let ratingTask = profileService.calculateAverageRating(userId: userId)
            async let countTask = profileService.fetchFulfilledCount(userId: userId)
            
            let (profile, reviews, codes, rating, count) = try await (
                profileTask, reviewsTask, codesTask, ratingTask, countTask
            )
            
            self.profile = profile
            self.reviews = reviews
            self.inviteCodes = codes
            self.averageRating = rating
            self.fulfilledCount = count
        } catch {
            self.error = error as? AppError ?? .unknown(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    func generateInviteCode(userId: UUID) async {
        do {
            let newCode = try await profileService.generateInviteCode(userId: userId)
            inviteCodes.insert(newCode, at: 0)
        } catch {
            self.error = error as? AppError ?? .unknown(error.localizedDescription)
        }
    }
}
```

---

### 4.5 Edit Profile View

**Requirement PROF-FR-006**: The Edit Profile screen MUST allow editing:

| Field | Editable | Validation |
|-------|----------|------------|
| Avatar | Yes (via PhotosPicker) | Max 5MB, image only |
| Name | Yes | 2-100 characters |
| Email | No (display only) | - |
| Phone Number | Yes | Valid phone format, optional |
| Car | Yes | Max 100 characters, optional |

**Requirement PROF-FR-007**: Edit Profile View wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â†  Edit Profile          [Save]   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”                 â”‚
â”‚        â”‚  Avatar  â”‚                 â”‚
â”‚        â”‚   (tap   â”‚                 â”‚
â”‚        â”‚ to changeâ”‚                 â”‚
â”‚        â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜                 â”‚
â”‚       Change Photo                  â”‚
â”‚                                     â”‚
â”‚   Name                              â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ John Smith                  â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Email (cannot be changed)         â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ john@example.com            â”‚   â”‚  (grayed out)
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Phone Number                      â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ (206) 555-1234              â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   Used for ride coordination        â”‚
â”‚                                     â”‚
â”‚   Car                               â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Blue Honda Civic            â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   Helps others identify your car    â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

### 4.6 Avatar Upload

**Requirement PROF-FR-008**: Avatar upload MUST use iOS native `PhotosPicker`:

```swift
// Features/Profile/Views/EditProfileView.swift
import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @StateObject private var viewModel: EditProfileViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: Image?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            // Avatar Section
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        VStack {
                            if let avatarImage {
                                avatarImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                AvatarView(
                                    url: viewModel.avatarUrl,
                                    name: viewModel.name,
                                    size: 100
                                )
                            }
                            Text("Change Photo")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
            
            // Name Section
            Section("Name") {
                TextField("Full Name", text: $viewModel.name)
                    .textContentType(.name)
            }
            
            // Email Section (read-only)
            Section("Email") {
                Text(viewModel.email)
                    .foregroundColor(.secondary)
            }
            
            // Phone Section
            Section {
                TextField("Phone Number", text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } header: {
                Text("Phone Number")
            } footer: {
                Text("Used for ride coordination. Required to claim requests.")
            }
            
            // Car Section
            Section {
                TextField("Car Description", text: $viewModel.car)
            } header: {
                Text("Car")
            } footer: {
                Text("e.g., Blue Honda Civic - helps others identify your car")
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await viewModel.saveProfile()
                        dismiss()
                    }
                }
                .disabled(viewModel.isSaving || !viewModel.hasChanges)
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                await loadAndUploadPhoto(item: newValue)
            }
        }
    }
    
    private func loadAndUploadPhoto(item: PhotosPickerItem?) async {
        guard let item else { return }
        
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return
        }
        
        // Resize image if needed
        guard let uiImage = UIImage(data: data),
              let resizedData = uiImage.jpegData(compressionQuality: 0.7) else {
            return
        }
        
        // Show preview immediately
        avatarImage = Image(uiImage: uiImage)
        
        // Upload to server
        await viewModel.uploadAvatar(imageData: resizedData)
    }
}
```

---

### 4.7 Phone Number Validation

**Requirement PROF-FR-009**: Phone numbers MUST be validated:

```swift
// Core/Utilities/Validators.swift
enum Validators {
    /// Validates and formats a US phone number
    static func formatPhoneNumber(_ input: String) -> String? {
        let digits = input.filter { $0.isNumber }
        
        if digits.count == 10 {
            return "+1\(digits)"
        } else if digits.count == 11 && digits.first == "1" {
            return "+\(digits)"
        }
        
        return nil
    }
    
    /// Checks if phone number is valid
    static func isValidPhoneNumber(_ input: String) -> Bool {
        return formatPhoneNumber(input) != nil
    }
    
    /// Formats for display: (206) 555-1234
    static func displayPhoneNumber(_ e164: String) -> String {
        let digits = e164.filter { $0.isNumber }
        guard digits.count >= 10 else { return e164 }
        let last10 = String(digits.suffix(10))
        return "(\(last10.prefix(3))) \(last10.dropFirst(3).prefix(3))-\(last10.suffix(4))"
    }
}
```

---

### 4.8 Public Profile View

**Requirement PROF-FR-010**: When viewing another user's profile:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â†  Back                           â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚        â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”                 â”‚
â”‚        â”‚  Avatar  â”‚                 â”‚
â”‚        â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜                 â”‚
â”‚                                     â”‚
â”‚         Jane Doe                    â”‚
â”‚      jane@example.com               â”‚
â”‚      ðŸ“ž (206) 555-4321              â”‚
â”‚      ðŸš— Red Toyota Camry            â”‚
â”‚                                     â”‚
â”‚   â˜… 4.9 average  â€¢  8 reviews       â”‚
â”‚   ðŸ† 15 requests fulfilled          â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚    ðŸ’¬ Send Message          â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   â­ Reviews                         â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar] John S.    â˜…â˜…â˜…â˜…â˜…   â”‚   â”‚
â”‚   â”‚ "Very helpful and kind!"    â”‚   â”‚
â”‚   â”‚ Dec 15, 2024                â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement PROF-FR-011**: Public profile shows:
- Avatar, name, email, phone (if set), car (if set)
- Average rating and review count
- Fulfilled requests count
- "Send Message" button
- List of reviews

**Requirement PROF-FR-012**: If viewing own profile via public route, redirect to My Profile.

---

### 4.9 Review Display Component

**Requirement PROF-FR-013**: Reusable review card component:

```swift
// UI/Components/Cards/ReviewCard.swift
struct ReviewCard: View {
    let review: Review
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let reviewer = review.reviewer {
                    UserAvatarLink(
                        userId: reviewer.id,
                        name: reviewer.name,
                        avatarUrl: reviewer.avatarUrl,
                        size: 32
                    )
                }
                
                Spacer()
                
                StarRatingView(rating: .constant(review.rating), interactive: false, size: 14)
            }
            
            Text(review.summary)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Text(review.createdAt.friendlyRelativeString)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
```

---

### 4.10 Invite Code Display

**Requirement PROF-FR-014**: Invite code row with copy/share actions:

```swift
// UI/Components/Common/InviteCodeRow.swift
struct InviteCodeRow: View {
    let code: InviteCode
    @State private var showCopied = false
    
    var body: some View {
        HStack {
            Text(code.code)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            
            Spacer()
            
            if code.isUsed {
                Text("Used")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            } else {
                Text("Available")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            copyToClipboard()
        }
        .swipeActions(edge: .trailing) {
            Button {
                shareCode()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
            
            Button {
                copyToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.orange)
        }
        .overlay(alignment: .center) {
            if showCopied {
                Text("Copied!")
                    .font(.caption)
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .transition(.opacity)
            }
        }
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = code.code
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        withAnimation {
            showCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
            }
        }
    }
    
    private func shareCode() {
        let message = """
        Join me on Naar's Cars! ðŸš—
        
        Use invite code: \(code.code)
        Sign up at: https://naarscars.com/signup?code=\(code.code)
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [message],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
```

---

### 4.11 Logout

**Requirement PROF-FR-015**: Logout with confirmation:

```swift
struct LogoutButton: View {
    @State private var showConfirmation = false
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Button(role: .destructive) {
            showConfirmation = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Log Out")
            }
        }
        .alert("Log Out?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) {
                Task {
                    try? await AuthService.shared.logOut()
                    appState.currentUser = nil
                }
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
    }
}
```

---

## 5. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Account deletion | Handled by admin |
| Change email | Requires re-verification |
| Change password | Use "Forgot Password" from login |
| Profile visibility settings | All profiles visible to members |
| Block/report users | Future enhancement |
| SMS invite sending | Web-only feature for now |

---

## 6. Design Considerations

### iOS-Native Patterns

| Pattern | Implementation |
|---------|---------------|
| `PhotosPicker` | Native iOS photo selection |
| `Form` | For edit profile layout |
| `List` | For profile sections |
| `.swipeActions` | For invite code actions |
| Share sheet | Native UIActivityViewController |
| `.alert` | Confirmation dialogs |

### Improvements Over Web App

| Web Behavior | iOS Improvement |
|--------------|-----------------|
| Custom image picker | Native PhotosPicker |
| Toast notifications | Haptic feedback |
| Modal editing | Push navigation |
| Manual refresh | Pull-to-refresh |

---

## 7. Technical Considerations

### Image Upload
- Storage bucket: `avatars`
- File path: `{userId}/avatar.jpg`
- Upsert mode: Replace existing
- Max size: 1MB (compress before upload)

### Performance
- Cache profile images with AsyncImage
- Lazy load reviews if > 10
- Debounce profile saves

---

## 8. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-authentication.md`

### Used By
- `prd-ride-requests.md` (user display)
- `prd-messaging.md` (start DM)
- `prd-invite-system.md` (code management)

---

## 9. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| View own profile | Data displays | Load profile screen |
| Edit profile | Changes save | Edit and verify |
| Upload avatar | Image appears | Upload and verify |
| View public profile | Data displays | Navigate to other user |
| Generate invite code | Code created | Tap generate |
| Share invite code | Share sheet opens | Tap share |

---

## 10. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Show email on public profile? | **Yes** | Community members should be able to contact |
| Allow multiple avatar uploads? | **No** | One at a time, replace existing |
| Show "joined date" on profile? | **Optional** | Nice to have but not required |

---

*End of PRD: User Profile*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 4.5 - Edit Profile View (Phone Number Field)

**Enhance existing phone field with visibility disclosure:**

```markdown
### 4.5 Edit Profile View

**Requirement PROF-FR-006**: Edit profile fields (existing).

**Requirement PROF-FR-006a**: Phone number field MUST include visibility disclosure:

```
┌─────────────────────────────────────┐
│   Phone Number                      │
│   ┌─────────────────────────────┐   │
│   │ (206) 555-1234              │   │
│   └─────────────────────────────┘   │
│   ⓘ Your phone number will be      │
│   visible to community members      │
│   for ride coordination.            │
└─────────────────────────────────────┘
```

**Requirement PROF-FR-006b**: Implementation:

```swift
struct EditProfileView: View {
    @StateObject private var viewModel: EditProfileViewModel
    
    var body: some View {
        Form {
            // ... other fields ...
            
            Section {
                TextField("Phone Number", text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                
                // Visibility disclosure
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("Your phone number will be visible to community members for ride coordination.")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("Contact")
            }
        }
    }
}
```

**Requirement PROF-FR-006c**: First time adding phone number, show confirmation alert:

```swift
func saveProfile() async {
    // Check if adding phone for first time
    let hadPhoneBefore = originalProfile?.phoneNumber != nil
    let hasPhoneNow = !phoneNumber.isEmpty
    
    if !hadPhoneBefore && hasPhoneNow && !hasShownPhoneDisclosure {
        showPhoneConfirmation = true
        return
    }
    
    await performSave()
}
```

Alert content:
- Title: "Phone Number Visibility"
- Message: "Your phone number will be visible to other Naar's Cars members to coordinate rides and favors. Continue?"
- Actions: "Yes, Save Number", "Cancel"
```

---

## REVISE: Section 4.6 - Avatar Upload

**Replace existing avatar upload with compression:**

```markdown
### 4.6 Avatar Upload

**Requirement PROF-FR-008**: Avatar upload with compression:

```swift
private func loadAndUploadPhoto(item: PhotosPickerItem?) async {
    guard let item else { return }
    
    isUploadingAvatar = true
    defer { isUploadingAvatar = false }
    
    // Load image data
    guard let data = try? await item.loadTransferable(type: Data.self),
          let uiImage = UIImage(data: data) else {
        error = .unknown("Failed to load image")
        return
    }
    
    // Compress using avatar preset
    guard let compressedData = ImageCompressor.compress(uiImage, preset: .avatar) else {
        error = .unknown("Image too large. Please try a different photo.")
        return
    }
    
    // Show preview immediately
    avatarImage = Image(uiImage: UIImage(data: compressedData) ?? uiImage)
    
    // Upload compressed data
    do {
        let url = try await ProfileService.shared.uploadAvatar(
            imageData: compressedData,
            userId: profile.id
        )
        
        // Update profile with new URL (include cache-buster)
        let cacheBustedUrl = "\(url)?v=\(Int(Date().timeIntervalSince1970))"
        try await ProfileService.shared.updateAvatarUrl(cacheBustedUrl)
        
        HapticFeedback.success()
    } catch {
        self.error = .unknown("Failed to upload photo")
        // Reset preview
        avatarImage = nil
    }
}
```

**Requirement PROF-FR-008a**: Avatar specifications:

| Property | Value |
|----------|-------|
| Max dimensions | 400x400 pixels |
| Max file size | 200KB |
| Format | JPEG |
| Quality | Auto-adjusted to meet size |

**Requirement PROF-FR-008b**: Photo permissions handling:

```swift
// Check if photo access denied
if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .denied {
    showPhotoAccessDeniedAlert = true
}
```

Photo access denied alert:
- Title: "Photo Access Required"
- Message: "To change your profile photo, please enable photo access in Settings."
- Actions: "Open Settings" (deep link), "Cancel"

```swift
func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
```
```

---

## REVISE: Section 4.7 - Phone Number Validation

**Replace existing validation with international support:**

```markdown
### 4.7 Phone Number Validation

**Requirement PROF-FR-009**: Phone validation with international support:

```swift
enum Validators {
    /// Validates phone number (US or international)
    static func isValidPhoneNumber(_ input: String) -> Bool {
        let digits = input.filter { $0.isNumber }
        // Accept 10 digits (US) or 11-15 digits (international with country code)
        return digits.count >= 10 && digits.count <= 15
    }
    
    /// Formats for storage (E.164 format)
    static func formatPhoneForStorage(_ input: String) -> String? {
        let digits = input.filter { $0.isNumber }
        
        if digits.count == 10 {
            // Assume US
            return "+1\(digits)"
        } else if digits.count == 11 && digits.first == "1" {
            // US with country code
            return "+\(digits)"
        } else if digits.count >= 11 && digits.count <= 15 {
            // International - assume has country code
            return "+\(digits)"
        }
        
        return nil
    }
    
    /// Formats for display (US-friendly)
    static func displayPhoneNumber(_ e164: String, masked: Bool = false) -> String {
        let digits = e164.filter { $0.isNumber }
        guard digits.count >= 10 else { return e164 }
        
        let last4 = String(digits.suffix(4))
        
        if masked {
            return "(•••) •••-\(last4)"
        }
        
        // Full display for US numbers
        if digits.count == 11 && digits.first == "1" {
            let areaCode = String(digits.dropFirst().prefix(3))
            let prefix = String(digits.dropFirst(4).prefix(3))
            return "(\(areaCode)) \(prefix)-\(last4)"
        }
        
        // International: just show with + prefix
        return "+\(digits)"
    }
}
```

**Requirement PROF-FR-009a**: Validation error messages:

| Input | Error Message |
|-------|---------------|
| Less than 10 digits | "Please enter a valid phone number" |
| More than 15 digits | "Please enter a valid phone number" |
| Non-numeric characters only | "Please enter a valid phone number" |
| Valid number | No error |

**Requirement PROF-FR-009b**: Real-time formatting in text field:

```swift
TextField("Phone Number", text: $phoneNumber)
    .keyboardType(.phonePad)
    .onChange(of: phoneNumber) { _, newValue in
        // Format as user types (US format)
        phoneNumber = formatPhoneInput(newValue)
    }

func formatPhoneInput(_ input: String) -> String {
    let digits = input.filter { $0.isNumber }
    var result = ""
    
    for (index, digit) in digits.prefix(10).enumerated() {
        if index == 0 { result += "(" }
        if index == 3 { result += ") " }
        if index == 6 { result += "-" }
        result += String(digit)
    }
    
    return result
}
```
```

---

## REVISE: Section 4.8 - Public Profile View

**Enhance with phone masking:**

```markdown
### 4.8 Public Profile View

**Requirement PROF-FR-010**: Public profile display (existing).

**Requirement PROF-FR-010a**: Phone number MUST be masked on public profiles by default:

```
┌─────────────────────────────────────┐
│      📞 (•••) •••-4321              │
│         [Reveal Number]             │
└─────────────────────────────────────┘
```

**Requirement PROF-FR-010b**: "Reveal Number" button implementation:

```swift
struct PublicProfileView: View {
    let profile: Profile
    @State private var isPhoneRevealed = false
    
    var body: some View {
        // ... other content ...
        
        if let phone = profile.phoneNumber {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "phone.fill")
                    Text(isPhoneRevealed 
                        ? Validators.displayPhoneNumber(phone, masked: false)
                        : Validators.displayPhoneNumber(phone, masked: true))
                }
                .font(.body)
                
                if !isPhoneRevealed && !shouldAutoReveal {
                    Button("Reveal Number") {
                        withAnimation {
                            isPhoneRevealed = true
                        }
                        HapticFeedback.light()
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
    
    /// Auto-reveal if user has relationship with profile owner
    private var shouldAutoReveal: Bool {
        // Auto-reveal if viewing own profile
        if profile.id == AuthService.shared.currentUserId {
            return true
        }
        
        // Auto-reveal if in active conversation
        if ConversationService.shared.hasConversationWith(userId: profile.id) {
            return true
        }
        
        // Auto-reveal if on same request (claimer/poster)
        if ClaimService.shared.hasSharedRequest(with: profile.id) {
            return true
        }
        
        return false
    }
}
```

**Requirement PROF-FR-010c**: Phone number shown unmasked when:

| Scenario | Auto-Reveal |
|----------|-------------|
| Viewing own profile | Yes |
| User has active conversation with profile owner | Yes |
| User is claimer/poster on same request | Yes |
| Other cases | No (show masked + reveal button) |

**Requirement PROF-FR-010d**: Revealed state persists for session only:
- Reset on app restart
- Reset when navigating away from profile
```

---

## ADD: Section 6.1 - Privacy Considerations

**Insert in appropriate section or create new**

```markdown
### 6.1 Privacy Considerations

**Requirement PROF-PRIV-001**: Phone number visibility is disclosed:
- Inline help text on edit screen
- Confirmation alert on first save
- See `PRIVACY-DISCLOSURES.md` for full requirements

**Requirement PROF-PRIV-002**: Photo permissions handled gracefully:
- Permission requested only when user initiates photo selection
- Clear explanation if permission denied
- Settings deep-link offered

**Requirement PROF-PRIV-003**: Profile data retention:
- Profile data retained until account deletion
- Avatar images retained until changed or account deleted
- See `PRIVACY-DISCLOSURES.md` for data retention policy
```

---

*End of User Profile Addendum*
