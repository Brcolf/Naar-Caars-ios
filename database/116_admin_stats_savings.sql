-- Migration: Admin stats savings breakdown by period
-- Returns estimated_cost sums grouped by week/month/year

CREATE OR REPLACE FUNCTION admin_stats_savings(
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
                date_trunc(v_trunc, r.created_at)::DATE AS period_start,
                COALESCE(SUM(r.estimated_cost), 0)::NUMERIC(12,2) AS total_savings,
                COUNT(*)::BIGINT AS ride_count
            FROM rides r
            WHERE r.estimated_cost IS NOT NULL
            GROUP BY date_trunc(v_trunc, r.created_at)
            ORDER BY period_start DESC
            LIMIT p_count
        ) t
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION admin_stats_savings(TEXT, INT) TO authenticated;
