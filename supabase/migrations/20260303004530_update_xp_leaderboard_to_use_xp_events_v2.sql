-- 20260303004530_update_xp_leaderboard_to_use_xp_events_v2.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Drop existing function first (return type changed)
DROP FUNCTION IF EXISTS public.get_xp_leaderboard(DATE, DATE);

-- Recreate using xp_events + computed streak bonus
CREATE FUNCTION public.get_xp_leaderboard(start_date DATE, end_date DATE)
RETURNS TABLE (
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
            COALESCE((SELECT SUM(r.estimated_cost)
             FROM public.rides r
             WHERE (r.user_id = ux.user_id OR r.claimed_by = ux.user_id)
               AND r.status IN ('confirmed', 'completed')), 0) AS savings
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
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Also update get_user_total_xp to include streak bonus
CREATE OR REPLACE FUNCTION public.get_user_total_xp()
RETURNS INTEGER AS $$
DECLARE
    v_event_xp INTEGER;
    v_streak_bonus INTEGER;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO v_event_xp
    FROM public.xp_events WHERE user_id = auth.uid();

    WITH fulfilled_weeks AS (
        SELECT DISTINCT DATE_TRUNC('week', created_at)::DATE AS week_start
        FROM public.xp_events
        WHERE user_id = auth.uid()
          AND source_type IN ('ride_fulfilled', 'favor_fulfilled')
    ),
    week_numbered AS (
        SELECT week_start, ROW_NUMBER() OVER (ORDER BY week_start) AS rn
        FROM fulfilled_weeks
    ),
    streaks AS (
        SELECT COUNT(*)::INTEGER AS streak_len
        FROM week_numbered
        GROUP BY (week_start - (rn * INTERVAL '7 days'))
    )
    SELECT COALESCE(MAX(streak_len), 0) * 5 INTO v_streak_bonus FROM streaks;

    RETURN v_event_xp + v_streak_bonus;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
