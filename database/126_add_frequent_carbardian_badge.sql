-- Migration 126: Add frequent_carbardian badge to get_user_badges and get_xp_leaderboard
-- Badge is awarded when a user has created 10+ total requests (rides + favors)

-------------------------------------------------------
-- 1. get_user_badges  –  add frequent_carbardian badge
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_badges(target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_rides_fulfilled   BIGINT;
    v_favors_fulfilled  BIGINT;
    v_five_star_count   BIGINT;
    v_total_savings     NUMERIC;
    v_longest_streak    BIGINT;
    v_requests_made     BIGINT;
    v_badges            JSONB := '[]'::jsonb;
BEGIN
    -- 1. Road warrior: completed rides fulfilled (all-time)
    SELECT COUNT(*)
    INTO v_rides_fulfilled
    FROM rides
    WHERE claimed_by = target_user_id
      AND status = 'completed';

    -- 2. Good neighbor: completed favors fulfilled (all-time)
    SELECT COUNT(*)
    INTO v_favors_fulfilled
    FROM favors
    WHERE claimed_by = target_user_id
      AND status = 'completed';

    -- 3. Five star: 5-star reviews received (all-time)
    SELECT COUNT(*)
    INTO v_five_star_count
    FROM reviews
    WHERE fulfiller_id = target_user_id
      AND rating = 5;

    -- 4. Big saver: total estimated_cost savings from fulfilled rides (all-time)
    SELECT COALESCE(SUM(estimated_cost), 0)
    INTO v_total_savings
    FROM rides
    WHERE claimed_by = target_user_id
      AND status = 'completed';

    -- 5. Streak champion: longest consecutive-week streak (gaps-and-islands)
    --    Using DATE_TRUNC('week', updated_at)::DATE for correct year-boundary handling
    WITH fulfilled_weeks AS (
        SELECT DISTINCT DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM rides
        WHERE claimed_by = target_user_id
          AND status = 'completed'

        UNION

        SELECT DISTINCT DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM favors
        WHERE claimed_by = target_user_id
          AND status = 'completed'
    ),
    week_numbered AS (
        SELECT
            week_start,
            ROW_NUMBER() OVER (ORDER BY week_start) AS rn
        FROM fulfilled_weeks
    ),
    streaks AS (
        SELECT COUNT(*)::BIGINT AS streak_len
        FROM week_numbered
        GROUP BY (week_start - (rn * INTERVAL '7 days'))
    )
    SELECT COALESCE(MAX(streak_len), 0)
    INTO v_longest_streak
    FROM streaks;

    -- 6. Frequent Carbardian: total requests made (rides + favors, all-time)
    SELECT COUNT(*) INTO v_requests_made
    FROM (
        SELECT id FROM rides  WHERE user_id = target_user_id
        UNION ALL
        SELECT id FROM favors WHERE user_id = target_user_id
    ) sub;

    -- Assemble badge array
    SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb)
    INTO v_badges
    FROM (
        SELECT 'road_warrior'    AS badge WHERE v_rides_fulfilled  >= 10
        UNION ALL
        SELECT 'good_neighbor'   AS badge WHERE v_favors_fulfilled >= 10
        UNION ALL
        SELECT 'streak_champion' AS badge WHERE v_longest_streak   >= 3
        UNION ALL
        SELECT 'five_star'       AS badge WHERE v_five_star_count  >= 10
        UNION ALL
        SELECT 'big_saver'       AS badge WHERE v_total_savings    >= 250
        UNION ALL
        SELECT 'frequent_carbardian' AS badge WHERE v_requests_made >= 10
    ) b;

    RETURN v_badges;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_user_badges(uuid) TO anon, authenticated, service_role;

-------------------------------------------------------
-- 2. get_xp_leaderboard  –  add frequent_carbardian badge
-------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_xp_leaderboard(start_date date DEFAULT '1970-01-01'::date, end_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(user_id uuid, name text, avatar_url text, xp bigint, badges jsonb, streak_weeks bigint, requests_fulfilled bigint, requests_made bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            (SELECT COUNT(*) FROM public.xp_events x7
             WHERE x7.user_id = ux.user_id
               AND x7.source_type IN ('ride_requested', 'favor_requested')
               AND x7.created_at::date BETWEEN start_date AND end_date)::BIGINT AS requests_made_cnt,
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
                UNION ALL
                SELECT 'frequent_carbardian' WHERE us.requests_made_cnt >= 10
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
$function$;

GRANT EXECUTE ON FUNCTION public.get_xp_leaderboard(date, date) TO anon, authenticated, service_role;
