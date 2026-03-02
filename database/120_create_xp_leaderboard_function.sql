-- Migration: Create XP-based leaderboard function
-- Replaces the old get_leaderboard with a richer scoring system
-- including XP points, badges, and streak tracking.

-- Index for review-based XP lookups (fulfiller + rating + created_at)
CREATE INDEX IF NOT EXISTS idx_reviews_fulfiller_id_rating
ON reviews(fulfiller_id, rating, created_at);

-- Drop the function first to allow changing the return type signature
DROP FUNCTION IF EXISTS get_xp_leaderboard(DATE, DATE);

CREATE OR REPLACE FUNCTION get_xp_leaderboard(
    start_date DATE DEFAULT '1970-01-01',
    end_date   DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    user_id            UUID,
    name               TEXT,
    avatar_url         TEXT,
    xp                 BIGINT,
    badges             JSONB,
    streak_weeks       BIGINT,
    requests_fulfilled BIGINT,
    requests_made      BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    WITH

    -- ---------------------------------------------------------------
    -- 1. Rides fulfilled in the date range
    -- ---------------------------------------------------------------
    rides_fulfilled AS (
        SELECT
            r.claimed_by                         AS uid,
            COUNT(*)                             AS cnt,
            -- 5 base + 1 per $5 saved; estimated_cost can be NULL
            SUM(5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::BIGINT AS xp_fulfill,
            COALESCE(SUM(r.estimated_cost), 0)   AS total_savings
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),

    -- ---------------------------------------------------------------
    -- 2. Favors fulfilled in the date range
    -- ---------------------------------------------------------------
    favors_fulfilled AS (
        SELECT
            f.claimed_by       AS uid,
            COUNT(*)           AS cnt,
            (COUNT(*) * 10)::BIGINT AS xp_fulfill   -- 10 flat per favor
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),

    -- ---------------------------------------------------------------
    -- 3. Rides requested in the date range
    -- ---------------------------------------------------------------
    rides_requested AS (
        SELECT
            r.user_id          AS uid,
            COUNT(*)           AS cnt,
            (COUNT(*) * 5)::BIGINT AS xp_request     -- 5 per ride requested
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),

    -- ---------------------------------------------------------------
    -- 4. Favors requested in the date range
    -- ---------------------------------------------------------------
    favors_requested AS (
        SELECT
            f.user_id          AS uid,
            COUNT(*)           AS cnt,
            (COUNT(*) * 5)::BIGINT AS xp_request     -- 5 per favor requested
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),

    -- ---------------------------------------------------------------
    -- 5. First-request milestones (one-time, 10 XP each)
    --    Award only if user's very first ride/favor request ever
    --    falls inside the date range.
    -- ---------------------------------------------------------------
    first_ride_milestones AS (
        SELECT r.user_id AS uid, 10::BIGINT AS bonus
        FROM rides r
        GROUP BY r.user_id
        HAVING MIN(r.created_at)::date BETWEEN start_date AND end_date
    ),
    first_favor_milestones AS (
        SELECT f.user_id AS uid, 10::BIGINT AS bonus
        FROM favors f
        GROUP BY f.user_id
        HAVING MIN(f.created_at)::date BETWEEN start_date AND end_date
    ),

    -- ---------------------------------------------------------------
    -- 6. Review bonuses (5-star = 5 XP, 4-star = 2 XP)
    -- ---------------------------------------------------------------
    review_xp AS (
        SELECT
            rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5
                     WHEN rv.rating = 4 THEN 2
                     ELSE 0 END)::BIGINT AS xp_reviews,
            COUNT(*) FILTER (WHERE rv.rating = 5) AS five_star_count
        FROM reviews rv
        WHERE rv.created_at::date BETWEEN start_date AND end_date
        GROUP BY rv.fulfiller_id
    ),

    -- ---------------------------------------------------------------
    -- 7. Streak calculation (gaps-and-islands on calendar weeks)
    --    A "week" = ISO week of the fulfillment's updated_at.
    --    We union rides + favors fulfilled, then find consecutive
    --    week runs per user.
    -- ---------------------------------------------------------------
    fulfilled_weeks AS (
        -- Distinct (user, week_start) pairs for completed fulfillments
        -- Using DATE_TRUNC('week', ...) for correct year-boundary handling
        SELECT DISTINCT
            claimed_by AS uid,
            DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM rides
        WHERE claimed_by IS NOT NULL
          AND status = 'completed'
          AND updated_at::date BETWEEN start_date AND end_date

        UNION

        SELECT DISTINCT
            claimed_by AS uid,
            DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM favors
        WHERE claimed_by IS NOT NULL
          AND status = 'completed'
          AND updated_at::date BETWEEN start_date AND end_date
    ),
    week_numbered AS (
        SELECT
            uid,
            week_start,
            ROW_NUMBER() OVER (PARTITION BY uid ORDER BY week_start) AS rn
        FROM fulfilled_weeks
    ),
    streaks AS (
        -- Gaps-and-islands: group consecutive weeks by (week_start - rn * 7 days)
        SELECT
            uid,
            COUNT(*)::BIGINT AS streak_len
        FROM week_numbered
        GROUP BY uid, (week_start - (rn * INTERVAL '7 days'))
    ),
    longest_streaks AS (
        SELECT
            uid,
            MAX(streak_len)::BIGINT AS longest_streak
        FROM streaks
        GROUP BY uid
    ),

    -- ---------------------------------------------------------------
    -- 8. Collect all user IDs that earned anything
    -- ---------------------------------------------------------------
    all_users AS (
        SELECT uid FROM rides_fulfilled
        UNION SELECT uid FROM favors_fulfilled
        UNION SELECT uid FROM rides_requested
        UNION SELECT uid FROM favors_requested
        UNION SELECT uid FROM first_ride_milestones
        UNION SELECT uid FROM first_favor_milestones
        UNION SELECT uid FROM review_xp
        UNION SELECT uid FROM longest_streaks
    ),

    -- ---------------------------------------------------------------
    -- 9. Assemble per-user totals
    -- ---------------------------------------------------------------
    user_totals AS (
        SELECT
            au.uid,
            -- Fulfillment XP
            COALESCE(rf.xp_fulfill, 0)
            + COALESCE(ff.xp_fulfill, 0)
            -- Request XP
            + COALESCE(rr.xp_request, 0)
            + COALESCE(fr.xp_request, 0)
            -- Milestone bonuses
            + COALESCE(frm.bonus, 0)
            + COALESCE(ffm.bonus, 0)
            -- Review XP
            + COALESCE(rv.xp_reviews, 0)
            -- Streak XP
            + COALESCE(ls.longest_streak, 0) * 5
            AS total_xp,

            -- Badge inputs
            COALESCE(rf.cnt, 0)              AS rides_fulfilled_cnt,
            COALESCE(ff.cnt, 0)              AS favors_fulfilled_cnt,
            COALESCE(ls.longest_streak, 0)   AS streak_wks,
            COALESCE(rv.five_star_count, 0)  AS five_star_cnt,
            COALESCE(rf.total_savings, 0)    AS savings,

            -- Output columns
            COALESCE(rf.cnt, 0) + COALESCE(ff.cnt, 0)  AS fulfilled_total,
            COALESCE(rr.cnt, 0) + COALESCE(fr.cnt, 0)  AS made_total
        FROM all_users au
        LEFT JOIN rides_fulfilled     rf  ON rf.uid = au.uid
        LEFT JOIN favors_fulfilled    ff  ON ff.uid = au.uid
        LEFT JOIN rides_requested     rr  ON rr.uid = au.uid
        LEFT JOIN favors_requested    fr  ON fr.uid = au.uid
        LEFT JOIN first_ride_milestones  frm ON frm.uid = au.uid
        LEFT JOIN first_favor_milestones ffm ON ffm.uid = au.uid
        LEFT JOIN review_xp           rv  ON rv.uid = au.uid
        LEFT JOIN longest_streaks     ls  ON ls.uid = au.uid
    )

    -- ---------------------------------------------------------------
    -- 10. Final SELECT with badge assembly
    -- ---------------------------------------------------------------
    SELECT
        p.id                              AS user_id,
        p.name                            AS name,
        p.avatar_url                      AS avatar_url,
        ut.total_xp::BIGINT               AS xp,
        -- Badges as JSONB array
        (
            SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb)
            FROM (
                SELECT 'road_warrior'    AS badge WHERE ut.rides_fulfilled_cnt >= 10
                UNION ALL
                SELECT 'good_neighbor'   AS badge WHERE ut.favors_fulfilled_cnt >= 10
                UNION ALL
                SELECT 'streak_champion' AS badge WHERE ut.streak_wks >= 3
                UNION ALL
                SELECT 'five_star'       AS badge WHERE ut.five_star_cnt >= 10
                UNION ALL
                SELECT 'big_saver'       AS badge WHERE ut.savings >= 250
            ) b
        )                                 AS badges,
        ut.streak_wks::BIGINT             AS streak_weeks,
        ut.fulfilled_total::BIGINT        AS requests_fulfilled,
        ut.made_total::BIGINT             AS requests_made
    FROM user_totals ut
    JOIN profiles p ON p.id = ut.uid
    WHERE p.approved = true
      AND ut.total_xp > 0
    ORDER BY ut.total_xp DESC
    LIMIT 100;
END;
$$;

-- Grant execute to both authenticated and anon roles
GRANT EXECUTE ON FUNCTION get_xp_leaderboard(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_xp_leaderboard(DATE, DATE) TO anon;
