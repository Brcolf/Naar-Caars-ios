-- Migration: Admin dashboard summary stats RPC
-- Returns top-level card values for the admin panel

CREATE OR REPLACE FUNCTION admin_dashboard_stats()
RETURNS JSON AS $$
DECLARE
    v_fulfilled BIGINT;
    v_savings NUMERIC(12,2);
    v_active BIGINT;
BEGIN
    -- Verify caller is admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: admin access required';
    END IF;

    -- Count completed rides + favors
    SELECT COALESCE(
        (SELECT COUNT(*) FROM rides WHERE status = 'completed'),
        0
    ) + COALESCE(
        (SELECT COUNT(*) FROM favors WHERE status = 'completed'),
        0
    ) INTO v_fulfilled;

    -- Sum estimated_cost from all rides that have a value
    SELECT COALESCE(SUM(estimated_cost), 0)
    INTO v_savings
    FROM rides
    WHERE estimated_cost IS NOT NULL;

    -- Count unfinished rides (open + pending + confirmed)
    SELECT COUNT(*)
    INTO v_active
    FROM rides
    WHERE status IN ('open', 'pending', 'confirmed');

    RETURN json_build_object(
        'fulfilled_count', v_fulfilled,
        'total_savings', v_savings,
        'active_rides_count', v_active
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION admin_dashboard_stats() TO authenticated;
