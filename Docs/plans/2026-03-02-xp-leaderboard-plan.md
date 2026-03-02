# XP Leaderboard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the "sum of completed requests" leaderboard with an XP-based system featuring badges and spotlight categories.

**Architecture:** Server-side XP/badge/streak computation in Supabase RPC functions. The Swift client receives pre-computed data and renders it. No new tables — all derived from existing `rides`, `favors`, and `reviews` tables. XP toast feedback uses the existing `ToastView` pattern.

**Tech Stack:** PostgreSQL (Supabase RPC), Swift/SwiftUI, existing `ToastView` component.

---

### Task 1: Create `get_xp_leaderboard` Supabase RPC function

**Files:**
- Create: `database/120_create_xp_leaderboard_function.sql`

**Context:**
- Current function is at `database/040_create_leaderboard_function.sql` — do NOT modify it; create a new function alongside it
- `rides` table: `claimed_by UUID`, `status TEXT`, `estimated_cost NUMERIC(10,2)`, `user_id UUID`, `created_at TIMESTAMPTZ`, `updated_at TIMESTAMPTZ`
- `favors` table: same structure (claimed_by, status, user_id, created_at, updated_at) — no estimated_cost
- `reviews` table: `fulfiller_id UUID`, `rating INTEGER (1-5)`, `ride_id UUID?`, `favor_id UUID?`, `created_at TIMESTAMPTZ`
- `profiles` table: `id UUID`, `name TEXT`, `avatar_url TEXT`, `approved BOOLEAN`

**Step 1: Write the SQL migration**

```sql
-- 120_create_xp_leaderboard_function.sql
-- XP-based leaderboard with badges and streak calculation

CREATE OR REPLACE FUNCTION get_xp_leaderboard(
    start_date DATE DEFAULT '1970-01-01',
    end_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
    user_id UUID,
    name TEXT,
    avatar_url TEXT,
    xp BIGINT,
    badges JSONB,
    streak_weeks BIGINT,
    requests_fulfilled BIGINT,
    requests_made BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH user_rides_fulfilled AS (
        SELECT
            r.claimed_by AS uid,
            COUNT(*) AS ride_count,
            -- 5 base + 1 per $5 saved
            SUM(5 + FLOOR(COALESCE(r.estimated_cost, 0) / 5))::BIGINT AS ride_xp,
            SUM(COALESCE(r.estimated_cost, 0))::NUMERIC AS total_savings
        FROM rides r
        WHERE r.status = 'completed'
          AND r.claimed_by IS NOT NULL
          AND DATE(r.updated_at) BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    user_favors_fulfilled AS (
        SELECT
            f.claimed_by AS uid,
            COUNT(*) AS favor_count,
            (COUNT(*) * 10)::BIGINT AS favor_xp
        FROM favors f
        WHERE f.status = 'completed'
          AND f.claimed_by IS NOT NULL
          AND DATE(f.updated_at) BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    user_rides_requested AS (
        SELECT
            r.user_id AS uid,
            COUNT(*) AS ride_req_count,
            (COUNT(*) * 5)::BIGINT AS ride_req_xp
        FROM rides r
        WHERE DATE(r.created_at) BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    user_favors_requested AS (
        SELECT
            f.user_id AS uid,
            COUNT(*) AS favor_req_count,
            (COUNT(*) * 5)::BIGINT AS favor_req_xp
        FROM favors f
        WHERE DATE(f.created_at) BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    -- First-request milestones: 10 XP if user's very first ride/favor request falls in range
    first_ride_milestone AS (
        SELECT r.user_id AS uid, 10::BIGINT AS milestone_xp
        FROM rides r
        WHERE r.user_id IN (
            SELECT r2.user_id FROM rides r2
            GROUP BY r2.user_id
            HAVING MIN(DATE(r2.created_at)) BETWEEN start_date AND end_date
        )
        GROUP BY r.user_id
    ),
    first_favor_milestone AS (
        SELECT f.user_id AS uid, 10::BIGINT AS milestone_xp
        FROM favors f
        WHERE f.user_id IN (
            SELECT f2.user_id FROM favors f2
            GROUP BY f2.user_id
            HAVING MIN(DATE(f2.created_at)) BETWEEN start_date AND end_date
        )
        GROUP BY f.user_id
    ),
    user_review_xp AS (
        SELECT
            rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5 WHEN rv.rating = 4 THEN 2 ELSE 0 END)::BIGINT AS review_xp,
            COUNT(*) FILTER (WHERE rv.rating = 5) AS five_star_count
        FROM reviews rv
        WHERE DATE(rv.created_at) BETWEEN start_date AND end_date
        GROUP BY rv.fulfiller_id
    ),
    -- Streak: consecutive weeks with at least one fulfilled request
    weekly_activity AS (
        SELECT claimed_by AS uid, DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM rides
        WHERE status = 'completed' AND claimed_by IS NOT NULL
          AND DATE(updated_at) BETWEEN start_date AND end_date
        UNION
        SELECT claimed_by AS uid, DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM favors
        WHERE status = 'completed' AND claimed_by IS NOT NULL
          AND DATE(updated_at) BETWEEN start_date AND end_date
    ),
    distinct_weeks AS (
        SELECT DISTINCT uid, week_start,
            ROW_NUMBER() OVER (PARTITION BY uid ORDER BY week_start) AS rn
        FROM weekly_activity
    ),
    -- Gaps-and-islands: subtract row_number weeks from week_start to find islands
    streak_islands AS (
        SELECT uid, week_start,
            week_start - (rn * INTERVAL '7 days')::INTERVAL AS island_id
        FROM distinct_weeks
    ),
    max_streaks AS (
        SELECT uid, MAX(island_count)::BIGINT AS streak_weeks
        FROM (
            SELECT uid, island_id, COUNT(*) AS island_count
            FROM streak_islands
            GROUP BY uid, island_id
        ) sub
        GROUP BY uid
    ),
    streak_xp AS (
        SELECT uid, (streak_weeks * 5)::BIGINT AS s_xp, streak_weeks
        FROM max_streaks
    ),
    -- Combine all XP sources
    combined AS (
        SELECT
            p.id AS uid,
            p.name,
            p.avatar_url,
            COALESCE(urf.ride_xp, 0)
                + COALESCE(uff.favor_xp, 0)
                + COALESCE(urr.ride_req_xp, 0)
                + COALESCE(ufr.favor_req_xp, 0)
                + COALESCE(frm.milestone_xp, 0)
                + COALESCE(ffm.milestone_xp, 0)
                + COALESCE(urv.review_xp, 0)
                + COALESCE(sx.s_xp, 0) AS total_xp,
            COALESCE(sx.streak_weeks, 0) AS streak_weeks,
            COALESCE(urf.ride_count, 0) + COALESCE(uff.favor_count, 0) AS total_fulfilled,
            COALESCE(urr.ride_req_count, 0) + COALESCE(ufr.favor_req_count, 0) AS total_made,
            -- Badge inputs (all-time for badge thresholds)
            COALESCE(urf.ride_count, 0) AS rides_fulfilled_count,
            COALESCE(uff.favor_count, 0) AS favors_fulfilled_count,
            COALESCE(sx.streak_weeks, 0) AS user_streak_weeks,
            COALESCE(urv.five_star_count, 0) AS user_five_star_count,
            COALESCE(urf.total_savings, 0) AS user_total_savings
        FROM profiles p
        LEFT JOIN user_rides_fulfilled urf ON urf.uid = p.id
        LEFT JOIN user_favors_fulfilled uff ON uff.uid = p.id
        LEFT JOIN user_rides_requested urr ON urr.uid = p.id
        LEFT JOIN user_favors_requested ufr ON ufr.uid = p.id
        LEFT JOIN first_ride_milestone frm ON frm.uid = p.id
        LEFT JOIN first_favor_milestone ffm ON ffm.uid = p.id
        LEFT JOIN user_review_xp urv ON urv.uid = p.id
        LEFT JOIN streak_xp sx ON sx.uid = p.id
        WHERE p.approved = true
    )
    SELECT
        c.uid,
        c.name,
        c.avatar_url,
        c.total_xp AS xp,
        -- Build badges JSONB array
        (
            SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb)
            FROM (
                SELECT 'road_warrior' AS badge WHERE c.rides_fulfilled_count >= 10
                UNION ALL
                SELECT 'good_neighbor' WHERE c.favors_fulfilled_count >= 10
                UNION ALL
                SELECT 'streak_champion' WHERE c.user_streak_weeks >= 3
                UNION ALL
                SELECT 'five_star' WHERE c.user_five_star_count >= 10
                UNION ALL
                SELECT 'big_saver' WHERE c.user_total_savings >= 250
            ) badges
        ) AS badges,
        c.streak_weeks,
        c.total_fulfilled AS requests_fulfilled,
        c.total_made AS requests_made
    FROM combined c
    WHERE c.total_xp > 0
    ORDER BY c.total_xp DESC
    LIMIT 100;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_xp_leaderboard(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_xp_leaderboard(DATE, DATE) TO anon;

-- Indexes for review lookups (rides/favors indexes already exist from 040)
CREATE INDEX IF NOT EXISTS idx_reviews_fulfiller_id_rating
ON reviews(fulfiller_id, rating, created_at);
```

**Step 2: Apply the migration via Supabase MCP**

Use `mcp__supabase__apply_migration` with name `create_xp_leaderboard_function` and the SQL above.

**Step 3: Verify the function works**

Run: `mcp__supabase__execute_sql` with `SELECT * FROM get_xp_leaderboard();`
Expected: Returns rows with user_id, name, avatar_url, xp, badges (jsonb), streak_weeks, requests_fulfilled, requests_made.

**Step 4: Commit**

```bash
git add database/120_create_xp_leaderboard_function.sql
git commit -m "feat(db): add get_xp_leaderboard RPC function with XP scoring, badges, and streaks"
```

---

### Task 2: Create `get_leaderboard_spotlights` Supabase RPC function

**Files:**
- Create: `database/121_create_leaderboard_spotlights_function.sql`

**Context:** Spotlights are computed separately because the spotlight winners may not be in the top 100 by XP. Two categories: longest streak and rising star (most XP gained in current period).

**Step 1: Write the SQL migration**

```sql
-- 121_create_leaderboard_spotlights_function.sql
-- Spotlight winners for the leaderboard: longest streak and rising star

CREATE OR REPLACE FUNCTION get_leaderboard_spotlights(
    start_date DATE DEFAULT '1970-01-01',
    end_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
    category TEXT,
    user_id UUID,
    name TEXT,
    avatar_url TEXT,
    value BIGINT
) AS $$
BEGIN
    -- Longest streak
    RETURN QUERY
    WITH weekly_activity AS (
        SELECT claimed_by AS uid, DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM rides
        WHERE status = 'completed' AND claimed_by IS NOT NULL
          AND DATE(updated_at) BETWEEN start_date AND end_date
        UNION
        SELECT claimed_by AS uid, DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM favors
        WHERE status = 'completed' AND claimed_by IS NOT NULL
          AND DATE(updated_at) BETWEEN start_date AND end_date
    ),
    distinct_weeks AS (
        SELECT DISTINCT uid, week_start,
            ROW_NUMBER() OVER (PARTITION BY uid ORDER BY week_start) AS rn
        FROM weekly_activity
    ),
    streak_islands AS (
        SELECT uid, week_start,
            week_start - (rn * INTERVAL '7 days')::INTERVAL AS island_id
        FROM distinct_weeks
    ),
    max_streaks AS (
        SELECT uid, MAX(island_count)::BIGINT AS streak
        FROM (
            SELECT uid, island_id, COUNT(*) AS island_count
            FROM streak_islands
            GROUP BY uid, island_id
        ) sub
        GROUP BY uid
        ORDER BY streak DESC
        LIMIT 1
    )
    SELECT
        'longest_streak'::TEXT AS category,
        p.id,
        p.name,
        p.avatar_url,
        ms.streak AS value
    FROM max_streaks ms
    JOIN profiles p ON p.id = ms.uid
    WHERE p.approved = true;

    -- Rising star (most XP gained in period)
    RETURN QUERY
    WITH xp_in_period AS (
        SELECT
            p.id AS uid,
            p.name,
            p.avatar_url,
            (
                COALESCE((
                    SELECT SUM(5 + FLOOR(COALESCE(r.estimated_cost, 0) / 5))
                    FROM rides r
                    WHERE r.claimed_by = p.id AND r.status = 'completed'
                      AND DATE(r.updated_at) BETWEEN start_date AND end_date
                ), 0)
                + COALESCE((
                    SELECT COUNT(*) * 10
                    FROM favors f
                    WHERE f.claimed_by = p.id AND f.status = 'completed'
                      AND DATE(f.updated_at) BETWEEN start_date AND end_date
                ), 0)
                + COALESCE((
                    SELECT COUNT(*) * 5
                    FROM rides r WHERE r.user_id = p.id
                      AND DATE(r.created_at) BETWEEN start_date AND end_date
                ), 0)
                + COALESCE((
                    SELECT COUNT(*) * 5
                    FROM favors f WHERE f.user_id = p.id
                      AND DATE(f.created_at) BETWEEN start_date AND end_date
                ), 0)
                + COALESCE((
                    SELECT SUM(CASE WHEN rv.rating = 5 THEN 5 WHEN rv.rating = 4 THEN 2 ELSE 0 END)
                    FROM reviews rv WHERE rv.fulfiller_id = p.id
                      AND DATE(rv.created_at) BETWEEN start_date AND end_date
                ), 0)
            )::BIGINT AS period_xp
        FROM profiles p
        WHERE p.approved = true
    )
    SELECT
        'rising_star'::TEXT,
        x.uid,
        x.name,
        x.avatar_url,
        x.period_xp
    FROM xp_in_period x
    WHERE x.period_xp > 0
    ORDER BY x.period_xp DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_leaderboard_spotlights(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_leaderboard_spotlights(DATE, DATE) TO anon;
```

**Step 2: Apply the migration via Supabase MCP**

**Step 3: Verify**

Run: `mcp__supabase__execute_sql` with `SELECT * FROM get_leaderboard_spotlights();`
Expected: Up to 2 rows — one with category='longest_streak', one with category='rising_star'.

**Step 4: Commit**

```bash
git add database/121_create_leaderboard_spotlights_function.sql
git commit -m "feat(db): add get_leaderboard_spotlights RPC function"
```

---

### Task 3: Add `LeaderboardBadge` enum

**Files:**
- Create: `NaarsCars/Core/Models/LeaderboardBadge.swift`
- Test: `NaarsCars/NaarsCarsTests/Core/Models/LeaderboardBadgeTests.swift`

**Context:** Badges are returned from the RPC as a JSONB array of strings like `["road_warrior", "five_star"]`. This enum maps those to display names and SF Symbol icons.

**Step 1: Write the failing test**

```swift
//  LeaderboardBadgeTests.swift
import XCTest
@testable import NaarsCars

final class LeaderboardBadgeTests: XCTestCase {

    func testDecodingFromString() throws {
        let json = "\"road_warrior\"".data(using: .utf8)!
        let badge = try JSONDecoder().decode(LeaderboardBadge.self, from: json)
        XCTAssertEqual(badge, .roadWarrior)
    }

    func testAllBadgesHaveDisplayName() {
        for badge in LeaderboardBadge.allCases {
            XCTAssertFalse(badge.displayName.isEmpty)
        }
    }

    func testAllBadgesHaveIcon() {
        for badge in LeaderboardBadge.allCases {
            XCTAssertFalse(badge.iconName.isEmpty)
        }
    }

    func testDecodingArray() throws {
        let json = "[\"road_warrior\",\"five_star\"]".data(using: .utf8)!
        let badges = try JSONDecoder().decode([LeaderboardBadge].self, from: json)
        XCTAssertEqual(badges, [.roadWarrior, .fiveStar])
    }

    func testUnknownBadgeDecodesGracefully() throws {
        // Unknown badges should be skipped, not crash
        let json = "[\"road_warrior\",\"unknown_badge\"]".data(using: .utf8)!
        let badges = try JSONDecoder().decode([LeaderboardBadge].self, from: json)
        // Should contain road_warrior; unknown_badge behavior depends on implementation
        XCTAssertTrue(badges.contains(.roadWarrior))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/LeaderboardBadgeTests 2>&1 | tail -20`
Expected: Compile error — `LeaderboardBadge` not found.

**Step 3: Write the implementation**

```swift
//  LeaderboardBadge.swift
import Foundation

/// Badge types earned on the leaderboard
enum LeaderboardBadge: String, Codable, CaseIterable, Equatable, Sendable {
    case roadWarrior = "road_warrior"
    case goodNeighbor = "good_neighbor"
    case streakChampion = "streak_champion"
    case fiveStar = "five_star"
    case risingStar = "rising_star"
    case bigSaver = "big_saver"

    var displayName: String {
        switch self {
        case .roadWarrior: return "Road Warrior"
        case .goodNeighbor: return "Good Neighbor"
        case .streakChampion: return "Streak Champ"
        case .fiveStar: return "Five Star"
        case .risingStar: return "Rising Star"
        case .bigSaver: return "Big Saver"
        }
    }

    var iconName: String {
        switch self {
        case .roadWarrior: return "car.fill"
        case .goodNeighbor: return "hands.clap.fill"
        case .streakChampion: return "flame.fill"
        case .fiveStar: return "star.fill"
        case .risingStar: return "rocket.fill"
        case .bigSaver: return "dollarsign.circle.fill"
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/LeaderboardBadgeTests 2>&1 | tail -20`
Expected: All PASS.

**Step 5: Commit**

```bash
git add NaarsCars/Core/Models/LeaderboardBadge.swift NaarsCars/NaarsCarsTests/Core/Models/LeaderboardBadgeTests.swift
git commit -m "feat: add LeaderboardBadge enum with display names and icons"
```

---

### Task 4: Update `LeaderboardEntry` model

**Files:**
- Modify: `NaarsCars/Core/Models/LeaderboardEntry.swift`
- Modify: `NaarsCars/NaarsCarsTests/Core/Models/LeaderboardEntryTests.swift`

**Context:** The model needs new fields: `xp`, `badges`, `streakWeeks`. The `CodingKeys` must map to the new RPC column names. Keep `requestsFulfilled` and `requestsMade` (still returned by RPC).

**Step 1: Update the test for new fields**

Add to `LeaderboardEntryTests.swift`:

```swift
func testCodableDecodingWithXP() throws {
    let json = """
    {
        "user_id": "123e4567-e89b-12d3-a456-426614174000",
        "name": "John Doe",
        "avatar_url": "https://example.com/avatar.jpg",
        "xp": 145,
        "badges": ["road_warrior", "five_star"],
        "streak_weeks": 4,
        "requests_fulfilled": 15,
        "requests_made": 8
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let entry = try decoder.decode(LeaderboardEntry.self, from: json)

    XCTAssertEqual(entry.xp, 145)
    XCTAssertEqual(entry.badges, [.roadWarrior, .fiveStar])
    XCTAssertEqual(entry.streakWeeks, 4)
    XCTAssertEqual(entry.requestsFulfilled, 15)
    XCTAssertEqual(entry.requestsMade, 8)
}

func testTopBadgesLimitedToTwo() {
    let entry = LeaderboardEntry(
        userId: UUID(),
        name: "Test",
        xp: 100,
        badges: [.roadWarrior, .goodNeighbor, .fiveStar],
        streakWeeks: 5,
        requestsFulfilled: 10,
        requestsMade: 5
    )
    XCTAssertEqual(entry.topBadges.count, 2)
}
```

**Step 2: Run tests to verify they fail**

Expected: Compile error — `xp`, `badges`, `streakWeeks` not found on `LeaderboardEntry`.

**Step 3: Update the model**

Replace `LeaderboardEntry.swift` contents:

```swift
import Foundation

struct LeaderboardEntry: Codable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    let avatarUrl: String?
    let xp: Int
    let badges: [LeaderboardBadge]
    let streakWeeks: Int
    let requestsFulfilled: Int
    let requestsMade: Int
    var rank: Int?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case avatarUrl = "avatar_url"
        case xp
        case badges
        case streakWeeks = "streak_weeks"
        case requestsFulfilled = "requests_fulfilled"
        case requestsMade = "requests_made"
    }

    var isCurrentUser: Bool {
        guard let currentUserId = AuthService.shared.currentUserId else { return false }
        return userId == currentUserId
    }

    /// Top 2 badges for display on leaderboard row
    var topBadges: [LeaderboardBadge] {
        Array(badges.prefix(2))
    }

    init(
        userId: UUID,
        name: String,
        avatarUrl: String? = nil,
        xp: Int,
        badges: [LeaderboardBadge] = [],
        streakWeeks: Int = 0,
        requestsFulfilled: Int,
        requestsMade: Int,
        rank: Int? = nil
    ) {
        self.userId = userId
        self.name = name
        self.avatarUrl = avatarUrl
        self.xp = xp
        self.badges = badges
        self.streakWeeks = streakWeeks
        self.requestsFulfilled = requestsFulfilled
        self.requestsMade = requestsMade
        self.rank = rank
    }
}
```

**Step 4: Fix existing tests that use old initializer**

Update all `LeaderboardEntry(...)` calls in `LeaderboardEntryTests.swift` and `LeaderboardViewModelTests.swift` to include `xp:` and remove any that no longer compile. The existing `testCodableDecoding` should be updated to use the new JSON shape.

**Step 5: Run tests**

Expected: All PASS.

**Step 6: Commit**

```bash
git add NaarsCars/Core/Models/LeaderboardEntry.swift NaarsCars/NaarsCarsTests/Core/Models/LeaderboardEntryTests.swift
git commit -m "feat: add xp, badges, streakWeeks to LeaderboardEntry model"
```

---

### Task 5: Add `SpotlightEntry` model

**Files:**
- Create: `NaarsCars/Core/Models/SpotlightEntry.swift`

**Context:** Represents a spotlight winner returned by `get_leaderboard_spotlights`. Simple struct — two instances max (longest_streak, rising_star).

**Step 1: Write the model**

```swift
//  SpotlightEntry.swift
import Foundation

/// A spotlight winner on the leaderboard
struct SpotlightEntry: Codable, Identifiable, Equatable {
    let category: String
    let userId: UUID
    let name: String
    let avatarUrl: String?
    let value: Int

    var id: String { category }

    enum CodingKeys: String, CodingKey {
        case category
        case userId = "user_id"
        case name
        case avatarUrl = "avatar_url"
        case value
    }

    var displayCategory: String {
        switch category {
        case "longest_streak": return "Longest Streak"
        case "rising_star": return "Rising Star"
        default: return category
        }
    }

    var iconName: String {
        switch category {
        case "longest_streak": return "flame.fill"
        case "rising_star": return "rocket.fill"
        default: return "star.fill"
        }
    }

    var formattedValue: String {
        switch category {
        case "longest_streak": return "\(value)w streak"
        case "rising_star": return "+\(value) XP"
        default: return "\(value)"
        }
    }
}
```

**Step 2: Commit**

```bash
git add NaarsCars/Core/Models/SpotlightEntry.swift
git commit -m "feat: add SpotlightEntry model for leaderboard spotlights"
```

---

### Task 6: Update `LeaderboardService`

**Files:**
- Modify: `NaarsCars/Core/Services/LeaderboardService.swift`

**Context:** Switch from calling `get_leaderboard` RPC to `get_xp_leaderboard`. Add a new method `fetchSpotlights` that calls `get_leaderboard_spotlights`. The `LeaderboardParams` struct is reused. Keep `findCurrentUserRank` working (it calls `fetchLeaderboard` internally).

**Step 1: Update `fetchLeaderboard` to call new RPC**

Change the RPC call from `"get_leaderboard"` to `"get_xp_leaderboard"` on line 114 of `LeaderboardService.swift`. That's the only change needed — the response decoding will work because `LeaderboardEntry` CodingKeys match the new function's column names.

Also update the filter on line 129: change `$0.requestsFulfilled > 0 || $0.requestsMade > 0` to `$0.xp > 0` (the RPC already filters, but belt-and-suspenders).

**Step 2: Add `fetchSpotlights` method**

Add after `fetchLeaderboard`:

```swift
/// Fetch spotlight winners for the leaderboard
func fetchSpotlights(period: LeaderboardPeriod) async throws -> [SpotlightEntry] {
    let (startDate, endDate) = period.dateRange

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

    let params = LeaderboardParams(
        start_date: dateFormatter.string(from: startDate),
        end_date: dateFormatter.string(from: endDate)
    )

    let client = await SupabaseService.shared.client

    let response = try await client
        .rpc("get_leaderboard_spotlights", params: params)
        .execute()

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let spotlights = try decoder.decode([SpotlightEntry].self, from: response.data)

    AppLogger.info("leaderboard", "Fetched \(spotlights.count) spotlight entries for period: \(period.displayName)")
    return spotlights
}
```

**Step 3: Update `findCurrentUserRank`**

No change needed — it calls `fetchLeaderboard` which now returns XP-sorted results. Rank is assigned by index, which is correct since results are sorted by XP DESC.

**Step 4: Commit**

```bash
git add NaarsCars/Core/Services/LeaderboardService.swift
git commit -m "feat: update LeaderboardService to use XP leaderboard and add spotlight fetching"
```

---

### Task 7: Update `LeaderboardViewModel`

**Files:**
- Modify: `NaarsCars/Features/Leaderboards/ViewModels/LeaderboardViewModel.swift`

**Context:** Add `spotlights` published property. Fetch spotlights in parallel with leaderboard data. Cache spotlights alongside entries.

**Step 1: Add spotlight state**

Add to published properties:

```swift
@Published var spotlights: [SpotlightEntry] = []
```

**Step 2: Update cache type**

Change cache to store spotlights too:

```swift
private var cachedEntries: [LeaderboardPeriod: (entries: [LeaderboardEntry], spotlights: [SpotlightEntry], cachedAt: Date)] = [:]
```

**Step 3: Update `loadLeaderboard`**

Update the cache check to also restore spotlights:

```swift
if let cached = cachedEntries[selectedPeriod],
   Date().timeIntervalSince(cached.cachedAt) < cacheTTL {
    entries = cached.entries
    spotlights = cached.spotlights
    updateCurrentUserRank()
    Task { await fetchFresh(showLoading: false) }
    return
}
```

**Step 4: Update `fetchFresh`**

Fetch entries and spotlights in parallel using `async let`:

```swift
private func fetchFresh(showLoading: Bool) async {
    if showLoading { isLoading = true }
    error = nil
    defer { if showLoading { isLoading = false } }

    do {
        async let entriesTask = leaderboardService.fetchLeaderboard(period: selectedPeriod)
        async let spotlightsTask = leaderboardService.fetchSpotlights(period: selectedPeriod)

        let (freshEntries, freshSpotlights) = try await (entriesTask, spotlightsTask)
        entries = freshEntries
        spotlights = freshSpotlights
        cachedEntries[selectedPeriod] = (freshEntries, freshSpotlights, Date())
        updateCurrentUserRank()
    } catch {
        self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
        AppLogger.error("leaderboard", "Error loading leaderboard: \(error.localizedDescription)")
    }
}
```

**Step 5: Commit**

```bash
git add NaarsCars/Features/Leaderboards/ViewModels/LeaderboardViewModel.swift
git commit -m "feat: add spotlight support to LeaderboardViewModel with parallel fetching"
```

---

### Task 8: Update `LeaderboardRow` to show XP and badges

**Files:**
- Modify: `NaarsCars/Features/Leaderboards/Views/LeaderboardRow.swift`

**Context:** Replace the "requests fulfilled" score display with XP. Add badge pills below the name. Keep rank badges (medals), avatar, and current-user highlighting.

**Step 1: Update the score section**

Replace the VStack that shows `entry.requestsFulfilled` and "fulfilled" label (lines 46-56) with:

```swift
VStack(alignment: .trailing, spacing: 2) {
    Text("\(entry.xp)")
        .font(.naarsTitle3)
        .fontWeight(.semibold)
        .foregroundColor(.naarsPrimary)

    Text("XP")
        .font(.naarsCaption)
        .foregroundColor(.secondary)
}
.accessibilityElement(children: .combine)
.accessibilityLabel("\(entry.xp) experience points")
```

**Step 2: Add badge pills below the name**

In the VStack with name and stats (lines 27-40), replace the stats HStack with badges:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text(entry.name)
        .font(.naarsHeadline)
        .foregroundColor(.primary)

    if !entry.topBadges.isEmpty {
        HStack(spacing: 6) {
            ForEach(entry.topBadges, id: \.self) { badge in
                Label(badge.displayName, systemImage: badge.iconName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.naarsPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.naarsPrimary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }
}
```

**Step 3: Update the preview**

Update preview entries to use the new initializer with `xp:` and `badges:` parameters.

**Step 4: Commit**

```bash
git add NaarsCars/Features/Leaderboards/Views/LeaderboardRow.swift
git commit -m "feat: update LeaderboardRow to display XP score and badge pills"
```

---

### Task 9: Create `SpotlightCard` view

**Files:**
- Create: `NaarsCars/Features/Leaderboards/Views/SpotlightCard.swift`

**Context:** A compact card showing a spotlight winner. Tappable to navigate to profile. Uses `AvatarView` (existing component, takes imageUrl, name, size).

**Step 1: Write the view**

```swift
//  SpotlightCard.swift
import SwiftUI

struct SpotlightCard: View {
    let spotlight: SpotlightEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: spotlight.iconName)
                .font(.naarsTitle3)
                .foregroundColor(.naarsPrimary)
                .frame(width: 32)

            AvatarView(
                imageUrl: spotlight.avatarUrl,
                name: spotlight.name,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(spotlight.displayCategory)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)

                Text(spotlight.name)
                    .font(.naarsHeadline)
                    .foregroundColor(.primary)
            }

            Spacer()

            Text(spotlight.formattedValue)
                .font(.naarsSubheadline)
                .fontWeight(.semibold)
                .foregroundColor(.naarsPrimary)
        }
        .padding(12)
        .background(Color.naarsCardBackground)
        .cornerRadius(10)
    }
}
```

**Step 2: Commit**

```bash
git add NaarsCars/Features/Leaderboards/Views/SpotlightCard.swift
git commit -m "feat: add SpotlightCard view for leaderboard spotlight winners"
```

---

### Task 10: Update `LeaderboardView` to include spotlights section

**Files:**
- Modify: `NaarsCars/Features/Leaderboards/Views/LeaderboardView.swift`

**Context:** Add a spotlights section below the main list. Spotlights are `NavigationLink`s to `PublicProfileView`. Only show if spotlights array is non-empty.

**Step 1: Add spotlights section**

In the `else` branch that renders the list (line 59 onward), add after the current user rank section and before the closing `}` of the List:

```swift
// Spotlights section
if !viewModel.spotlights.isEmpty {
    Section {
        ForEach(viewModel.spotlights) { spotlight in
            NavigationLink(destination: PublicProfileView(userId: spotlight.userId)) {
                SpotlightCard(spotlight: spotlight)
            }
            .buttonStyle(PlainButtonStyle())
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    } header: {
        Text("Spotlights")
            .font(.naarsHeadline)
            .foregroundColor(.primary)
            .textCase(nil)
            .padding(.top, 8)
    }
}
```

**Step 2: Commit**

```bash
git add NaarsCars/Features/Leaderboards/Views/LeaderboardView.swift
git commit -m "feat: add spotlights section to LeaderboardView"
```

---

### Task 11: Add XP toast to completion flow

**Files:**
- Modify: `NaarsCars/Features/Claiming/Views/CompleteSheet.swift`

**Context:** After a request is completed, show a "+N XP" toast using the existing `.toast(message:style:)` modifier. The toast should appear after the success checkmark dismisses. Since we don't know the exact XP earned without querying (it depends on ride savings, etc.), show a generic message for now. A ride completion always earns at least 5 XP base; a favor completion earns 10 XP.

**Step 1: Add toast state and show it**

Add to `CompleteSheet`:

```swift
@State private var toastMessage: String? = nil
```

In the `onConfirm` callback area, after `showSuccess = true`, set the toast:

```swift
let xpMessage = requestType == "ride" ? "+5 XP (+ savings bonus)" : "+10 XP"
toastMessage = xpMessage
```

Add the `.toast` modifier to the view:

```swift
.toast(message: $toastMessage, style: .success)
```

**Step 2: Commit**

```bash
git add NaarsCars/Features/Claiming/Views/CompleteSheet.swift
git commit -m "feat: show XP earned toast on request completion"
```

---

### Task 12: Update existing tests

**Files:**
- Modify: `NaarsCars/NaarsCarsTests/Core/Services/LeaderboardServiceTests.swift`
- Modify: `NaarsCars/NaarsCarsTests/Features/Leaderboards/LeaderboardViewModelTests.swift`

**Context:** Tests use real Supabase calls. Update assertions to check XP-based ordering instead of requestsFulfilled-based ordering. Add spotlight test.

**Step 1: Update `LeaderboardServiceTests`**

In `testFetchLeaderboard_OrderedByCount`, change the ordering assertion:

```swift
// Then: Entries should be ordered by XP descending
var previousXP: Int? = nil
for entry in entries {
    if let prev = previousXP {
        XCTAssertGreaterThanOrEqual(prev, entry.xp, "Entries should be ordered by XP descending")
    }
    previousXP = entry.xp
}
```

Add a new test:

```swift
func testFetchSpotlights() async throws {
    do {
        let spotlights = try await leaderboardService.fetchSpotlights(period: .allTime)
        // Should return 0-2 spotlights
        XCTAssertLessThanOrEqual(spotlights.count, 2)
        for spotlight in spotlights {
            XCTAssertTrue(["longest_streak", "rising_star"].contains(spotlight.category))
            XCTAssertGreaterThan(spotlight.value, 0)
        }
    } catch {
        XCTFail("Failed to fetch spotlights: \(error.localizedDescription)")
    }
}
```

**Step 2: Update `LeaderboardViewModelTests`**

No logic changes needed — just ensure tests compile with updated `LeaderboardEntry` initializer (done in Task 4).

**Step 3: Run all leaderboard tests**

Run: `xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/LeaderboardEntryTests -only-testing:NaarsCarsTests/LeaderboardBadgeTests -only-testing:NaarsCarsTests/LeaderboardServiceTests -only-testing:NaarsCarsTests/LeaderboardViewModelTests 2>&1 | tail -30`
Expected: All PASS.

**Step 4: Commit**

```bash
git add NaarsCars/NaarsCarsTests/
git commit -m "test: update leaderboard tests for XP-based scoring and spotlights"
```

---

### Task 13: Run advisors and verify

**Step 1:** Run `mcp__supabase__get_advisors` for both security and performance to check for any issues with the new functions.

**Step 2:** Fix any flagged issues.

**Step 3:** Final commit if any fixes needed.
