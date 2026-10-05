-- 20260303002456_create_xp_events_table.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Create xp_events table
CREATE TABLE IF NOT EXISTS public.xp_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,
    source_type TEXT NOT NULL CHECK (source_type IN ('ride', 'favor')),
    source_id UUID NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_type, source_id)
);

-- Index for user lookups
CREATE INDEX idx_xp_events_user_id ON public.xp_events(user_id);
CREATE INDEX idx_xp_events_created_at ON public.xp_events(created_at);

-- RLS: users can only read their own XP events
ALTER TABLE public.xp_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own xp_events"
    ON public.xp_events FOR SELECT
    USING (auth.uid() = user_id);

-- Trigger function: insert XP event when ride/favor completes
CREATE OR REPLACE FUNCTION public.record_xp_on_completion()
RETURNS TRIGGER AS $$
BEGIN
    -- Only fire when status changes to 'completed' and there's a claimer
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.claimed_by IS NOT NULL THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
        VALUES (
            NEW.claimed_by,
            CASE TG_TABLE_NAME
                WHEN 'rides' THEN 5
                WHEN 'favors' THEN 10
            END,
            CASE TG_TABLE_NAME
                WHEN 'rides' THEN 'ride'
                WHEN 'favors' THEN 'favor'
            END,
            NEW.id,
            CASE TG_TABLE_NAME
                WHEN 'rides' THEN COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride')
                WHEN 'favors' THEN COALESCE(NEW.title, 'Favor')
            END,
            COALESCE(NEW.updated_at, now())
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach triggers to rides and favors tables
CREATE TRIGGER trg_rides_xp_on_completion
    AFTER UPDATE ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_completion();

CREATE TRIGGER trg_favors_xp_on_completion
    AFTER UPDATE ON public.favors
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_completion();

-- Backfill: insert XP events for all existing completed rides
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    r.claimed_by,
    5,
    'ride',
    r.id,
    COALESCE(r.pickup || ' → ' || r.destination, 'Ride'),
    COALESCE(r.updated_at, r.created_at)
FROM public.rides r
WHERE r.status = 'completed' AND r.claimed_by IS NOT NULL
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Backfill: insert XP events for all existing completed favors
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    f.claimed_by,
    10,
    'favor',
    f.id,
    COALESCE(f.title, 'Favor'),
    COALESCE(f.updated_at, f.created_at)
FROM public.favors f
WHERE f.status = 'completed' AND f.claimed_by IS NOT NULL
ON CONFLICT (source_type, source_id) DO NOTHING;
