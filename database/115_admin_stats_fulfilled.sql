-- Migration: Admin stats fulfilled breakdown by period
-- Returns completed request counts grouped by week/month/year

CREATE OR REPLACE FUNCTION admin_stats_fulfilled(
    p_period TEXT DEFAULT 'month',
    p_count INT DEFAULT 12
)
RETURNS JSON AS $$
DECLARE
    v_trunc TEXT;
BEGIN
    -- Verify caller is admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: admin access required';
    END IF;

    -- Map period to date_trunc argument
    v_trunc := CASE p_period
        WHEN 'week' THEN 'week'
        WHEN 'month' THEN 'month'
        WHEN 'year' THEN 'year'
        ELSE 'month'
    END;

    RETURN (
        SELECT COALESCE(json_agg(row_to_json(t)), '[]'::JSON)
        FROM (
            SELECT
                period_start,
                SUM(ride_count)::BIGINT AS ride_count,
                SUM(favor_count)::BIGINT AS favor_count,
                SUM(ride_count + favor_count)::BIGINT AS total_count
            FROM (
                -- Completed rides
                SELECT
                    date_trunc(v_trunc, r.updated_at)::DATE AS period_start,
                    COUNT(*) AS ride_count,
                    0 AS favor_count
                FROM rides r
                WHERE r.status = 'completed'
                GROUP BY date_trunc(v_trunc, r.updated_at)

                UNION ALL

                -- Completed favors
                SELECT
                    date_trunc(v_trunc, f.updated_at)::DATE AS period_start,
                    0 AS ride_count,
                    COUNT(*) AS favor_count
                FROM favors f
                WHERE f.status = 'completed'
                GROUP BY date_trunc(v_trunc, f.updated_at)
            ) combined
            GROUP BY period_start
            ORDER BY period_start DESC
            LIMIT p_count
        ) t
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION admin_stats_fulfilled(TEXT, INT) TO authenticated;
