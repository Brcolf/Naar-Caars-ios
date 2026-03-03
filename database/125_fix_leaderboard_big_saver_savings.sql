-- Fix: big_saver savings calculation was using OR (requester + fulfiller)
-- Should only count rides the user FULFILLED (claimed_by), matching get_user_badges.
-- The deployed function uses xp_events table; this migration matches the live version.

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
    user_xp AS (
        SELECT
            xe.user_id,
            SUM(xe.amount)::BIGINT AS event_xp
        FROM public.xp_events xe
        WHERE xe.created_at::date BETWEEN start_date AND end_date
        GROUP BY xe.user_id
    ),
    fulfilled_weeks AS (
        SELECT DISTINCT
            xe.user_id AS uid,
            DATE_TRUNC('week', xe.created_at)::DATE AS week_start
        FROM public.xp_events xe
        WHERE xe.source_type IN ('ride_fulfilled', 'favor_fulfilled')
          AND xe.created_at::date BETWEEN start_date AND end_date
    ),
    week_numbered AS (
        SELECT uid, week_start,
            ROW_NUMBER() OVER (PARTITION BY uid ORDER BY week_start) AS rn
        FROM fulfilled_weeks
    ),
    streaks AS (
        SELECT uid, COUNT(*)::BIGINT AS streak_len
        FROM week_numbered
        GROUP BY uid, (week_start - (rn * INTERVAL '7 days'))
    ),
    longest_streaks AS (
        SELECT uid, MAX(streak_len)::BIGINT AS longest_streak
        FROM streaks GROUP BY uid
    ),
    user_stats AS (
        SELECT
            ux.user_id,
            ux.event_xp,
            COALESCE(ls.longest_streak, 0) AS streak_wks,
            (SELECT COUNT(*) FROM public.xp_events x2
             WHERE x2.user_id = ux.user_id
               AND x2.source_type IN ('ride_fulfilled', 'favor_fulfilled')
               AND x2.created_at::date BETWEEN start_date AND end_date)::BIGINT AS fulfilled_total,
            (SELECT COUNT(*) FROM public.xp_events x3
             WHERE x3.user_id = ux.user_id
               AND x3.source_type IN ('ride_requested', 'favor_requested')
               AND x3.created_at::date BETWEEN start_date AND end_date)::BIGINT AS made_total,
            (SELECT COUNT(*) FROM public.xp_events x4
             WHERE x4.user_id = ux.user_id AND x4.source_type = 'ride_fulfilled'
               AND x4.created_at::date BETWEEN start_date AND end_date)::BIGINT AS rides_fulfilled_cnt,
            (SELECT COUNT(*) FROM public.xp_events x5
             WHERE x5.user_id = ux.user_id AND x5.source_type = 'favor_fulfilled'
               AND x5.created_at::date BETWEEN start_date AND end_date)::BIGINT AS favors_fulfilled_cnt,
            (SELECT COUNT(*) FROM public.xp_events x6
             WHERE x6.user_id = ux.user_id AND x6.source_type = 'review_received' AND x6.amount = 5
               AND x6.created_at::date BETWEEN start_date AND end_date)::BIGINT AS five_star_cnt,
            -- FIX: Only count savings from rides the user FULFILLED (claimed_by), not requested
            COALESCE((SELECT SUM(r.estimated_cost)
             FROM public.rides r
             WHERE r.claimed_by = ux.user_id
               AND r.status = 'completed'), 0) AS savings
        FROM user_xp ux
        LEFT JOIN longest_streaks ls ON ls.uid = ux.user_id
    )
    SELECT
        p.id AS user_id,
        p.name AS name,
        p.avatar_url AS avatar_url,
        (us.event_xp + us.streak_wks * 5)::BIGINT AS xp,
        (
            SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb)
            FROM (
                SELECT 'road_warrior' AS badge WHERE us.rides_fulfilled_cnt >= 10
                UNION ALL
                SELECT 'good_neighbor' WHERE us.favors_fulfilled_cnt >= 10
                UNION ALL
                SELECT 'streak_champion' WHERE us.streak_wks >= 3
                UNION ALL
                SELECT 'five_star' WHERE us.five_star_cnt >= 10
                UNION ALL
                SELECT 'big_saver' WHERE us.savings >= 250
            ) b
        ) AS badges,
        us.streak_wks::BIGINT AS streak_weeks,
        us.fulfilled_total::BIGINT AS requests_fulfilled,
        us.made_total::BIGINT AS requests_made
    FROM user_stats us
    JOIN profiles p ON p.id = us.user_id
    WHERE p.approved = true
      AND (us.event_xp + us.streak_wks * 5) > 0
    ORDER BY (us.event_xp + us.streak_wks * 5) DESC
    LIMIT 100;
END;
$$;

GRANT EXECUTE ON FUNCTION get_xp_leaderboard(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_xp_leaderboard(DATE, DATE) TO anon;
