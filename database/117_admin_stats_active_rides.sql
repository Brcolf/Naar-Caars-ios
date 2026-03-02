-- Migration: Admin stats active (unfinished) rides
-- Returns all rides with status open/pending/confirmed with poster/claimer names

CREATE OR REPLACE FUNCTION admin_stats_active_rides()
RETURNS JSON AS $$
BEGIN
    -- Verify caller is admin
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
                r.pickup,
                r.destination,
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
            ORDER BY r.date ASC, r.time ASC
        ) t
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION admin_stats_active_rides() TO authenticated;
