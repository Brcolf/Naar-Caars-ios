-- 20260303002526_create_user_savings_and_xp_rpcs.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- RPC: Get user savings breakdown by period
CREATE OR REPLACE FUNCTION public.get_user_savings(p_period TEXT DEFAULT 'all')
RETURNS TABLE (
    period_label TEXT,
    total_savings DOUBLE PRECISION,
    ride_count BIGINT
) AS $$
BEGIN
    IF p_period = 'month' THEN
        RETURN QUERY
        SELECT
            to_char(date_trunc('month', r.date), 'Mon YYYY') AS period_label,
            COALESCE(SUM(r.estimated_cost), 0)::DOUBLE PRECISION AS total_savings,
            COUNT(*)::BIGINT AS ride_count
        FROM public.rides r
        WHERE (r.user_id = auth.uid() OR r.claimed_by = auth.uid())
          AND r.status IN ('confirmed', 'completed')
          AND r.estimated_cost IS NOT NULL
        GROUP BY date_trunc('month', r.date)
        ORDER BY date_trunc('month', r.date) DESC;
    ELSIF p_period = 'year' THEN
        RETURN QUERY
        SELECT
            to_char(date_trunc('year', r.date), 'YYYY') AS period_label,
            COALESCE(SUM(r.estimated_cost), 0)::DOUBLE PRECISION AS total_savings,
            COUNT(*)::BIGINT AS ride_count
        FROM public.rides r
        WHERE (r.user_id = auth.uid() OR r.claimed_by = auth.uid())
          AND r.status IN ('confirmed', 'completed')
          AND r.estimated_cost IS NOT NULL
        GROUP BY date_trunc('year', r.date)
        ORDER BY date_trunc('year', r.date) DESC;
    ELSE
        -- 'all' - return single row with total
        RETURN QUERY
        SELECT
            'All Time'::TEXT AS period_label,
            COALESCE(SUM(r.estimated_cost), 0)::DOUBLE PRECISION AS total_savings,
            COUNT(*)::BIGINT AS ride_count
        FROM public.rides r
        WHERE (r.user_id = auth.uid() OR r.claimed_by = auth.uid())
          AND r.status IN ('confirmed', 'completed')
          AND r.estimated_cost IS NOT NULL;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC: Get user XP events (for history sheet)
CREATE OR REPLACE FUNCTION public.get_user_xp_events()
RETURNS TABLE (
    id UUID,
    amount INTEGER,
    source_type TEXT,
    source_id UUID,
    description TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        xe.id,
        xe.amount,
        xe.source_type,
        xe.source_id,
        xe.description,
        xe.created_at
    FROM public.xp_events xe
    WHERE xe.user_id = auth.uid()
    ORDER BY xe.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC: Get user total XP (for stat display)
CREATE OR REPLACE FUNCTION public.get_user_total_xp()
RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(
        (SELECT SUM(xe.amount)::INTEGER FROM public.xp_events xe WHERE xe.user_id = auth.uid()),
        0
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC: Get user total savings (for stat display)
CREATE OR REPLACE FUNCTION public.get_user_total_savings()
RETURNS DOUBLE PRECISION AS $$
BEGIN
    RETURN COALESCE(
        (SELECT SUM(r.estimated_cost)
         FROM public.rides r
         WHERE (r.user_id = auth.uid() OR r.claimed_by = auth.uid())
           AND r.status IN ('confirmed', 'completed')
           AND r.estimated_cost IS NOT NULL),
        0
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
