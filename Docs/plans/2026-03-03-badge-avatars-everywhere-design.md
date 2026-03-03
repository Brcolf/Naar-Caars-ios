# Badge Avatars Everywhere Design

**Date:** 2026-03-03

## Problem

Badges only appear on avatars in 3 places (leaderboard, public profile, my profile). Users should see badge rings on avatars throughout the app.

## Design

### BadgeCache

A singleton `@Observable` class storing `[UUID: [LeaderboardBadge]]` in memory.

- `badges(for userId: UUID) -> [LeaderboardBadge]` — returns cached or empty
- `store(badges:for:)` — single user write
- `storeBatch(entries:)` — bulk populate from leaderboard results
- **1 hour TTL** — stale entries still returned, refreshed on next leaderboard/profile fetch
- Populated as side effect of existing fetches (LeaderboardViewModel, profile views)
- No new API calls — graceful degradation for unseen users (no badges shown)

### AvatarView Changes

Add optional `userId: UUID?` parameter. When provided and `size >= 40`, auto-reads from BadgeCache. Explicit `badges` parameter still works (takes priority over cache lookup).

**Size threshold:** Only avatars 40pt+ show badges. Smaller avatars (message bubbles at 28pt, typing indicators, town hall at 24pt) skip the ring for readability.

**Scope:** All surfaces including admin views.

### New Badge: Frequent Carbardian

- **Key:** `frequent_carbardian`
- **Emoji:** 🚙
- **SF Symbol:** `car.2.fill`
- **Criteria:** 10+ total requests created (rides + favors, all-time)
- **Description:** "Requested 10 or more rides and favors"

Requires changes to:
- `LeaderboardBadge.swift` — add case
- `get_user_badges` DB function — add request count check
- `get_xp_leaderboard` DB function — add to badge assembly
- Localization — add name and description strings

### Call Sites to Update (40pt+ avatars)

Add `userId` parameter to these existing AvatarView calls:
- SpotlightCard (36pt — skip, below threshold)
- RideCard (40pt)
- FavorCard (40pt)
- ReviewCard (40pt)
- UserAvatarLink (50pt)
- ConversationAvatar (50pt single)
- ConversationsListView toast (36pt — skip)
- PendingUsersView (50pt)
- PendingUserDetailView (80pt, 40pt)
- UserManagementView (44pt)
- UserSearchView (50pt, 32pt — skip 32pt)
- MessageDetailsPopup (40pt)
- EditProfileView (120pt)
- SettingsView blocked users (44pt)
- RequestQAView (32pt — skip)
- ConversationDetailView (32pt, 26pt — skip)
