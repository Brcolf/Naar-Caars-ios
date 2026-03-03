-- Migration: Deduplicate leaderboard spotlights and add top_requester category
-- Returns up to 3 spotlight winners with unique user_ids:
--   1. longest_streak  – consecutive weeks fulfilling requests
--   2. rising_star     – most direct-action XP in date range
--   3. top_requester   – most requests posted (rides + favors) in date range
--
-- Uses a temp table _claimed_users to enforce uniqueness across categories.

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

    -- Temp table to track already-claimed user IDs (dropped at end of txn)
    CREATE TEMP TABLE IF NOT EXISTS _claimed_users (
        uid UUID PRIMARY KEY
    ) ON COMMIT DROP;
    TRUNCATE _claimed_users;

    -- -----------------------------------------------------------------
    -- Category 1: longest_streak
    -- The user with the most consecutive weeks of fulfilling at least
    -- one request (ride or favor) in the date range.
    -- Uses DATE_TRUNC('week', ...) gaps-and-islands approach.
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
    )
    SELECT
        'longest_streak'::TEXT        AS category,
        p.id                          AS user_id,
        p.name                        AS name,
        p.avatar_url                  AS avatar_url,
        lpu.longest_streak            AS value
    FROM longest_per_user lpu
    JOIN profiles p ON p.id = lpu.uid
    WHERE p.approved = true
      AND lpu.longest_streak > 0
      AND lpu.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY lpu.longest_streak DESC, p.name ASC
    LIMIT 1;

    -- Claim the longest_streak winner
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
    )
    SELECT lpu.uid
    FROM longest_per_user lpu
    JOIN profiles p ON p.id = lpu.uid
    WHERE p.approved = true
      AND lpu.longest_streak > 0
      AND lpu.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY lpu.longest_streak DESC, p.name ASC
    LIMIT 1
    ON CONFLICT DO NOTHING;

    -- -----------------------------------------------------------------
    -- Category 2: rising_star
    -- The user who gained the most direct-action XP in the date range.
    -- XP formula:
    --   Ride fulfilled:  5 + floor(estimated_cost / 5)
    --   Favor fulfilled: 10 flat
    --   Ride requested:  5
    --   Favor requested: 5
    --   5-star review:   5
    --   4-star review:   2
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    rides_fulfilled_xp AS (
        SELECT
            r.claimed_by AS uid,
            SUM(5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::BIGINT AS xp
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    favors_fulfilled_xp AS (
        SELECT
            f.claimed_by AS uid,
            (COUNT(*) * 10)::BIGINT AS xp
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    rides_requested_xp AS (
        SELECT
            r.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favors_requested_xp AS (
        SELECT
            f.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    review_xp AS (
        SELECT
            rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5
                     WHEN rv.rating = 4 THEN 2
                     ELSE 0 END)::BIGINT AS xp
        FROM reviews rv
        WHERE rv.created_at::date BETWEEN start_date AND end_date
        GROUP BY rv.fulfiller_id
    ),
    all_users AS (
        SELECT uid FROM rides_fulfilled_xp
        UNION SELECT uid FROM favors_fulfilled_xp
        UNION SELECT uid FROM rides_requested_xp
        UNION SELECT uid FROM favors_requested_xp
        UNION SELECT uid FROM review_xp
    ),
    user_totals AS (
        SELECT
            au.uid,
            (
                COALESCE(rf.xp, 0)
                + COALESCE(ff.xp, 0)
                + COALESCE(rr.xp, 0)
                + COALESCE(fr.xp, 0)
                + COALESCE(rv.xp, 0)
            )::BIGINT AS total_xp
        FROM all_users au
        LEFT JOIN rides_fulfilled_xp  rf ON rf.uid = au.uid
        LEFT JOIN favors_fulfilled_xp ff ON ff.uid = au.uid
        LEFT JOIN rides_requested_xp  rr ON rr.uid = au.uid
        LEFT JOIN favors_requested_xp fr ON fr.uid = au.uid
        LEFT JOIN review_xp           rv ON rv.uid = au.uid
    )
    SELECT
        'rising_star'::TEXT           AS category,
        p.id                          AS user_id,
        p.name                        AS name,
        p.avatar_url                  AS avatar_url,
        ut.total_xp                   AS value
    FROM user_totals ut
    JOIN profiles p ON p.id = ut.uid
    WHERE p.approved = true
      AND ut.total_xp > 0
      AND ut.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY ut.total_xp DESC, p.name ASC
    LIMIT 1;

    -- Claim the rising_star winner
    INSERT INTO _claimed_users (uid)
    WITH
    rides_fulfilled_xp AS (
        SELECT
            r.claimed_by AS uid,
            SUM(5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::BIGINT AS xp
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    favors_fulfilled_xp AS (
        SELECT
            f.claimed_by AS uid,
            (COUNT(*) * 10)::BIGINT AS xp
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    rides_requested_xp AS (
        SELECT
            r.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favors_requested_xp AS (
        SELECT
            f.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    review_xp AS (
        SELECT
            rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5
                     WHEN rv.rating = 4 THEN 2
                     ELSE 0 END)::BIGINT AS xp
        FROM reviews rv
        WHERE rv.created_at::date BETWEEN start_date AND end_date
        GROUP BY rv.fulfiller_id
    ),
    all_users AS (
        SELECT uid FROM rides_fulfilled_xp
        UNION SELECT uid FROM favors_fulfilled_xp
        UNION SELECT uid FROM rides_requested_xp
        UNION SELECT uid FROM favors_requested_xp
        UNION SELECT uid FROM review_xp
    ),
    user_totals AS (
        SELECT
            au.uid,
            (
                COALESCE(rf.xp, 0)
                + COALESCE(ff.xp, 0)
                + COALESCE(rr.xp, 0)
                + COALESCE(fr.xp, 0)
                + COALESCE(rv.xp, 0)
            )::BIGINT AS total_xp
        FROM all_users au
        LEFT JOIN rides_fulfilled_xp  rf ON rf.uid = au.uid
        LEFT JOIN favors_fulfilled_xp ff ON ff.uid = au.uid
        LEFT JOIN rides_requested_xp  rr ON rr.uid = au.uid
        LEFT JOIN favors_requested_xp fr ON fr.uid = au.uid
        LEFT JOIN review_xp           rv ON rv.uid = au.uid
    )
    SELECT ut.uid
    FROM user_totals ut
    JOIN profiles p ON p.id = ut.uid
    WHERE p.approved = true
      AND ut.total_xp > 0
      AND ut.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY ut.total_xp DESC, p.name ASC
    LIMIT 1
    ON CONFLICT DO NOTHING;

    -- -----------------------------------------------------------------
    -- Category 3: top_requester
    -- The user who posted the most requests (rides + favors) in the
    -- date range.
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    ride_counts AS (
        SELECT
            r.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favor_counts AS (
        SELECT
            f.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    all_requesters AS (
        SELECT uid FROM ride_counts
        UNION SELECT uid FROM favor_counts
    ),
    requester_totals AS (
        SELECT
            ar.uid,
            (COALESCE(rc.cnt, 0) + COALESCE(fc.cnt, 0))::BIGINT AS total_requests
        FROM all_requesters ar
        LEFT JOIN ride_counts  rc ON rc.uid = ar.uid
        LEFT JOIN favor_counts fc ON fc.uid = ar.uid
    )
    SELECT
        'top_requester'::TEXT         AS category,
        p.id                          AS user_id,
        p.name                        AS name,
        p.avatar_url                  AS avatar_url,
        rt.total_requests             AS value
    FROM requester_totals rt
    JOIN profiles p ON p.id = rt.uid
    WHERE p.approved = true
      AND rt.total_requests > 0
      AND rt.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY rt.total_requests DESC, p.name ASC
    LIMIT 1;

    -- Claim the top_requester winner
    INSERT INTO _claimed_users (uid)
    WITH
    ride_counts AS (
        SELECT
            r.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favor_counts AS (
        SELECT
            f.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    all_requesters AS (
        SELECT uid FROM ride_counts
        UNION SELECT uid FROM favor_counts
    ),
    requester_totals AS (
        SELECT
            ar.uid,
            (COALESCE(rc.cnt, 0) + COALESCE(fc.cnt, 0))::BIGINT AS total_requests
        FROM all_requesters ar
        LEFT JOIN ride_counts  rc ON rc.uid = ar.uid
        LEFT JOIN favor_counts fc ON fc.uid = ar.uid
    )
    SELECT rt.uid
    FROM requester_totals rt
    JOIN profiles p ON p.id = rt.uid
    WHERE p.approved = true
      AND rt.total_requests > 0
      AND rt.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY rt.total_requests DESC, p.name ASC
    LIMIT 1
    ON CONFLICT DO NOTHING;

END;
$$;

-- Grant execute to both authenticated and anon roles
GRANT EXECUTE ON FUNCTION get_leaderboard_spotlights(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_leaderboard_spotlights(DATE, DATE) TO anon;
