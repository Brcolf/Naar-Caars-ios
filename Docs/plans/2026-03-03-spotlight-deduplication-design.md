# Spotlight Deduplication Design

**Date:** 2026-03-03

## Problem

The leaderboard spotlights can show the same user in multiple categories. We want a maximum of 3 unique spotlight winners, and if a user qualifies for multiple categories, they should only appear once.

## Design

### New Spotlight Category

Add **top_requester**: the user who posted the most total requests (rides + favors) in the period.

This brings the total to 3 categories: `longest_streak`, `rising_star`, `top_requester`.

### Deduplication Strategy

**Priority order:** `longest_streak` > `rising_star` > `top_requester`

Each category computes **top 3 candidates** (to allow backfilling). Categories are processed in priority order. For each category, the function picks the highest-ranked candidate whose `user_id` has not already been claimed by a higher-priority category.

The function returns at most 3 rows, one per category, with guaranteed unique users.

### Database Changes

Replace `get_leaderboard_spotlights` with a new version that:

1. Computes top 3 candidates per category using CTEs
2. Builds a `claimed_users` set starting empty
3. For each category in priority order, selects the first candidate not in `claimed_users`, then adds them
4. Returns the deduplicated result set

### Client Changes

- **SpotlightEntry.swift** — Add `displayCategory`, `iconName`, and `formattedValue` mappings for `"top_requester"`
- **Localization** — Add `spotlight_top_requester` and `spotlight_requester_value` keys
- No changes needed to LeaderboardViewModel, SpotlightCard, or LeaderboardView
