# XP Leaderboard with Spotlights & Badges

## Overview

Redesign the leaderboard from a simple "sum of completed requests" ranking to an XP-based system with earnable badges and spotlight categories. The goal is to reward helpfulness while making the experience more playful and engaging.

## Scoring Engine

XP is computed server-side in the Supabase RPC function. The client receives pre-computed totals.

| Action | XP | Notes |
|---|---|---|
| Fulfill a ride | 5 base + 1 per $5 saved | Uses existing computed savings field |
| Fulfill a favor | 10 | Flat rate |
| Request a ride | 5 | Encourages posting requests |
| Request a favor | 5 | Encourages posting requests |
| First ride requested (ever) | 10 | One-time milestone bonus |
| First favor requested (ever) | 10 | One-time milestone bonus |
| Receive a 5-star review | 5 | Quality reward |
| Receive a 4-star review | 2 | Quality reward |
| Weekly streak (per active week) | 5 | Consecutive weeks with 1+ fulfilled request |

### Ride savings XP

The savings field is already computed and stored on rides. The XP formula is: `5 + floor(savings / 5)`. This calculation happens entirely in the SQL function.

### Streaks

A streak is consecutive calendar weeks where the user fulfilled at least one request. Computed via weekly bucketing in SQL. Streak XP accrues per week maintained.

### First-request milestones

Checked by looking for the user's earliest ride/favor request. If it falls within the selected date range, the milestone bonus applies for that period.

## Badges

Badges are binary (earned or not). Computed server-side alongside XP. Up to 2 badges displayed per leaderboard row.

| Badge | Criteria | Icon |
|---|---|---|
| Road Warrior | 10+ rides fulfilled | car |
| Good Neighbor | 10+ favors fulfilled | hands |
| Streak King/Queen | 3+ week streak | flame |
| Five Star | 10+ five-star reviews | star |
| Rising Star | Top 3 in XP gained this month | rocket |
| Big Saver | Helped save $250+ total | piggy bank |

## Spotlight Categories

Two spotlight cards displayed below the main XP leaderboard:

### Longest Streak

The user with the most consecutive weeks of fulfilling at least one request in the selected time period. Shows name, avatar, and streak count.

### Rising Star

The user who gained the most XP in the current time period. For "all-time" filter, uses the current month. Shows name, avatar, and XP gained.

Each spotlight is a tappable card that navigates to the user's profile.

## Leaderboard Row Layout

```
┌──────────────────────────────────────────┐
│  #1  medal  [Avatar]  Name        450 XP │
│              [Badge 1] [Badge 2]          │
└──────────────────────────────────────────┘
```

- Rank + medal emoji (top 3) or number (4+)
- Avatar + name
- Total XP right-aligned
- Up to 2 badges as small pill-shaped tags below the name
- Current user's row highlighted

## XP Inline Feedback

After completing an action that earns XP, a small toast appears for ~2 seconds:

```
┌─────────────────────────┐
│  +10 XP  Ride Hero       │
└─────────────────────────┘
```

- Auto-dismisses, non-blocking
- Shows on request completion/review screens

## Data Architecture

- All XP, badge, and spotlight calculations happen in the Supabase RPC function
- No new tables needed — XP is computed on-the-fly from existing rides, favors, and reviews
- LeaderboardEntry model expands to include `xp: Int`, `badges: [Badge]`
- RPC response includes spotlight winner data
- All computation is server-side (off main thread by design)

## What Doesn't Change

- Time period filters (all-time, year, quarter, month)
- Top 100 limit
- "Your Rank" section for users outside top 100
- Pull-to-refresh and 15-minute cache TTL
- Navigation to profiles from rows
- Skeleton loading states
