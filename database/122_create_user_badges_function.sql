-- Migration: Create get_user_badges RPC for single-user badge lookup
-- Used by profile pages to compute all-time badge achievements for a user.

-- Drop first for signature safety
DROP FUNCTION IF EXISTS get_user_badges(UUID);

CREATE OR REPLACE FUNCTION get_user_badges(target_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rides_fulfilled   BIGINT;
    v_favors_fulfilled  BIGINT;
    v_five_star_count   BIGINT;
    v_total_savings     NUMERIC;
    v_longest_streak    BIGINT;
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
    ) b;

    RETURN v_badges;
END;
$$;

-- Grant to authenticated only (requires user context, not anon)
GRANT EXECUTE ON FUNCTION get_user_badges(UUID) TO authenticated;
