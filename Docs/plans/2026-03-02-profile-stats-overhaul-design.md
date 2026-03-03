# Profile Stats Bar Overhaul - Design

## Summary

Refactor the `ProfileStatsCard` from 3 static stats (Rating, Reviews, Fulfilled) to 4 interactive stats (Rating, My Savings, Fulfilled, XP). Each stat taps to open a detail sheet. Replace the center "Reviews" stat with a dollar-amount "My Savings" stat. Add XP as a 4th stat. All taps present as slide-up sheets with consistent styling matching the admin panel's `StatCard` pattern.

## Decisions Made

- **Savings scope:** Rides only (favors have no estimated cost)
- **XP tracking:** New `xp_events` table (not reconstructed from requests)
- **XP consistency:** DB trigger + update leaderboard RPC to read from `xp_events` (single source of truth)
- **Savings UI:** Sheet with period picker + grouped list (no chart)
- **Tab naming:** "Helped With" (replaces "Requests I've Helped With")
- **Stats layout:** Keep horizontal single-row, reduce spacing from 32 → 20
- **Navigation pattern:** All stat taps use `.sheet()` (no navigation pushes)
- **Architecture:** Callback-based closures on `ProfileStatsCard` (Approach A)
- **Styling:** Match admin panel `StatCard` pattern (icon, value, label with `naarsBackgroundSecondary`, separator border, 12pt corner radius)

## Stats Card Changes

### Current (3 stats)
```
[ Rating | Reviews | Fulfilled ]
```

### New (4 stats)
```
[ Rating | My Savings | Fulfilled | XP ]
```

### Styling (matching admin StatCard)

Each stat column:
- Icon: `.naarsTitle2` font, colored per stat
- Value: `.naarsTitle2`, `.bold`
- Label: `.naarsCaption`, `.secondary`
- Card: `naarsBackgroundSecondary` background, 12pt corner radius, 1pt `separator` border
- When tappable: wrapped in `Button` with `.plain` style

Stat colors:
- Rating: `.naarsPrimary` (terracotta) with `star.fill` icon
- My Savings: `.naarsSuccess` (green) with `dollarsign.circle.fill` icon
- Fulfilled: `.naarsSuccess` (green) with `checkmark.circle.fill` icon
- XP: `.naarsWarning` (orange) with `bolt.fill` icon

### API

```swift
ProfileStatsCard(
    rating: Double?,
    totalSavings: Double,
    fulfilledCount: Int,
    xp: Int,
    onRatingTap: (() -> Void)?,
    onSavingsTap: (() -> Void)?,
    onFulfilledTap: (() -> Void)?,
    onXPTap: (() -> Void)?
)
```

PublicProfileView uses a separate initializer with only rating + fulfilledCount, no closures (non-interactive).

## Database Changes

### New `xp_events` table

| Column | Type | Notes |
|--------|------|-------|
| id | UUID | PK, default gen_random_uuid() |
| user_id | UUID | FK → auth.users, NOT NULL |
| amount | integer | +5 for rides, +10 for favors |
| source_type | text | 'ride' or 'favor' |
| source_id | UUID | FK to ride/favor id |
| description | text | e.g. "Ride to Airport" |
| created_at | timestamptz | default now() |

RLS: Users can only SELECT their own rows (`user_id = auth.uid()`).

### Postgres trigger

On `rides` and `favors` UPDATE where `status` changes to `'completed'`, insert an `xp_events` row for the `claimed_by` user. Idempotent via unique constraint on `(source_type, source_id)` using `ON CONFLICT DO NOTHING`.

### Backfill migration

One-time INSERT into `xp_events` from all existing completed rides (5 XP each) and favors (10 XP each) where `claimed_by IS NOT NULL`.

### Updated `get_xp_leaderboard` RPC

Change to SUM `amount` from `xp_events` grouped by `user_id` instead of computing on-the-fly. Must respect the same `start_date`/`end_date` parameters.

### New `get_user_savings` RPC

Parameters: `p_period` (text: 'month', 'year', 'all')
Returns: rows of `(period_label, total_savings, ride_count)`
Scoped to `auth.uid()` — sums `estimated_cost` from rides where `user_id = auth.uid() OR claimed_by = auth.uid()`, grouped by period.

### New `get_user_xp_events` RPC

Parameters: none (uses `auth.uid()`)
Returns: all `xp_events` rows for the calling user, ordered by `created_at` DESC.

## New Detail Views (All Sheets)

### ReviewsSheet
- `NavigationStack` with "Reviews" title and close button
- Reuses existing `ReviewRowView` components
- Receives `[Review]` from parent (already loaded in MyProfileViewModel)

### SavingsSheet
- `NavigationStack` with "My Savings" title and close button
- Segmented picker: Month / Year / All Time (matching admin overlay pattern)
- Total amount displayed prominently at top (48pt font, bold)
- Subtitle: "Total Savings"
- List of rides with their estimated savings, grouped by period
- Uses `get_user_savings` RPC

### PastRequestsView (modified)
- Add `initialFilter: PastRequestFilter` parameter (defaults to `.myRequests`)
- Set `_selectedFilter = State(initialValue: initialFilter)` in init
- Rename "Requests I've Helped With" tab label to "Helped With"
- No other changes to behavior

### XPHistorySheet
- `NavigationStack` with "XP History" title and close button
- Total XP displayed at top (48pt font, bold)
- Subtitle: "Total XP Earned"
- List of XP events showing: amount badge (+5 / +10), description, date
- Grouped by month
- Uses `get_user_xp_events` RPC

## ViewModel & Service Changes

### MyProfileViewModel gains:
- `@Published var totalSavings: Double = 0`
- `@Published var xp: Int = 0`
- Two new concurrent fetches in `loadProfile()`:
  - `profileService.fetchUserSavings(userId:)` → total savings (all time, for the stat display)
  - `profileService.fetchUserXP(userId:)` → total XP (sum from xp_events)

### ProfileService gains:
- `fetchUserSavings(userId:) async throws -> Double` — calls `get_user_savings` with period='all'
- `fetchUserXP(userId:) async throws -> Int` — sums from `xp_events` for user
- `fetchUserSavingsBreakdown(period:) async throws -> [SavingsPeriod]` — for the savings sheet
- `fetchXPEvents(userId:) async throws -> [XPEvent]` — for the XP history sheet

### New model: XPEvent
```swift
struct XPEvent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let amount: Int
    let sourceType: String
    let sourceId: UUID
    let description: String?
    let createdAt: Date
}
```

### MyProfileView gains:
- Enum-driven sheet state:
  ```swift
  enum ProfileSheet: Identifiable {
      case reviews, savings, pastRequests, xpHistory
      var id: Self { self }
  }
  @State private var activeSheet: ProfileSheet?
  ```
- Single `.sheet(item: $activeSheet)` with switch
- Closures passed to `ProfileStatsCard` that set `activeSheet`

## Risk Mitigations

1. **XP divergence:** Leaderboard RPC updated to read from `xp_events` in same migration as backfill
2. **Forward XP recording:** Postgres trigger (not app-level) ensures no missed events
3. **Duplicate XP:** Unique constraint on `(source_type, source_id)` with `ON CONFLICT DO NOTHING`
4. **Security:** All user-facing RPCs use `auth.uid()` internally
5. **Small screens:** Test 4 stats at reduced spacing on iPhone SE
6. **Sheet state:** Single enum-driven `activeSheet` instead of 4 booleans
