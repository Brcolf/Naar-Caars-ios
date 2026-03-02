# Review Workflow Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix review re-loading from bell notifications, fix past requests toggle labels, remove 7-day review window, add inline review display on completed request details, and add an all-reviews list view from the profile.

**Architecture:** Five independent improvements to the existing review system. No new database migrations needed — all changes are client-side. The inline review section is a new reusable SwiftUI component. The all-reviews list reuses existing `ReviewCard` with enhanced data fetching.

**Tech Stack:** SwiftUI, Supabase PostgREST queries, existing ReviewService/ProfileService

---

### Task 1: Fix Bell Notification Review Re-loading

**Problem:** `NavigationCoordinator.showReviewPrompt` stays `true` after the review prompt is dismissed interactively (backgrounding the app). When the user later taps the notification, setting `showReviewPrompt = true` is a no-op because it's already `true`, so the `onChange` in `MainTabView` doesn't fire.

**Files:**
- Modify: `NaarsCars/App/MainTabView.swift:181-222`

**Step 1: Add onDismiss handler to the fullScreenCover**

The `fullScreenCover(item:)` at line 181 has no `onDismiss` handler. When the user dismisses the sheet by backgrounding (or any interactive dismiss), neither `onReviewSubmitted` nor `onReviewSkipped` fires, leaving `showReviewPrompt = true`. Add an `onDismiss` closure that resets the state.

In `MainTabView.swift`, change line 181 from:

```swift
.fullScreenCover(item: $promptCoordinator.activePrompt) { prompt in
```

to:

```swift
.fullScreenCover(item: $promptCoordinator.activePrompt, onDismiss: {
    navigationCoordinator.resetReviewPrompt()
}) { prompt in
```

This ensures that regardless of HOW the sheet is dismissed (submitted, skipped, interactive dismiss, backgrounding), `showReviewPrompt` gets reset to `false`. The `resetReviewPrompt()` calls inside `onReviewSubmitted`/`onReviewSkipped` become redundant but harmless — calling reset twice is safe since it just sets booleans to false/nil.

**Step 2: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/App/MainTabView.swift
git commit -m "fix: reset review prompt state on sheet dismiss to fix bell re-loading"
```

---

### Task 2: Fix Past Requests Toggle Labels

**Problem:** `PastRequestFilter` raw values `"ride_edit_my_past_requests"` and `"ride_edit_helped_with"` are used as localization keys, but these keys don't exist in `Localizable.xcstrings`. The raw strings with underscores are displayed.

**Files:**
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Step 1: Add localization entries**

Add the following keys to `Localizable.xcstrings`. Each entry follows the established JSON structure in the file. Insert these entries in alphabetical order among existing `ride_edit_*` entries.

Keys to add with English values:
- `ride_edit_my_past_requests` → "My Past Requests"
- `ride_edit_helped_with` → "Rides I Helped With"
- `ride_edit_no_past_requests` → "No Past Requests" (verify if missing)
- `ride_edit_past_requests_title` → "Past Requests" (verify if missing)
- `ride_edit_no_past_requests_mine` → "You haven't posted any completed requests yet." (verify if missing)
- `ride_edit_no_past_requests_helped` → "You haven't helped with any requests yet." (verify if missing)

For each key, provide all 6 languages (en, es, ko, vi, zh-Hans, zh-Hant). Use the same JSON structure as existing entries:

```json
"ride_edit_my_past_requests" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "My Past Requests"
      }
    },
    "es" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Mis solicitudes pasadas"
      }
    },
    "ko" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "내 과거 요청"
      }
    },
    "vi" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Yêu cầu trước đây"
      }
    },
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "我的过去请求"
      }
    },
    "zh-Hant" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "我的過去請求"
      }
    }
  }
}
```

```json
"ride_edit_helped_with" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Rides I Helped With"
      }
    },
    "es" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Viajes en los que ayudé"
      }
    },
    "ko" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "내가 도운 라이드"
      }
    },
    "vi" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Chuyến đi tôi đã giúp"
      }
    },
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "我帮助过的行程"
      }
    },
    "zh-Hant" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "我幫助過的行程"
      }
    }
  }
}
```

**Important:** First search the xcstrings file for each key to confirm which ones are actually missing before adding. Only add missing ones.

**Step 2: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/Resources/Localizable.xcstrings
git commit -m "fix: add missing localization keys for past requests toggle labels"
```

---

### Task 3: Remove 7-Day Review Window

**Files:**
- Modify: `NaarsCars/Core/Services/ReviewService.swift:143-175`
- Modify: `NaarsCars/Core/Services/ReviewPromptProvider.swift:94-136`

**Step 1: Simplify `canStillReview` to always return true**

In `ReviewService.swift`, replace lines 143-175 (the entire `canStillReview` method) with:

```swift
/// Check if user can still review a request
/// - Parameters:
///   - requestType: "ride" or "favor"
///   - requestId: Request ID
/// - Returns: Always true — reviews have no time limit
func canStillReview(
    requestType: String,
    requestId: UUID
) async throws -> Bool {
    return true
}
```

This removes the Supabase query and the 7-day calculation. The method signature is preserved so all callers continue to work without changes.

**Step 2: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Run existing tests**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:NaarsCarsTests/PromptCoordinatorTests 2>&1 | tail -20`
Expected: All tests pass

**Step 4: Commit**

```bash
git add NaarsCars/Core/Services/ReviewService.swift
git commit -m "feat: remove 7-day review window — reviews can be left at any time"
```

---

### Task 4: Add `fetchReviewForRequest` to ReviewService

**Files:**
- Modify: `NaarsCars/Core/Services/ReviewService.swift`

**Step 1: Add the new method**

Add this method to `ReviewService` after the `canStillReview` method (around line 155, after Task 3's changes):

```swift
/// Fetch the review for a specific request
/// - Parameters:
///   - requestType: "ride" or "favor"
///   - requestId: The request UUID
/// - Returns: The review if one exists, nil otherwise
func fetchReviewForRequest(
    requestType: String,
    requestId: UUID
) async throws -> Review? {
    let column = requestType == "ride" ? "ride_id" : "favor_id"

    let response: [Review] = try await supabase
        .from("reviews")
        .select()
        .eq(column, value: requestId.uuidString)
        .limit(1)
        .execute()
        .value

    return response.first
}
```

**Step 2: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/Core/Services/ReviewService.swift
git commit -m "feat: add fetchReviewForRequest method to ReviewService"
```

---

### Task 5: Create RequestReviewSection Component

**Files:**
- Create: `NaarsCars/Features/Reviews/Views/RequestReviewSection.swift`

**Step 1: Create the component**

Create `NaarsCars/Features/Reviews/Views/RequestReviewSection.swift`:

```swift
//
//  RequestReviewSection.swift
//  NaarsCars
//
//  Inline review display for completed request detail views
//

import SwiftUI

/// Displays an existing review inline, or a "Leave a Review" button if the poster hasn't reviewed yet.
struct RequestReviewSection: View {
    let requestType: String
    let requestId: UUID
    let posterId: UUID
    let claimerId: UUID?
    let isCompleted: Bool
    let requestTitle: String
    var onReviewSubmitted: (() -> Void)?

    @State private var review: Review?
    @State private var reviewerProfile: Profile?
    @State private var isLoading = true
    @State private var showLeaveReview = false

    private var isCurrentUserPoster: Bool {
        AuthService.shared.currentUserId == posterId
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.naarsCardBackground)
                    .cornerRadius(12)
            } else if let review = review {
                reviewDisplay(review)
            } else if isCurrentUserPoster && isCompleted && claimerId != nil {
                addReviewButton
            }
        }
        .task {
            await loadReview()
        }
        .sheet(isPresented: $showLeaveReview) {
            if let claimerId = claimerId {
                LeaveReviewView(
                    requestType: requestType,
                    requestId: requestId,
                    requestTitle: requestTitle,
                    fulfillerId: claimerId,
                    fulfillerName: reviewerProfile?.name ?? "Someone",
                    onReviewSubmitted: {
                        Task {
                            await loadReview()
                            onReviewSubmitted?()
                        }
                    },
                    onReviewSkipped: {}
                )
            }
        }
    }

    // MARK: - Review Display

    private func reviewDisplay(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("review_section_title".localized)
                .font(.naarsTitle3)

            ReviewCard(
                review: review,
                reviewerName: reviewerProfile?.name,
                reviewerAvatarUrl: reviewerProfile?.avatarUrl
            )
        }
        .cardStyle()
    }

    // MARK: - Add Review Button

    private var addReviewButton: some View {
        Button {
            showLeaveReview = true
        } label: {
            HStack {
                Image(systemName: "star.bubble")
                Text("review_leave_review".localized)
                    .font(.naarsHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Data Loading

    private func loadReview() async {
        defer { isLoading = false }
        do {
            let fetchedReview = try await ReviewService.shared.fetchReviewForRequest(
                requestType: requestType,
                requestId: requestId
            )
            self.review = fetchedReview
            if let reviewerId = fetchedReview?.reviewerId {
                self.reviewerProfile = try? await ProfileService.shared.fetchProfile(userId: reviewerId)
            }
        } catch {
            AppLogger.error("reviews", "Failed to load review for request: \(error)")
        }
    }
}
```

**Step 2: Add localization keys**

Add to `Localizable.xcstrings`:
- `review_section_title` → "Review" (en), with all 6 languages
- `review_leave_review` → "Leave a Review" (en), with all 6 languages

**Step 3: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add NaarsCars/Features/Reviews/Views/RequestReviewSection.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add RequestReviewSection component for inline review display"
```

---

### Task 6: Add RequestReviewSection to RideDetailView

**Files:**
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift`

**Step 1: Insert RequestReviewSection after the claimer card**

In `RideDetailView.swift`, after the claimer card section (after line 434 — the closing `}` of the `if let claimer = ride.claimer` block), and before line 436 (the Flight section comment), insert:

```swift
// Review Section (for completed rides)
if ride.claimedBy != nil {
    RequestReviewSection(
        requestType: "ride",
        requestId: ride.id,
        posterId: ride.userId,
        claimerId: ride.claimedBy,
        isCompleted: ride.status == .completed,
        requestTitle: "\(ride.pickup) → \(ride.destination)",
        onReviewSubmitted: {
            Task { await viewModel.loadRide(id: rideId) }
        }
    )
}
```

**Step 2: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/Features/Rides/Views/RideDetailView.swift
git commit -m "feat: add inline review section to RideDetailView for completed rides"
```

---

### Task 7: Add RequestReviewSection to FavorDetailView

**Files:**
- Modify: `NaarsCars/Features/Favors/Views/FavorDetailView.swift`

**Step 1: Insert RequestReviewSection after the claimer card**

In `FavorDetailView.swift`, after the claimer card section (after line 344 — the closing `}` of the `if let claimer = favor.claimer` block), and before line 346 (the Requirements & Gift section), insert:

```swift
// Review Section (for completed favors)
if favor.claimedBy != nil {
    RequestReviewSection(
        requestType: "favor",
        requestId: favor.id,
        posterId: favor.userId,
        claimerId: favor.claimedBy,
        isCompleted: favor.status == .completed,
        requestTitle: favor.title,
        onReviewSubmitted: {
            Task { await viewModel.loadFavor(id: favorId) }
        }
    )
}
```

**Step 2: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/Features/Favors/Views/FavorDetailView.swift
git commit -m "feat: add inline review section to FavorDetailView for completed favors"
```

---

### Task 8: Extend Review Model with Joined Fields

**Files:**
- Modify: `NaarsCars/Core/Models/Review.swift`

**Step 1: Add optional joined fields**

In `Review.swift`, add these fields after the existing `fulfillerName` (line 23):

```swift
var reviewerName: String?
var reviewerAvatarUrl: String?
var requestTitle: String?
```

These are computed/joined fields (not from the database), matching the existing `fulfillerName` pattern. They don't need `CodingKeys` entries since they're `var` with default `nil` and the decoder will simply skip them.

**Step 2: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/Core/Models/Review.swift
git commit -m "feat: add reviewer and request context fields to Review model"
```

---

### Task 9: Enhance ProfileService.fetchReviews with Joined Data

**Files:**
- Modify: `NaarsCars/Core/Services/ProfileService.swift:288-298`

**Step 1: Enhance the fetchReviews method**

Replace the existing `fetchReviews(forUserId:)` method with a version that fetches reviewer profiles and request titles. The current implementation only fetches raw reviews without any joined data.

Replace lines 288-298 with:

```swift
func fetchReviews(forUserId userId: UUID) async throws -> [Review] {
    var reviews: [Review] = try await supabase
        .from("reviews")
        .select()
        .eq("fulfiller_id", value: userId.uuidString)
        .order("created_at", ascending: false)
        .execute()
        .value

    // Batch-fetch reviewer profiles
    let reviewerIds = Array(Set(reviews.map(\.reviewerId)))
    let profiles = try await fetchProfiles(userIds: reviewerIds)
    let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

    // Batch-fetch ride titles
    let rideIds = reviews.compactMap(\.rideId)
    var rideTitleMap: [UUID: String] = [:]
    if !rideIds.isEmpty {
        struct RideTitle: Decodable {
            let id: UUID
            let pickup: String
            let destination: String
        }
        let rides: [RideTitle] = try await supabase
            .from("rides")
            .select("id, pickup, destination")
            .in("id", values: rideIds.map(\.uuidString))
            .execute()
            .value
        for ride in rides {
            rideTitleMap[ride.id] = "\(ride.pickup) → \(ride.destination)"
        }
    }

    // Batch-fetch favor titles
    let favorIds = reviews.compactMap(\.favorId)
    var favorTitleMap: [UUID: String] = [:]
    if !favorIds.isEmpty {
        struct FavorTitle: Decodable {
            let id: UUID
            let title: String
        }
        let favors: [FavorTitle] = try await supabase
            .from("favors")
            .select("id, title")
            .in("id", values: favorIds.map(\.uuidString))
            .execute()
            .value
        for favor in favors {
            favorTitleMap[favor.id] = favor.title
        }
    }

    // Enrich reviews with joined data
    for i in reviews.indices {
        let profile = profileMap[reviews[i].reviewerId]
        reviews[i].reviewerName = profile?.name
        reviews[i].reviewerAvatarUrl = profile?.avatarUrl
        if let rideId = reviews[i].rideId {
            reviews[i].requestTitle = rideTitleMap[rideId]
        } else if let favorId = reviews[i].favorId {
            reviews[i].requestTitle = favorTitleMap[favorId]
        }
    }

    return reviews
}
```

**Step 2: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add NaarsCars/Core/Services/ProfileService.swift
git commit -m "feat: enhance fetchReviews to include reviewer profiles and request titles"
```

---

### Task 10: Create AllReviewsView

**Files:**
- Create: `NaarsCars/Features/Reviews/Views/AllReviewsView.swift`

**Step 1: Create the view**

Create `NaarsCars/Features/Reviews/Views/AllReviewsView.swift`:

```swift
//
//  AllReviewsView.swift
//  NaarsCars
//
//  Scrollable list of all reviews left for the current user
//

import SwiftUI

struct AllReviewsView: View {
    let userId: UUID
    @State private var reviews: [Review] = []
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading && reviews.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonReviewCard()
                        }
                    }
                    .padding()
                }
            } else if let error = error, reviews.isEmpty {
                ErrorView(
                    error: error,
                    retryAction: { Task { await loadReviews() } }
                )
            } else if reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "profile_no_reviews".localized,
                    message: "profile_no_reviews_message".localized,
                    customImage: "naars_Profile_icon"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(reviews) { review in
                            VStack(alignment: .leading, spacing: 8) {
                                ReviewCard(
                                    review: review,
                                    reviewerName: review.reviewerName,
                                    reviewerAvatarUrl: review.reviewerAvatarUrl
                                )

                                // Request context
                                if let requestTitle = review.requestTitle {
                                    HStack(spacing: 4) {
                                        Image(systemName: review.rideId != nil ? "car.fill" : "hand.raised.fill")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(requestTitle)
                                            .font(.naarsCaption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await loadReviews()
                }
            }
        }
        .navigationTitle("review_all_reviews_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadReviews()
        }
    }

    private func loadReviews() async {
        defer { isLoading = false }
        do {
            reviews = try await ProfileService.shared.fetchReviews(forUserId: userId)
            error = nil
        } catch {
            self.error = error
            AppLogger.error("reviews", "Failed to load all reviews: \(error)")
        }
    }
}

// MARK: - Skeleton

private struct SkeletonReviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.naarsBackgroundSecondary)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.naarsBackgroundSecondary)
                        .frame(width: 100, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.naarsBackgroundSecondary)
                        .frame(width: 80, height: 12)
                }
                Spacer()
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.naarsBackgroundSecondary)
                .frame(height: 40)
        }
        .padding()
        .background(Color.naarsBackgroundSecondary.opacity(0.5))
        .cornerRadius(12)
        .shimmer()
    }
}
```

**Step 2: Add localization key**

Add to `Localizable.xcstrings`:
- `review_all_reviews_title` → "My Reviews" (en), "Mis reseñas" (es), "내 리뷰" (ko), "Đánh giá của tôi" (vi), "我的评价" (zh-Hans), "我的評價" (zh-Hant)

**Step 3: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add NaarsCars/Features/Reviews/Views/AllReviewsView.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add AllReviewsView for scrollable list of all user reviews"
```

---

### Task 11: Wire AllReviewsView into MyProfileView

**Files:**
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift:408-443`

**Step 1: Wrap the reviews section header in a NavigationLink**

Replace the reviews section header `HStack` (lines 410-422) to make it a NavigationLink. Change from:

```swift
HStack {
    Text("profile_reviews".localized)
        .font(.naarsHeadline)
    Spacer()
    if viewModel.reviews.count > 5 {
        Button(showAllReviews ? "profile_show_less".localized : "profile_show_all".localized) {
            withAnimation {
                showAllReviews.toggle()
            }
        }
        .font(.naarsCaption)
        .foregroundColor(.naarsPrimary)
    }
}
```

To:

```swift
NavigationLink {
    if let userId = appState.currentUser?.id ?? AuthService.shared.currentUserId {
        AllReviewsView(userId: userId)
    }
} label: {
    HStack {
        Text("profile_reviews".localized)
            .font(.naarsHeadline)
        Spacer()
        if !viewModel.reviews.isEmpty {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
.disabled(viewModel.reviews.isEmpty)
```

This replaces the "Show All" / "Show Less" toggle with a NavigationLink to `AllReviewsView`. The reviews section in the profile now shows up to 5 reviews as a preview, and tapping the header navigates to the full list. The `showAllReviews` state variable and toggle logic can be removed as they're no longer needed.

**Step 2: Clean up unused state**

Remove the `@State private var showAllReviews = false` declaration (line 23) since it's no longer used.

Also update the reviews ForEach (around line 433) to always show a preview (max 5):

```swift
ForEach(Array(viewModel.reviews.prefix(5))) { review in
    ReviewRow(review: review)
}
```

**Step 3: Build and verify**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add NaarsCars/Features/Profile/Views/MyProfileView.swift
git commit -m "feat: wire AllReviewsView into profile reviews section via NavigationLink"
```

---

### Task 12: Final Build Verification & Cleanup

**Step 1: Full build**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 2: Run all tests**

Run: `cd /Users/bcolf/Documents/naars-cars-ios && xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -20`
Expected: All tests pass

**Step 3: Fix any issues found and commit**

If build or test failures are discovered, fix them and commit with an appropriate message.
