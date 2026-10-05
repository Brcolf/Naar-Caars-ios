-- 20260302173326_admin_stats_include_favors.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Update admin_dashboard_stats to count unfinished favors too
CREATE OR REPLACE FUNCTION admin_dashboard_stats()
RETURNS JSON AS $$
DECLARE
    v_fulfilled BIGINT;
    v_savings NUMERIC(12,2);
    v_active BIGINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: admin access required';
    END IF;

    SELECT COALESCE(
        (SELECT COUNT(*) FROM rides WHERE status = 'completed'),
        0
    ) + COALESCE(
        (SELECT COUNT(*) FROM favors WHERE status = 'completed'),
        0
    ) INTO v_fulfilled;

    SELECT COALESCE(SUM(estimated_cost), 0)
    INTO v_savings
    FROM rides
    WHERE estimated_cost IS NOT NULL;

    -- Count unfinished rides AND favors
    SELECT (
        SELECT COUNT(*) FROM rides WHERE status IN ('open', 'pending', 'confirmed')
    ) + (
        SELECT COUNT(*) FROM favors WHERE status IN ('open', 'pending', 'confirmed')
    ) INTO v_active;

    RETURN json_build_object(
        'fulfilled_count', v_fulfilled,
        'total_savings', v_savings,
        'active_rides_count', v_active
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Update admin_stats_active_rides to include favors
CREATE OR REPLACE FUNCTION admin_stats_active_rides()
RETURNS JSON AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: admin access required';
    END IF;

    RETURN (
        SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
        FROM (
            SELECT
                r.id,
                'ride' AS type,
                r.pickup AS title,
                r.destination AS subtitle,
                r.date,
                r.time,
                r.status,
                r.claimed_by,
                poster.name AS poster_name,
                claimer.name AS claimer_name
            FROM rides r
            LEFT JOIN profiles poster ON poster.id = r.user_id
            LEFT JOIN profiles claimer ON claimer.id = r.claimed_by
            WHERE r.status IN ('open', 'pending', 'confirmed')

            UNION ALL

            SELECT
                f.id,
                'favor' AS type,
                f.title AS title,
                f.location AS subtitle,
                f.date,
                f.time,
                f.status,
                f.claimed_by,
                poster.name AS poster_name,
                claimer.name AS claimer_name
            FROM favors f
            LEFT JOIN profiles poster ON poster.id = f.user_id
            LEFT JOIN profiles claimer ON claimer.id = f.claimed_by
            WHERE f.status IN ('open', 'pending', 'confirmed')

            ORDER BY date ASC, time ASC
        ) t
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;