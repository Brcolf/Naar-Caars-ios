# Light/Dark Mode UI Polish

**Date:** 2026-03-02

## Problem

Two visual issues across the app's light and dark mode:

1. **Dark mode name fade artifact:** The `FadingTitleText` component uses a `LinearGradient` overlay that fades to `Color.naarsBackgroundSecondary`. In dark mode, this creates a visible gray rectangle over conversation names — even when the name doesn't need fading. In light mode the fade blends naturally into the white background.

2. **Light mode lacks visual separation:** Most views use `.listStyle(.plain)` with no explicit background, so white cards sit on a near-white background (`#F8F9FA`), making everything blend together. The Settings view (which uses SwiftUI `Form`) has good contrast as a reference point.

## Solution

### Fix 1: FadingTitleText — mask instead of overlay

Replace the color-dependent gradient overlay with a `.mask()` approach. A mask fades text from opaque to transparent, working identically on any background color in either mode.

**File:** `NaarsCars/Features/Messaging/Views/ConversationRow.swift`

### Fix 2: Light mode background contrast

Change `naarsBackground` light mode from `#F8F9FA` to `#F2F2F7` (iOS system grouped background). This provides clear contrast against white card surfaces. Dark mode values unchanged.

**File:** `NaarsCars/UI/Styles/ColorTheme.swift`

### Fix 3: Apply background to all main views

Add `.scrollContentBackground(.hidden)` (List views) and `.background(Color.naarsBackground)` to all 6 main tab views:

| View | File | Container |
|------|------|-----------|
| ConversationsListView | Messaging/Views/ConversationsListView.swift | List |
| LeaderboardView | Leaderboards/Views/LeaderboardView.swift | List |
| NotificationsListView | Notifications/Views/NotificationsListView.swift | List |
| RequestsDashboardView | Requests/Views/RequestsDashboardView.swift | ScrollView |
| TownHallFeedView | TownHall/Views/TownHallFeedView.swift | ScrollView |
| MyProfileView | Profile/Views/MyProfileView.swift | ScrollView |

## Scope

- 8 files changed
- No new files
- No data model or logic changes
- Visual-only changes
