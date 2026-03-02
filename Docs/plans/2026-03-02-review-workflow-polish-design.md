# Review Workflow Polish — Design

**Date:** 2026-03-02
**Status:** Approved

## Overview

Five improvements to the review workflow: fix bell notification re-loading, fix past requests toggle labels, remove 7-day review window, add inline review display on completed request details, and add an all-reviews list view accessible from the profile.

---

## 1. Fix Bell Notification Review Re-loading

**Problem:** When the review prompt modal is dismissed (by backgrounding the app), `NavigationCoordinator.showReviewPrompt` stays `true`. When the user later taps the notification in the bell, `applyDeferredNotificationIntentIfNeeded()` sets `showReviewPrompt = true` again — but since it's already `true`, the `onChange` handler in `MainTabView` doesn't fire.

**Fix:**
- When the active review prompt sheet is dismissed (for any reason — submitted, skipped, or interactive dismiss), call `NavigationCoordinator.resetReviewPrompt()` to set `showReviewPrompt = false`.
- This ensures the next notification tap → deferred intent → `showReviewPrompt = true` actually triggers the `onChange`.

**Files:**
- `MainTabView.swift` — ensure prompt sheet `onDismiss` resets coordinator state
- `PromptCoordinator.swift` — verify prompt dismissal cleans up properly

---

## 2. Fix Past Requests Toggle Labels

**Problem:** `PastRequestFilter` uses raw values `"ride_edit_my_past_requests"` and `"ride_edit_helped_with"` as localization keys. These keys don't exist in `Localizable.xcstrings`, so raw underscore text is displayed.

**Fix:** Add localization entries:
- `ride_edit_my_past_requests` → "My Past Requests"
- `ride_edit_helped_with` → "Rides I Helped With"
- Verify/add: `ride_edit_no_past_requests`, `ride_edit_past_requests_title`, `ride_edit_no_past_requests_mine`, `ride_edit_no_past_requests_helped`

**Files:**
- `Localizable.xcstrings`

---

## 3. Remove 7-Day Review Window

**Problem:** `ReviewService.canStillReview()` enforces a 7-day limit after completion. Reviews should be possible at any time.

**Fix:**
- Simplify `ReviewService.canStillReview()` to always return `true`.
- Update `ReviewPromptProvider` if it also filters by the 7-day window.

**Files:**
- `ReviewService.swift`
- `ReviewPromptProvider.swift` (if applicable)

---

## 4. Inline Review Section on Completed Request Details

**New component: `RequestReviewSection`**

A reusable SwiftUI view for both `RideDetailView` and `FavorDetailView`.

**Behavior:**
- Input: `requestType`, `requestId`, ride/favor data (poster ID, claimer ID, completion status)
- Fetches review for this request via new `ReviewService.fetchReviewForRequest(requestType:requestId:)`
- **Review exists:** Display inline section with reviewer avatar + name, star rating, comment text, photo thumbnail, date
- **No review, user is poster, request is completed:** Show "Leave a Review" button → opens `LeaveReviewView` sheet
- **No review, user is not poster:** Show nothing

**Placement:** Below claimer card section, visible only when request status is completed.

**New service method:** `ReviewService.fetchReviewForRequest(requestType:requestId:)` — queries reviews table by `ride_id` or `favor_id`.

**Files:**
- New: `NaarsCars/Features/Reviews/Views/RequestReviewSection.swift`
- `ReviewService.swift` — add `fetchReviewForRequest()`
- `ReviewServiceProtocol` (if exists) — add method
- `RideDetailView.swift` — add `RequestReviewSection` for completed rides
- `FavorDetailView.swift` — add `RequestReviewSection` for completed favors

---

## 5. All Reviews List View from Profile

**New view: `AllReviewsView`**

Dedicated scrollable list of all reviews left for the current user.

**UI:**
- Navigation title: "My Reviews"
- Each row: reviewer avatar + name, star rating, date, full comment, photo (tappable), request context ("Ride: Airport → Campus" or "Favor: Pick up groceries")
- Empty state if no reviews
- Pull-to-refresh

**Data:** Enhance `ProfileService.fetchReviews()` to join reviewer profile and request title data via Supabase query joins, or fetch reviews then batch-fetch associated data.

**Model extension:** Add optional joined fields to `Review`: `reviewerName`, `reviewerAvatarUrl`, `requestTitle` (similar to existing `fulfillerName`).

**Access point:** Reviews section header in `MyProfileView` becomes a `NavigationLink` to `AllReviewsView`.

**Files:**
- New: `NaarsCars/Features/Reviews/Views/AllReviewsView.swift`
- `Review.swift` — add optional joined fields
- `ProfileService.swift` — enhance `fetchReviews()` with joins
- `MyProfileView.swift` — wrap reviews section in `NavigationLink`

---

## Summary of All Files Touched

| File | Change |
|------|--------|
| `MainTabView.swift` | Reset review prompt state on sheet dismiss |
| `PromptCoordinator.swift` | Verify prompt dismissal cleanup |
| `Localizable.xcstrings` | Add missing past-requests localization keys |
| `ReviewService.swift` | Remove 7-day limit, add `fetchReviewForRequest()` |
| `ReviewPromptProvider.swift` | Remove 7-day filtering if applicable |
| `RequestReviewSection.swift` | **New** — inline review display component |
| `RideDetailView.swift` | Add `RequestReviewSection` for completed rides |
| `FavorDetailView.swift` | Add `RequestReviewSection` for completed favors |
| `AllReviewsView.swift` | **New** — full reviews list view |
| `Review.swift` | Add optional joined fields for reviewer/request context |
| `ProfileService.swift` | Enhance `fetchReviews()` with joins |
| `MyProfileView.swift` | NavigationLink on reviews section header |
