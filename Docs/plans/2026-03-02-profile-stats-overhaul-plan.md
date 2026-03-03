# Profile Stats Bar Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the profile stats bar from 3 static stats to 4 interactive stats (Rating, My Savings, Fulfilled, XP) with tap-to-sheet navigation, matching admin panel styling.

**Architecture:** Callback-based `ProfileStatsCard` with optional tap closures. New `xp_events` Postgres table with triggers for single-source-of-truth XP tracking. User-facing Supabase RPCs for savings and XP. Enum-driven sheet state in `MyProfileView`. All detail views presented as slide-up sheets.

**Tech Stack:** SwiftUI, Supabase (Postgres RPCs, RLS, triggers), Swift async/await

**Design doc:** `Docs/plans/2026-03-02-profile-stats-overhaul-design.md`

---

## Task 1: Create `xp_events` Table and Backfill

**Files:**
- Create: Supabase migration (via MCP)

**Step 1: Apply migration to create xp_events table with trigger and backfill**

Apply a single Supabase migration named `create_xp_events_table` with this SQL:

```sql
-- Create xp_events table
CREATE TABLE IF NOT EXISTS public.xp_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,
    source_type TEXT NOT NULL CHECK (source_type IN ('ride', 'favor')),
    source_id UUID NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_type, source_id)
);

-- Index for user lookups
CREATE INDEX idx_xp_events_user_id ON public.xp_events(user_id);
CREATE INDEX idx_xp_events_created_at ON public.xp_events(created_at);

-- RLS: users can only read their own XP events
ALTER TABLE public.xp_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own xp_events"
    ON public.xp_events FOR SELECT
    USING (auth.uid() = user_id);

-- Trigger function: insert XP event when ride/favor completes
CREATE OR REPLACE FUNCTION public.record_xp_on_completion()
RETURNS TRIGGER AS $$
BEGIN
    -- Only fire when status changes to 'completed' and there's a claimer
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.claimed_by IS NOT NULL THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
        VALUES (
            NEW.claimed_by,
            CASE TG_TABLE_NAME
                WHEN 'rides' THEN 5
                WHEN 'favors' THEN 10
            END,
            CASE TG_TABLE_NAME
                WHEN 'rides' THEN 'ride'
                WHEN 'favors' THEN 'favor'
            END,
            NEW.id,
            CASE TG_TABLE_NAME
                WHEN 'rides' THEN COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride')
                WHEN 'favors' THEN COALESCE(NEW.title, 'Favor')
            END,
            COALESCE(NEW.updated_at, now())
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach triggers to rides and favors tables
CREATE TRIGGER trg_rides_xp_on_completion
    AFTER UPDATE ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_completion();

CREATE TRIGGER trg_favors_xp_on_completion
    AFTER UPDATE ON public.favors
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_completion();

-- Backfill: insert XP events for all existing completed rides
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    r.claimed_by,
    5,
    'ride',
    r.id,
    COALESCE(r.pickup || ' → ' || r.destination, 'Ride'),
    COALESCE(r.updated_at, r.created_at)
FROM public.rides r
WHERE r.status = 'completed' AND r.claimed_by IS NOT NULL
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Backfill: insert XP events for all existing completed favors
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    f.claimed_by,
    10,
    'favor',
    f.id,
    COALESCE(f.title, 'Favor'),
    COALESCE(f.updated_at, f.created_at)
FROM public.favors f
WHERE f.status = 'completed' AND f.claimed_by IS NOT NULL
ON CONFLICT (source_type, source_id) DO NOTHING;
```

**Step 2: Verify migration**

Run SQL to verify:
```sql
SELECT count(*) as total_xp_events,
       count(DISTINCT user_id) as unique_users,
       sum(CASE WHEN source_type = 'ride' THEN 1 ELSE 0 END) as ride_events,
       sum(CASE WHEN source_type = 'favor' THEN 1 ELSE 0 END) as favor_events
FROM public.xp_events;
```

Expected: counts > 0 if there are existing completed rides/favors.

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: create xp_events table with triggers and backfill"
```

---

## Task 2: Create User-Facing RPCs (Savings + XP)

**Files:**
- Create: Supabase migration (via MCP)

**Step 1: Apply migration for get_user_savings RPC**

Apply a migration named `create_user_savings_and_xp_rpcs`:

```sql
-- RPC: Get user savings breakdown by period
-- Returns savings from rides where user is poster OR claimer
CREATE OR REPLACE FUNCTION public.get_user_savings(p_period TEXT DEFAULT 'all')
RETURNS TABLE (
    period_label TEXT,
    total_savings DOUBLE PRECISION,
    ride_count BIGINT
) AS $$
BEGIN
    IF p_period = 'month' THEN
        RETURN QUERY
        SELECT
            to_char(date_trunc('month', r.date), 'Mon YYYY') AS period_label,
            COALESCE(SUM(r.estimated_cost), 0) AS total_savings,
            COUNT(*)::BIGINT AS ride_count
        FROM public.rides r
        WHERE (r.user_id = auth.uid() OR r.claimed_by = auth.uid())
          AND r.status IN ('confirmed', 'completed')
          AND r.estimated_cost IS NOT NULL
        GROUP BY date_trunc('month', r.date)
        ORDER BY date_trunc('month', r.date) DESC;
    ELSIF p_period = 'year' THEN
        RETURN QUERY
        SELECT
            to_char(date_trunc('year', r.date), 'YYYY') AS period_label,
            COALESCE(SUM(r.estimated_cost), 0) AS total_savings,
            COUNT(*)::BIGINT AS ride_count
        FROM public.rides r
        WHERE (r.user_id = auth.uid() OR r.claimed_by = auth.uid())
          AND r.status IN ('confirmed', 'completed')
          AND r.estimated_cost IS NOT NULL
        GROUP BY date_trunc('year', r.date)
        ORDER BY date_trunc('year', r.date) DESC;
    ELSE
        -- 'all' - return single row with total
        RETURN QUERY
        SELECT
            'All Time'::TEXT AS period_label,
            COALESCE(SUM(r.estimated_cost), 0) AS total_savings,
            COUNT(*)::BIGINT AS ride_count
        FROM public.rides r
        WHERE (r.user_id = auth.uid() OR r.claimed_by = auth.uid())
          AND r.status IN ('confirmed', 'completed')
          AND r.estimated_cost IS NOT NULL;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC: Get user XP events (for history sheet)
CREATE OR REPLACE FUNCTION public.get_user_xp_events()
RETURNS TABLE (
    id UUID,
    amount INTEGER,
    source_type TEXT,
    source_id UUID,
    description TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        xe.id,
        xe.amount,
        xe.source_type,
        xe.source_id,
        xe.description,
        xe.created_at
    FROM public.xp_events xe
    WHERE xe.user_id = auth.uid()
    ORDER BY xe.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC: Get user total XP (for stat display)
CREATE OR REPLACE FUNCTION public.get_user_total_xp()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(
        (SELECT SUM(amount) FROM public.xp_events WHERE user_id = auth.uid()),
        0
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC: Get user total savings (for stat display)
CREATE OR REPLACE FUNCTION public.get_user_total_savings()
RETURNS DOUBLE PRECISION AS $$
BEGIN
    RETURN COALESCE(
        (SELECT SUM(r.estimated_cost)
         FROM public.rides r
         WHERE (r.user_id = auth.uid() OR r.claimed_by = auth.uid())
           AND r.status IN ('confirmed', 'completed')
           AND r.estimated_cost IS NOT NULL),
        0
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
```

**Step 2: Verify RPCs work**

Run SQL to test (will use the service role, not auth.uid()):
```sql
SELECT * FROM public.get_user_savings('month') LIMIT 5;
```

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: create user-facing savings and XP RPCs"
```

---

## Task 3: Update `get_xp_leaderboard` RPC to Use `xp_events`

**Files:**
- Create: Supabase migration (via MCP)

**Step 1: Apply migration to update leaderboard RPC**

Apply a migration named `update_xp_leaderboard_to_use_xp_events`:

```sql
-- Update get_xp_leaderboard to read from xp_events table
-- instead of computing XP on-the-fly from rides/favors
CREATE OR REPLACE FUNCTION public.get_xp_leaderboard(start_date DATE, end_date DATE)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    avatar_url TEXT,
    xp BIGINT,
    badges TEXT[],
    streak_weeks BIGINT,
    requests_fulfilled BIGINT,
    requests_made BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH user_xp AS (
        SELECT
            xe.user_id,
            SUM(xe.amount) AS total_xp
        FROM public.xp_events xe
        WHERE xe.created_at >= start_date
          AND xe.created_at < (end_date + INTERVAL '1 day')
        GROUP BY xe.user_id
        HAVING SUM(xe.amount) > 0
    ),
    user_stats AS (
        SELECT
            ux.user_id,
            ux.total_xp,
            -- Count fulfilled rides in period
            (SELECT COUNT(*) FROM public.rides r
             WHERE r.claimed_by = ux.user_id
               AND r.status IN ('confirmed', 'completed')
               AND r.date >= start_date AND r.date <= end_date) AS rides_fulfilled,
            -- Count fulfilled favors in period
            (SELECT COUNT(*) FROM public.favors f
             WHERE f.claimed_by = ux.user_id
               AND f.status IN ('confirmed', 'completed')
               AND f.date >= start_date AND f.date <= end_date) AS favors_fulfilled,
            -- Count requests made in period
            (SELECT COUNT(*) FROM public.rides r2
             WHERE r2.user_id = ux.user_id
               AND r2.date >= start_date AND r2.date <= end_date)
            +
            (SELECT COUNT(*) FROM public.favors f2
             WHERE f2.user_id = ux.user_id
               AND f2.date >= start_date AND f2.date <= end_date) AS requests_made
        FROM user_xp ux
    ),
    user_badges AS (
        SELECT
            us.user_id,
            ARRAY_REMOVE(ARRAY[
                CASE WHEN us.rides_fulfilled >= 5 THEN 'road_warrior' END,
                CASE WHEN us.favors_fulfilled >= 5 THEN 'good_neighbor' END,
                CASE WHEN (SELECT AVG(rating)::NUMERIC FROM public.reviews rv WHERE rv.fulfiller_id = us.user_id) >= 4.8 THEN 'five_star' END,
                CASE WHEN (SELECT COALESCE(SUM(r3.estimated_cost), 0) FROM public.rides r3 WHERE (r3.user_id = us.user_id OR r3.claimed_by = us.user_id) AND r3.status IN ('confirmed', 'completed')) >= 500 THEN 'big_saver' END
            ], NULL) AS badges
        FROM user_stats us
    ),
    streak_calc AS (
        SELECT
            us.user_id,
            0::BIGINT AS streak_weeks -- Streak calculation can be enhanced later
        FROM user_stats us
    )
    SELECT
        p.id AS user_id,
        p.name,
        p.avatar_url,
        us.total_xp AS xp,
        COALESCE(ub.badges, ARRAY[]::TEXT[]) AS badges,
        COALESCE(sc.streak_weeks, 0) AS streak_weeks,
        (us.rides_fulfilled + us.favors_fulfilled) AS requests_fulfilled,
        us.requests_made
    FROM user_stats us
    JOIN public.profiles p ON p.id = us.user_id
    LEFT JOIN user_badges ub ON ub.user_id = us.user_id
    LEFT JOIN streak_calc sc ON sc.user_id = us.user_id
    ORDER BY us.total_xp DESC
    LIMIT 100;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
```

**Step 2: Verify leaderboard still works**

```sql
SELECT * FROM public.get_xp_leaderboard('2020-01-01'::date, '2030-01-01'::date) LIMIT 5;
```

Expected: Returns leaderboard entries with XP values matching sum of xp_events.

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: update get_xp_leaderboard to use xp_events table"
```

---

## Task 4: Create `XPEvent` Model

**Files:**
- Create: `NaarsCars/Core/Models/XPEvent.swift`

**Step 1: Create the model file**

```swift
//
//  XPEvent.swift
//  NaarsCars
//
//  Model for XP earning events displayed in XP history
//

import Foundation

/// Represents a single XP earning event
struct XPEvent: Codable, Identifiable {
    let id: UUID
    let amount: Int
    let sourceType: String
    let sourceId: UUID
    let description: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case sourceType = "source_type"
        case sourceId = "source_id"
        case description
        case createdAt = "created_at"
    }
}
```

**Step 2: Create `UserSavingsPeriod` model**

Add to the same file or a new file `NaarsCars/Core/Models/UserSavingsPeriod.swift`:

```swift
//
//  UserSavingsPeriod.swift
//  NaarsCars
//
//  Model for user savings breakdown by period
//

import Foundation

/// Represents savings for a single period (month/year/all-time)
struct UserSavingsPeriod: Codable, Identifiable {
    let periodLabel: String
    let totalSavings: Double
    let rideCount: Int

    var id: String { periodLabel }

    enum CodingKeys: String, CodingKey {
        case periodLabel = "period_label"
        case totalSavings = "total_savings"
        case rideCount = "ride_count"
    }
}
```

**Step 3: Commit**

```bash
git add NaarsCars/Core/Models/XPEvent.swift NaarsCars/Core/Models/UserSavingsPeriod.swift
git commit -m "feat: add XPEvent and UserSavingsPeriod models"
```

---

## Task 5: Add Service Methods to `ProfileService`

**Files:**
- Modify: `NaarsCars/Core/Services/ProfileService.swift` (after line 450, before `deleteAccount`)
- Modify: `NaarsCars/Core/Protocols/ProfileServiceProtocol.swift` (add new methods)

**Step 1: Add methods to ProfileServiceProtocol**

In `NaarsCars/Core/Protocols/ProfileServiceProtocol.swift`, add before the closing `}`:

```swift
    func fetchUserTotalSavings(userId: UUID) async throws -> Double
    func fetchUserTotalXP(userId: UUID) async throws -> Int
    func fetchUserSavingsBreakdown(period: String) async throws -> [UserSavingsPeriod]
    func fetchUserXPEvents() async throws -> [XPEvent]
```

**Step 2: Implement methods in ProfileService**

In `NaarsCars/Core/Services/ProfileService.swift`, add after `fetchFulfilledCount` (after line 450):

```swift
    // MARK: - Savings & XP Operations

    /// Fetch total savings for a user (all time)
    /// - Parameter userId: The user ID (unused, RPC uses auth.uid())
    /// - Returns: Total savings in dollars
    func fetchUserTotalSavings(userId: UUID) async throws -> Double {
        let response = try await supabase
            .rpc("get_user_total_savings")
            .execute()

        let value = try JSONDecoder().decode(Double.self, from: response.data)
        return value
    }

    /// Fetch total XP for a user
    /// - Parameter userId: The user ID (unused, RPC uses auth.uid())
    /// - Returns: Total XP points
    func fetchUserTotalXP(userId: UUID) async throws -> Int {
        let response = try await supabase
            .rpc("get_user_total_xp")
            .execute()

        let value = try JSONDecoder().decode(Int.self, from: response.data)
        return value
    }

    /// Fetch savings breakdown by period
    /// - Parameter period: "month", "year", or "all"
    /// - Returns: Array of savings periods
    func fetchUserSavingsBreakdown(period: String) async throws -> [UserSavingsPeriod] {
        let response = try await supabase
            .rpc("get_user_savings", params: ["p_period": period])
            .execute()

        let decoder = JSONDecoder()
        let periods = try decoder.decode([UserSavingsPeriod].self, from: response.data)
        return periods
    }

    /// Fetch XP event history for the current user
    /// - Returns: Array of XP events, newest first
    func fetchUserXPEvents() async throws -> [XPEvent] {
        let response = try await supabase
            .rpc("get_user_xp_events")
            .execute()

        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        let events = try decoder.decode([XPEvent].self, from: response.data)
        return events
    }
```

**Step 3: Add stubs to any mock ProfileService if one exists**

Search for `MockProfileService` or test doubles and add stub implementations.

**Step 4: Commit**

```bash
git add NaarsCars/Core/Services/ProfileService.swift NaarsCars/Core/Protocols/ProfileServiceProtocol.swift
git commit -m "feat: add savings and XP service methods to ProfileService"
```

---

## Task 6: Update `MyProfileViewModel` with Savings and XP

**Files:**
- Modify: `NaarsCars/Features/Profile/ViewModels/MyProfileViewModel.swift`

**Step 1: Add published properties**

After line 23 (`@Published var fulfilledCount: Int = 0`), add:

```swift
    @Published var totalSavings: Double = 0
    @Published var totalXP: Int = 0
```

**Step 2: Add concurrent fetches to loadProfile**

In `loadProfile(userId:)`, add two more async let tasks. Replace the concurrent fetch block (lines 49-64) with:

```swift
            async let profileTask = profileService.fetchProfile(userId: userId)
            async let reviewsTask = profileService.fetchReviews(forUserId: userId)
            async let inviteCodeTask = inviteService.fetchCurrentInviteCode(userId: userId)
            async let inviteStatsTask = inviteService.getInviteStats(userId: userId)
            async let ratingTask = profileService.calculateAverageRating(userId: userId)
            async let countTask = profileService.fetchFulfilledCount(userId: userId)
            async let savingsTask = profileService.fetchUserTotalSavings(userId: userId)
            async let xpTask = profileService.fetchUserTotalXP(userId: userId)

            let (fetchedProfile, fetchedReviews, fetchedCode, fetchedStats, fetchedRating, fetchedCount, fetchedSavings, fetchedXP) = try await (
                profileTask,
                reviewsTask,
                inviteCodeTask,
                inviteStatsTask,
                ratingTask,
                countTask,
                savingsTask,
                xpTask
            )
```

**Step 3: Assign the new properties**

After line 72 (`fulfilledCount = fetchedCount`), add:

```swift
            totalSavings = fetchedSavings
            totalXP = fetchedXP
```

**Step 4: Commit**

```bash
git add NaarsCars/Features/Profile/ViewModels/MyProfileViewModel.swift
git commit -m "feat: add savings and XP to MyProfileViewModel"
```

---

## Task 7: Refactor `ProfileStatsCard` to Admin-Matching Interactive Style

**Files:**
- Modify: `NaarsCars/UI/Components/Common/ProfileStatsCard.swift`

**Step 1: Rewrite ProfileStatsCard**

Replace the entire body of `ProfileStatsCard.swift` with the new implementation. Key changes:
- Add `totalSavings: Double`, `xp: Int` properties
- Add 4 optional closure properties for taps
- Replace "Reviews" stat with "My Savings"
- Add "XP" stat
- Match admin `StatCard` styling: icon + value + label, `naarsBackgroundSecondary` background, `separator` border
- Reduce HStack spacing from 32 to 20
- Each stat is a Button when closure is non-nil, plain VStack otherwise

```swift
//
//  ProfileStatsCard.swift
//  NaarsCars
//
//  Reusable stats card showing rating, savings, fulfilled count, and XP
//

import SwiftUI

/// A reusable card that displays profile statistics
/// Used by both MyProfileView (interactive) and PublicProfileView (static)
struct ProfileStatsCard: View {
    let rating: Double?
    let totalSavings: Double?
    let fulfilledCount: Int
    let xp: Int?

    // Optional tap actions (nil = non-interactive)
    var onRatingTap: (() -> Void)?
    var onSavingsTap: (() -> Void)?
    var onFulfilledTap: (() -> Void)?
    var onXPTap: (() -> Void)?

    /// Full initializer with all 4 stats and tap actions (used by MyProfileView)
    init(
        rating: Double?,
        totalSavings: Double,
        fulfilledCount: Int,
        xp: Int,
        onRatingTap: (() -> Void)? = nil,
        onSavingsTap: (() -> Void)? = nil,
        onFulfilledTap: (() -> Void)? = nil,
        onXPTap: (() -> Void)? = nil
    ) {
        self.rating = rating
        self.totalSavings = totalSavings
        self.fulfilledCount = fulfilledCount
        self.xp = xp
        self.onRatingTap = onRatingTap
        self.onSavingsTap = onSavingsTap
        self.onFulfilledTap = onFulfilledTap
        self.onXPTap = onXPTap
    }

    /// Minimal initializer without savings/XP (used by PublicProfileView)
    init(rating: Double?, fulfilledCount: Int) {
        self.rating = rating
        self.totalSavings = nil
        self.fulfilledCount = fulfilledCount
        self.xp = nil
    }

    var body: some View {
        HStack(spacing: 20) {
            // Rating
            statColumn(
                icon: "star.fill",
                iconColor: .naarsPrimary,
                value: rating.map { String(format: "%.1f", $0) } ?? "—",
                label: rating != nil ? "Rating" : "No Rating",
                action: onRatingTap
            )

            if totalSavings != nil || xp != nil {
                Divider()
            }

            // My Savings (only shown in full mode)
            if let savings = totalSavings {
                statColumn(
                    icon: "dollarsign.circle.fill",
                    iconColor: .naarsSuccess,
                    value: formatSavings(savings),
                    label: "My Savings",
                    action: onSavingsTap
                )

                Divider()
            }

            // Fulfilled
            statColumn(
                icon: "checkmark.circle.fill",
                iconColor: .naarsSuccess,
                value: "\(fulfilledCount)",
                label: "Fulfilled",
                action: onFulfilledTap
            )

            // XP (only shown in full mode)
            if let xpValue = xp {
                Divider()

                statColumn(
                    icon: "bolt.fill",
                    iconColor: .naarsWarning,
                    value: "\(xpValue)",
                    label: "XP",
                    action: onXPTap
                )
            }
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statColumn(icon: String, iconColor: Color, value: String, label: String, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                statContent(icon: icon, iconColor: iconColor, value: value, label: label)
            }
            .buttonStyle(.plain)
        } else {
            statContent(icon: icon, iconColor: iconColor, value: value, label: label)
        }
    }

    private func statContent(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.naarsCaption)
                .foregroundColor(iconColor)
            Text(value)
                .font(.naarsHeadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private func formatSavings(_ amount: Double) -> String {
        if amount >= 1000 {
            return "$\(Int(amount / 1000))k"
        }
        return "$\(Int(amount))"
    }
}

#Preview {
    VStack(spacing: 20) {
        ProfileStatsCard(
            rating: 4.5,
            totalSavings: 1240,
            fulfilledCount: 8,
            xp: 350
        )
        ProfileStatsCard(rating: nil, fulfilledCount: 3)
    }
    .padding()
}
```

Note: The font sizes are intentionally smaller than the admin panel's `StatCard` (which uses `.naarsTitle2` for icon and value) because we're fitting 4 stats in a horizontal row instead of 3 separate cards. Use `.naarsCaption` for icons and `.naarsHeadline` for values to keep things readable at this density. If it feels too cramped during testing, we can adjust.

**Step 2: Verify build compiles**

Run: `xcodebuild build` (or check in Xcode)
Expected: Build errors in MyProfileView and PublicProfileView (callers need updating — handled in next tasks)

**Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Common/ProfileStatsCard.swift
git commit -m "feat: refactor ProfileStatsCard with 4 interactive stats matching admin styling"
```

---

## Task 8: Create Detail Sheet Views

**Files:**
- Create: `NaarsCars/Features/Profile/Views/ReviewsSheet.swift`
- Create: `NaarsCars/Features/Profile/Views/SavingsSheet.swift`
- Create: `NaarsCars/Features/Profile/Views/XPHistorySheet.swift`

**Step 1: Create ReviewsSheet**

```swift
//
//  ReviewsSheet.swift
//  NaarsCars
//
//  Sheet displaying list of reviews for the current user
//

import SwiftUI

struct ReviewsSheet: View {
    let reviews: [Review]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if reviews.isEmpty {
                    EmptyStateView(
                        icon: "star.fill",
                        title: "No Reviews Yet",
                        message: "Reviews from people you've helped will appear here.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(reviews) { review in
                                ReviewRowView(review: review)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

**Step 2: Create SavingsSheet**

Model this after `AdminSavingsOverlay.swift` (lines 10-125) for consistent styling:

```swift
//
//  SavingsSheet.swift
//  NaarsCars
//
//  Sheet showing user's savings breakdown by period
//

import SwiftUI

struct SavingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod = "month"
    @State private var periods: [UserSavingsPeriod] = []
    @State private var isLoading = false
    @State private var error: String?

    private let profileService: any ProfileServiceProtocol = ProfileService.shared

    private var total: Double {
        periods.reduce(0) { $0 + $1.totalSavings }
    }

    private var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: total)) ?? "$0"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Period", selection: $selectedPeriod) {
                    Text("Month").tag("month")
                    Text("Year").tag("year")
                    Text("All Time").tag("all")
                }
                .pickerStyle(.segmented)
                .padding()

                VStack(spacing: 4) {
                    Text(formattedTotal)
                        .font(.system(size: 48, weight: .bold))
                    Text("Total Savings")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error)
                        .foregroundColor(.secondary)
                    Spacer()
                } else if periods.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "dollarsign.circle.fill",
                        title: "No Savings Yet",
                        message: "Savings from shared rides will appear here.",
                        actionTitle: nil,
                        action: nil
                    )
                    Spacer()
                } else {
                    List(periods) { period in
                        HStack {
                            Text(period.periodLabel)
                                .font(.naarsBody)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatCurrency(period.totalSavings))
                                    .font(.naarsHeadline)
                                Text("\(period.rideCount) rides")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadData() }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            periods = try await profileService.fetchUserSavingsBreakdown(period: selectedPeriod)
        } catch {
            self.error = "Failed to load savings"
            AppLogger.error("profile", "Savings sheet error: \(error.localizedDescription)")
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}
```

**Step 3: Create XPHistorySheet**

```swift
//
//  XPHistorySheet.swift
//  NaarsCars
//
//  Sheet showing user's XP earning history
//

import SwiftUI

struct XPHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var events: [XPEvent] = []
    @State private var isLoading = false
    @State private var error: String?

    let totalXP: Int

    private let profileService: any ProfileServiceProtocol = ProfileService.shared

    /// Group events by month for sectioned display
    private var groupedEvents: [(String, [XPEvent])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"

        let grouped = Dictionary(grouping: events) { event in
            formatter.string(from: event.createdAt)
        }

        return grouped.sorted { lhs, rhs in
            guard let lhsDate = lhs.value.first?.createdAt,
                  let rhsDate = rhs.value.first?.createdAt else { return false }
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(totalXP)")
                        .font(.system(size: 48, weight: .bold))
                    Text("Total XP Earned")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                }
                .padding()

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error)
                        .foregroundColor(.secondary)
                    Spacer()
                } else if events.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "bolt.fill",
                        title: "No XP Yet",
                        message: "Help neighbors with rides and favors to earn XP.",
                        actionTitle: nil,
                        action: nil
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(groupedEvents, id: \.0) { month, monthEvents in
                            Section(header: Text(month)) {
                                ForEach(monthEvents) { event in
                                    HStack {
                                        Text("+\(event.amount)")
                                            .font(.naarsHeadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.naarsWarning)
                                            .frame(width: 50, alignment: .leading)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.description ?? (event.sourceType == "ride" ? "Ride" : "Favor"))
                                                .font(.naarsBody)
                                                .lineLimit(1)
                                            Text(event.createdAt.timeAgo)
                                                .font(.naarsCaption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: event.sourceType == "ride" ? "car.fill" : "hand.raised.fill")
                                            .foregroundColor(.secondary)
                                            .font(.naarsCaption)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("XP History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            events = try await profileService.fetchUserXPEvents()
        } catch {
            self.error = "Failed to load XP history"
            AppLogger.error("profile", "XP history sheet error: \(error.localizedDescription)")
        }
    }
}
```

**Step 4: Commit**

```bash
git add NaarsCars/Features/Profile/Views/ReviewsSheet.swift NaarsCars/Features/Profile/Views/SavingsSheet.swift NaarsCars/Features/Profile/Views/XPHistorySheet.swift
git commit -m "feat: add ReviewsSheet, SavingsSheet, and XPHistorySheet detail views"
```

---

## Task 9: Update `PastRequestsView` with Configurable Initial Tab

**Files:**
- Modify: `NaarsCars/Features/Requests/Views/PastRequestsView.swift`

**Step 1: Add initialFilter parameter**

Replace line 13:
```swift
@State private var selectedFilter: PastRequestFilter = .myRequests
```

With an init that accepts an initial filter:

```swift
@State private var selectedFilter: PastRequestFilter

init(initialFilter: PastRequestFilter = .myRequests) {
    _selectedFilter = State(initialValue: initialFilter)
}
```

**Step 2: Update the "Helped With" tab label**

The tab label comes from the localized string `"ride_edit_helped_with"`. Check the current English value in `Localizable.xcstrings`. If it says "Rides I Helped With", update it to "Helped With". Also update all other language translations for this key to their equivalent short form.

**Step 3: Commit**

```bash
git add NaarsCars/Features/Requests/Views/PastRequestsView.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add initialFilter param to PastRequestsView and rename Helped With tab"
```

---

## Task 10: Update `MyProfileView` with Sheet Navigation

**Files:**
- Modify: `NaarsCars/Features/Profile/Views/MyProfileView.swift`

**Step 1: Add ProfileSheet enum and state**

Near the top of `MyProfileView` (after existing `@State` properties), add:

```swift
    enum ProfileSheet: Identifiable {
        case reviews
        case savings
        case pastRequests
        case xpHistory

        var id: Int {
            switch self {
            case .reviews: return 0
            case .savings: return 1
            case .pastRequests: return 2
            case .xpHistory: return 3
            }
        }
    }

    @State private var activeProfileSheet: ProfileSheet?
```

**Step 2: Update statsSection call**

Replace the existing `statsSection` call (lines 44-49) with:

```swift
statsSection(
    rating: viewModel.averageRating,
    totalSavings: viewModel.totalSavings,
    fulfilledCount: viewModel.fulfilledCount,
    xp: viewModel.totalXP
)
```

**Step 3: Update statsSection method**

Replace the `statsSection` method (lines 362-364) with:

```swift
    private func statsSection(rating: Double?, totalSavings: Double, fulfilledCount: Int, xp: Int) -> some View {
        ProfileStatsCard(
            rating: rating,
            totalSavings: totalSavings,
            fulfilledCount: fulfilledCount,
            xp: xp,
            onRatingTap: { activeProfileSheet = .reviews },
            onSavingsTap: { activeProfileSheet = .savings },
            onFulfilledTap: { activeProfileSheet = .pastRequests },
            onXPTap: { activeProfileSheet = .xpHistory }
        )
    }
```

**Step 4: Add the sheet modifier**

Add a `.sheet(item:)` modifier to the main view body (near existing sheet modifiers):

```swift
    .sheet(item: $activeProfileSheet) { sheet in
        switch sheet {
        case .reviews:
            ReviewsSheet(reviews: viewModel.reviews)
        case .savings:
            SavingsSheet()
        case .pastRequests:
            PastRequestsView(initialFilter: .helpedWith)
        case .xpHistory:
            XPHistorySheet(totalXP: viewModel.totalXP)
        }
    }
```

**Step 5: Commit**

```bash
git add NaarsCars/Features/Profile/Views/MyProfileView.swift
git commit -m "feat: wire up interactive stats with sheet navigation in MyProfileView"
```

---

## Task 11: Update `PublicProfileView`

**Files:**
- Modify: `NaarsCars/Features/Profile/Views/PublicProfileView.swift`

**Step 1: Verify PublicProfileView still compiles**

The minimal initializer `ProfileStatsCard(rating:fulfilledCount:)` should still work since we kept it. Verify the `statsSection` method at lines 98-100 still compiles without changes.

If build errors occur, ensure the `PublicProfileView` is calling:
```swift
ProfileStatsCard(rating: rating, fulfilledCount: fulfilledCount)
```

This initializer sets `totalSavings = nil`, `xp = nil`, and all closures to `nil`, so only Rating and Fulfilled show, non-interactively.

**Step 2: Commit (only if changes needed)**

```bash
git add NaarsCars/Features/Profile/Views/PublicProfileView.swift
git commit -m "fix: update PublicProfileView for ProfileStatsCard API change"
```

---

## Task 12: Update Localized Strings

**Files:**
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Step 1: Update "ride_edit_helped_with" translations**

Change the English value from "Rides I Helped With" to "Helped With". Update other languages similarly:
- ES: "Ayudé con"
- KO: "도운 요청"
- VI: "Đã giúp"
- ZH-Hans: "帮助过的"
- ZH-Hant: "幫助過的"

**Step 2: Commit**

```bash
git add NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: update Helped With tab label translations"
```

---

## Task 13: Build Verification and Smoke Test

**Step 1: Build the project**

```bash
xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: Build succeeds with no errors.

**Step 2: Run existing tests**

```bash
xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: All existing tests pass.

**Step 3: Manual verification checklist**

- [ ] Profile stats card shows 4 stats: Rating, My Savings, Fulfilled, XP
- [ ] Tapping Rating opens ReviewsSheet
- [ ] Tapping My Savings opens SavingsSheet with period picker
- [ ] Tapping Fulfilled opens PastRequestsView pre-set to "Helped With" tab
- [ ] Tapping XP opens XPHistorySheet
- [ ] PublicProfileView still shows only Rating + Fulfilled (non-interactive)
- [ ] Leaderboard XP values match profile XP values
- [ ] Stats card styling matches admin panel StatCard pattern

**Step 4: Run Supabase security advisors**

Check for missing RLS policies or security issues after the migrations.

**Step 5: Commit any fixes**

```bash
git commit -m "fix: address build verification issues"
```

---

## Summary of All Files Changed

| Action | File |
|--------|------|
| Create | Supabase migration: `xp_events` table + triggers + backfill |
| Create | Supabase migration: user savings + XP RPCs |
| Create | Supabase migration: update `get_xp_leaderboard` RPC |
| Create | `NaarsCars/Core/Models/XPEvent.swift` |
| Create | `NaarsCars/Core/Models/UserSavingsPeriod.swift` |
| Create | `NaarsCars/Features/Profile/Views/ReviewsSheet.swift` |
| Create | `NaarsCars/Features/Profile/Views/SavingsSheet.swift` |
| Create | `NaarsCars/Features/Profile/Views/XPHistorySheet.swift` |
| Modify | `NaarsCars/UI/Components/Common/ProfileStatsCard.swift` |
| Modify | `NaarsCars/Core/Services/ProfileService.swift` |
| Modify | `NaarsCars/Core/Protocols/ProfileServiceProtocol.swift` |
| Modify | `NaarsCars/Features/Profile/ViewModels/MyProfileViewModel.swift` |
| Modify | `NaarsCars/Features/Profile/Views/MyProfileView.swift` |
| Modify | `NaarsCars/Features/Profile/Views/PublicProfileView.swift` (if needed) |
| Modify | `NaarsCars/Features/Requests/Views/PastRequestsView.swift` |
| Modify | `NaarsCars/Resources/Localizable.xcstrings` |
