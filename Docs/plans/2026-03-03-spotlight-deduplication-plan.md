# Spotlight Deduplication Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a third spotlight category (top_requester), deduplicate so each user appears at most once, and cap at 3 spotlights.

**Architecture:** Replace the existing `get_leaderboard_spotlights` DB function with a new version that computes top-3 candidates per category, then deduplicates in priority order (longest_streak > rising_star > top_requester) using a temp table of claimed user IDs. Client-side changes are minimal — add mappings for the new category.

**Tech Stack:** PostgreSQL (plpgsql), Swift/SwiftUI, Supabase MCP

---

### Task 1: Deploy updated `get_leaderboard_spotlights` database function

**Files:**
- Create: `database/124_spotlight_dedup_and_top_requester.sql`

**Step 1: Write the migration SQL**

Create `database/124_spotlight_dedup_and_top_requester.sql` with the following content:

```sql
-- Migration: Add top_requester category, deduplicate spotlights
-- Returns up to 3 spotlight winners with unique users.
-- Priority: longest_streak > rising_star > top_requester

DROP FUNCTION IF EXISTS get_leaderboard_spotlights(DATE, DATE);

CREATE OR REPLACE FUNCTION get_leaderboard_spotlights(
    start_date DATE DEFAULT '1970-01-01',
    end_date   DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    category   TEXT,
    user_id    UUID,
    name       TEXT,
    avatar_url TEXT,
    value      BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- Temp table to track claimed users for deduplication
    CREATE TEMP TABLE IF NOT EXISTS _claimed_users (uid UUID PRIMARY KEY) ON COMMIT DROP;
    TRUNCATE _claimed_users;

    -- -----------------------------------------------------------------
    -- Category 1 (highest priority): longest_streak
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    fulfilled_weeks AS (
        SELECT DISTINCT
            r.claimed_by AS uid,
            DATE_TRUNC('week', r.updated_at)::DATE AS week_start
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        UNION
        SELECT DISTINCT
            f.claimed_by AS uid,
            DATE_TRUNC('week', f.updated_at)::DATE AS week_start
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
    ),
    week_numbered AS (
        SELECT
            fw.uid,
            fw.week_start,
            ROW_NUMBER() OVER (PARTITION BY fw.uid ORDER BY fw.week_start) AS rn
        FROM fulfilled_weeks fw
    ),
    streaks AS (
        SELECT
            wn.uid,
            COUNT(*)::BIGINT AS streak_len
        FROM week_numbered wn
        GROUP BY wn.uid, (wn.week_start - (wn.rn * INTERVAL '7 days'))
    ),
    longest_per_user AS (
        SELECT
            s.uid,
            MAX(s.streak_len)::BIGINT AS longest_streak
        FROM streaks s
        GROUP BY s.uid
    ),
    winner AS (
        SELECT
            p.id                   AS user_id,
            p.name                 AS name,
            p.avatar_url           AS avatar_url,
            lpu.longest_streak     AS value
        FROM longest_per_user lpu
        JOIN profiles p ON p.id = lpu.uid
        WHERE p.approved = true
          AND lpu.longest_streak > 0
          AND lpu.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
        ORDER BY lpu.longest_streak DESC, p.name ASC
        LIMIT 1
    )
    SELECT 'longest_streak'::TEXT AS category, w.user_id, w.name, w.avatar_url, w.value
    FROM winner w;

    -- Claim the winner
    INSERT INTO _claimed_users (uid)
    WITH
    fulfilled_weeks AS (
        SELECT DISTINCT
            r.claimed_by AS uid,
            DATE_TRUNC('week', r.updated_at)::DATE AS week_start
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        UNION
        SELECT DISTINCT
            f.claimed_by AS uid,
            DATE_TRUNC('week', f.updated_at)::DATE AS week_start
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
    ),
    week_numbered AS (
        SELECT fw.uid, fw.week_start,
            ROW_NUMBER() OVER (PARTITION BY fw.uid ORDER BY fw.week_start) AS rn
        FROM fulfilled_weeks fw
    ),
    streaks AS (
        SELECT wn.uid, COUNT(*)::BIGINT AS streak_len
        FROM week_numbered wn
        GROUP BY wn.uid, (wn.week_start - (wn.rn * INTERVAL '7 days'))
    ),
    longest_per_user AS (
        SELECT s.uid, MAX(s.streak_len)::BIGINT AS longest_streak
        FROM streaks s GROUP BY s.uid
    )
    SELECT p.id
    FROM longest_per_user lpu
    JOIN profiles p ON p.id = lpu.uid
    WHERE p.approved = true AND lpu.longest_streak > 0
      AND lpu.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY lpu.longest_streak DESC, p.name ASC
    LIMIT 1
    ON CONFLICT DO NOTHING;

    -- -----------------------------------------------------------------
    -- Category 2: rising_star
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    rides_fulfilled_xp AS (
        SELECT r.claimed_by AS uid,
            SUM(5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::BIGINT AS xp
        FROM rides r
        WHERE r.claimed_by IS NOT NULL AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    favors_fulfilled_xp AS (
        SELECT f.claimed_by AS uid, (COUNT(*) * 10)::BIGINT AS xp
        FROM favors f
        WHERE f.claimed_by IS NOT NULL AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    rides_requested_xp AS (
        SELECT r.user_id AS uid, (COUNT(*) * 5)::BIGINT AS xp
        FROM rides r WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favors_requested_xp AS (
        SELECT f.user_id AS uid, (COUNT(*) * 5)::BIGINT AS xp
        FROM favors f WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    review_xp AS (
        SELECT rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5 WHEN rv.rating = 4 THEN 2 ELSE 0 END)::BIGINT AS xp
        FROM reviews rv WHERE rv.created_at::date BETWEEN start_date AND end_date
        GROUP BY rv.fulfiller_id
    ),
    all_users AS (
        SELECT uid FROM rides_fulfilled_xp UNION SELECT uid FROM favors_fulfilled_xp
        UNION SELECT uid FROM rides_requested_xp UNION SELECT uid FROM favors_requested_xp
        UNION SELECT uid FROM review_xp
    ),
    user_totals AS (
        SELECT au.uid,
            (COALESCE(rf.xp,0)+COALESCE(ff.xp,0)+COALESCE(rr.xp,0)+COALESCE(fr.xp,0)+COALESCE(rv.xp,0))::BIGINT AS total_xp
        FROM all_users au
        LEFT JOIN rides_fulfilled_xp  rf ON rf.uid = au.uid
        LEFT JOIN favors_fulfilled_xp ff ON ff.uid = au.uid
        LEFT JOIN rides_requested_xp  rr ON rr.uid = au.uid
        LEFT JOIN favors_requested_xp fr ON fr.uid = au.uid
        LEFT JOIN review_xp           rv ON rv.uid = au.uid
    ),
    winner AS (
        SELECT p.id AS user_id, p.name, p.avatar_url, ut.total_xp AS value
        FROM user_totals ut
        JOIN profiles p ON p.id = ut.uid
        WHERE p.approved = true AND ut.total_xp > 0
          AND ut.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
        ORDER BY ut.total_xp DESC, p.name ASC
        LIMIT 1
    )
    SELECT 'rising_star'::TEXT AS category, w.user_id, w.name, w.avatar_url, w.value
    FROM winner w;

    -- Claim the winner
    INSERT INTO _claimed_users (uid)
    WITH
    rides_fulfilled_xp AS (
        SELECT r.claimed_by AS uid,
            SUM(5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::BIGINT AS xp
        FROM rides r
        WHERE r.claimed_by IS NOT NULL AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    favors_fulfilled_xp AS (
        SELECT f.claimed_by AS uid, (COUNT(*) * 10)::BIGINT AS xp
        FROM favors f WHERE f.claimed_by IS NOT NULL AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    rides_requested_xp AS (
        SELECT r.user_id AS uid, (COUNT(*) * 5)::BIGINT AS xp
        FROM rides r WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favors_requested_xp AS (
        SELECT f.user_id AS uid, (COUNT(*) * 5)::BIGINT AS xp
        FROM favors f WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    review_xp AS (
        SELECT rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5 WHEN rv.rating = 4 THEN 2 ELSE 0 END)::BIGINT AS xp
        FROM reviews rv WHERE rv.created_at::date BETWEEN start_date AND end_date
        GROUP BY rv.fulfiller_id
    ),
    all_users AS (
        SELECT uid FROM rides_fulfilled_xp UNION SELECT uid FROM favors_fulfilled_xp
        UNION SELECT uid FROM rides_requested_xp UNION SELECT uid FROM favors_requested_xp
        UNION SELECT uid FROM review_xp
    ),
    user_totals AS (
        SELECT au.uid,
            (COALESCE(rf.xp,0)+COALESCE(ff.xp,0)+COALESCE(rr.xp,0)+COALESCE(fr.xp,0)+COALESCE(rv.xp,0))::BIGINT AS total_xp
        FROM all_users au
        LEFT JOIN rides_fulfilled_xp  rf ON rf.uid = au.uid
        LEFT JOIN favors_fulfilled_xp ff ON ff.uid = au.uid
        LEFT JOIN rides_requested_xp  rr ON rr.uid = au.uid
        LEFT JOIN favors_requested_xp fr ON fr.uid = au.uid
        LEFT JOIN review_xp           rv ON rv.uid = au.uid
    )
    SELECT p.id
    FROM user_totals ut
    JOIN profiles p ON p.id = ut.uid
    WHERE p.approved = true AND ut.total_xp > 0
      AND ut.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY ut.total_xp DESC, p.name ASC
    LIMIT 1
    ON CONFLICT DO NOTHING;

    -- -----------------------------------------------------------------
    -- Category 3 (lowest priority): top_requester
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    request_counts AS (
        SELECT r.user_id AS uid, COUNT(*)::BIGINT AS cnt
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
        UNION ALL
        SELECT f.user_id AS uid, COUNT(*)::BIGINT AS cnt
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    user_totals AS (
        SELECT rc.uid, SUM(rc.cnt)::BIGINT AS total_requests
        FROM request_counts rc
        GROUP BY rc.uid
    ),
    winner AS (
        SELECT p.id AS user_id, p.name, p.avatar_url, ut.total_requests AS value
        FROM user_totals ut
        JOIN profiles p ON p.id = ut.uid
        WHERE p.approved = true AND ut.total_requests > 0
          AND ut.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
        ORDER BY ut.total_requests DESC, p.name ASC
        LIMIT 1
    )
    SELECT 'top_requester'::TEXT AS category, w.user_id, w.name, w.avatar_url, w.value
    FROM winner w;

END;
$$;

GRANT EXECUTE ON FUNCTION get_leaderboard_spotlights(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_leaderboard_spotlights(DATE, DATE) TO anon;
```

**Step 2: Apply the migration via Supabase MCP**

Use `mcp__supabase__apply_migration` with name `spotlight_dedup_and_top_requester` and the SQL above.

**Step 3: Verify the migration**

Run via `mcp__supabase__execute_sql`:
```sql
SELECT * FROM get_leaderboard_spotlights('1970-01-01', CURRENT_DATE);
```

Expected: Up to 3 rows, each with a unique `user_id`, categories from `{longest_streak, rising_star, top_requester}`.

**Step 4: Commit**

```bash
git add database/124_spotlight_dedup_and_top_requester.sql
git commit -m "feat: add top_requester spotlight, deduplicate across categories"
```

---

### Task 2: Add `top_requester` mappings to SpotlightEntry

**Files:**
- Modify: `NaarsCars/Core/Models/SpotlightEntry.swift:28-49`

**Step 1: Add `top_requester` to `displayCategory`**

In `SpotlightEntry.swift`, add a case to the `displayCategory` switch (after line 31):

```swift
case "top_requester": return "spotlight_top_requester".localized
```

**Step 2: Add `top_requester` to `iconName`**

Add a case to the `iconName` switch (after line 39):

```swift
case "top_requester": return "hand.raised.fill"
```

**Step 3: Add `top_requester` to `formattedValue`**

Add a case to the `formattedValue` switch (after line 47):

```swift
case "top_requester": return "spotlight_requester_value".localized(with: value)
```

**Step 4: Commit**

```bash
git add NaarsCars/Core/Models/SpotlightEntry.swift
git commit -m "feat: add top_requester display mappings to SpotlightEntry"
```

---

### Task 3: Add localization strings

**Files:**
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Step 1: Add `spotlight_top_requester` key**

Insert after the `spotlight_streak_value` block (after line 31646), before the `"Stats"` key:

```json
    "spotlight_top_requester": {
      "extractionState": "manual",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Top Requester"
          }
        }
      }
    },
    "spotlight_requester_value": {
      "extractionState": "manual",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "%lld requests"
          }
        }
      }
    },
```

**Step 2: Commit**

```bash
git add NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add localization keys for top_requester spotlight"
```

---

### Task 4: Update tests

**Files:**
- Modify: `NaarsCars/NaarsCarsTests/Core/Services/LeaderboardServiceTests.swift:44-58`

**Step 1: Update `testFetchSpotlights` assertion**

Update the test to accept the new category and count:

```swift
func testFetchSpotlights() async throws {
    do {
        let spotlights = try await leaderboardService.fetchSpotlights(period: .allTime)

        // Should return 0-3 spotlights with unique users
        XCTAssertLessThanOrEqual(spotlights.count, 3)

        let validCategories: Set<String> = ["longest_streak", "rising_star", "top_requester"]
        for spotlight in spotlights {
            XCTAssertTrue(validCategories.contains(spotlight.category),
                          "Unexpected category: \(spotlight.category)")
            XCTAssertGreaterThan(spotlight.value, 0)
        }

        // Verify no duplicate users
        let userIds = spotlights.map { $0.userId }
        XCTAssertEqual(userIds.count, Set(userIds).count, "Spotlight users should be unique")
    } catch {
        XCTFail("Failed to fetch spotlights: \(error.localizedDescription)")
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build-for-testing -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

**Step 3: Commit**

```bash
git add NaarsCars/NaarsCarsTests/Core/Services/LeaderboardServiceTests.swift
git commit -m "test: update spotlight test for 3 categories and deduplication"
```
