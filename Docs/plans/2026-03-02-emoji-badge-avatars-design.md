# Emoji Badge Avatars Design

## Overview

Replace text-label badge pills on leaderboard rows with emoji badges that overlay the user's avatar in a ring pattern. Badges become part of the user's visual identity across the entire app. Add a badges section to profile pages explaining each badge.

## Badge Emoji Map

| Badge | Emoji | Criteria |
|---|---|---|
| Road Warrior | 🚗 | 10+ rides fulfilled |
| Good Neighbor | 🤝 | 10+ favors fulfilled |
| Streak Champ | 🔥 | 3+ week streak |
| Five Star | ⭐ | 10+ five-star reviews |
| Big Saver | 💰 | Helped save $250+ |

## Avatar Overlay

Modify the existing `AvatarView` component to accept an optional `badges: [LeaderboardBadge]` parameter. When badges are present, up to 3 emoji are positioned in a ring around the lower half of the avatar at fixed clock positions:

- **1 badge:** 6 o'clock (bottom center)
- **2 badges:** 5 o'clock, 7 o'clock
- **3 badges:** 4 o'clock, 6 o'clock, 8 o'clock

Each emoji sits in a small circle background (white/card color) to ensure visibility against the avatar image. Emoji size scales with avatar size (~30% of avatar diameter).

Since `AvatarView` is used throughout the app, badges automatically appear everywhere the avatar is shown, as long as the caller passes badge data.

## Leaderboard Row Changes

Remove the badge pill `HStack` from `LeaderboardRow`. Badges are now shown on the avatar overlay instead.

## Profile Badge Section

Add a "Badges" section to `PublicProfileView` and `MyProfileView` showing all 5 badges in a vertical list:

- Earned badges shown with emoji, name, and criteria description
- Unearned badges grayed out with the same info

## Data Flow

- `LeaderboardEntry` already has `badges: [LeaderboardBadge]` — feeds the avatar overlay on leaderboard rows
- Profile pages need badge data: add a lightweight `get_user_badges(user_id)` RPC that returns the badge array for a single user
- `LeaderboardBadge` enum gets a new `emoji: String` property mapping each case to its emoji character
