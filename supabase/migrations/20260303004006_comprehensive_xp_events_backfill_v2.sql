-- 20260303004006_comprehensive_xp_events_backfill_v2.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Step 1: Drop existing triggers
DROP TRIGGER IF EXISTS trg_rides_xp_on_completion ON public.rides;
DROP TRIGGER IF EXISTS trg_favors_xp_on_completion ON public.favors;

-- Step 2: Clear partial backfill data FIRST (before constraint change)
TRUNCATE public.xp_events;

-- Step 3: Update CHECK constraint to allow all source types
ALTER TABLE public.xp_events DROP CONSTRAINT IF EXISTS xp_events_source_type_check;
ALTER TABLE public.xp_events ADD CONSTRAINT xp_events_source_type_check
    CHECK (source_type IN ('ride_fulfilled', 'favor_fulfilled', 'ride_requested', 'favor_requested', 'first_ride', 'first_favor', 'review_received'));

-- Step 4: Backfill ride_fulfilled (5 + floor(estimated_cost / 5) savings bonus)
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    r.claimed_by,
    (5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::INTEGER,
    'ride_fulfilled',
    r.id,
    COALESCE(r.pickup || ' → ' || r.destination, 'Ride'),
    COALESCE(r.updated_at, r.created_at)
FROM public.rides r
WHERE r.status = 'completed' AND r.claimed_by IS NOT NULL
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Step 5: Backfill favor_fulfilled (10 XP each)
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    f.claimed_by,
    10,
    'favor_fulfilled',
    f.id,
    COALESCE(f.title, 'Favor'),
    COALESCE(f.updated_at, f.created_at)
FROM public.favors f
WHERE f.status = 'completed' AND f.claimed_by IS NOT NULL
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Step 6: Backfill ride_requested (5 XP each)
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    r.user_id,
    5,
    'ride_requested',
    r.id,
    'Requested: ' || COALESCE(r.pickup || ' → ' || r.destination, 'Ride'),
    r.created_at
FROM public.rides r
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Step 7: Backfill favor_requested (5 XP each)
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    f.user_id,
    5,
    'favor_requested',
    f.id,
    'Requested: ' || COALESCE(f.title, 'Favor'),
    f.created_at
FROM public.favors f
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Step 8: Backfill first_ride milestone (10 XP)
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    sub.user_id,
    10,
    'first_ride',
    sub.id,
    'First ride milestone',
    sub.created_at
FROM (
    SELECT r.user_id, r.id, r.created_at,
           ROW_NUMBER() OVER (PARTITION BY r.user_id ORDER BY r.created_at) AS rn
    FROM public.rides r
) sub
WHERE sub.rn = 1
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Step 9: Backfill first_favor milestone (10 XP)
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    sub.user_id,
    10,
    'first_favor',
    sub.id,
    'First favor milestone',
    sub.created_at
FROM (
    SELECT f.user_id, f.id, f.created_at,
           ROW_NUMBER() OVER (PARTITION BY f.user_id ORDER BY f.created_at) AS rn
    FROM public.favors f
) sub
WHERE sub.rn = 1
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Step 10: Backfill review_received (5 for 5-star, 2 for 4-star)
INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
SELECT
    rv.fulfiller_id,
    CASE WHEN rv.rating = 5 THEN 5 WHEN rv.rating = 4 THEN 2 ELSE 0 END,
    'review_received',
    rv.id,
    CASE WHEN rv.rating = 5 THEN '5-star review' WHEN rv.rating = 4 THEN '4-star review' ELSE 'Review received' END,
    rv.created_at
FROM public.reviews rv
WHERE rv.rating >= 4
ON CONFLICT (source_type, source_id) DO NOTHING;

-- Step 11: Comprehensive trigger for ride/favor completion
CREATE OR REPLACE FUNCTION public.record_xp_on_completion()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.claimed_by IS NOT NULL THEN
        IF TG_TABLE_NAME = 'rides' THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
            VALUES (
                NEW.claimed_by,
                (5 + COALESCE(FLOOR(NEW.estimated_cost / 5), 0))::INTEGER,
                'ride_fulfilled',
                NEW.id,
                COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride'),
                COALESCE(NEW.updated_at, now())
            )
            ON CONFLICT (source_type, source_id) DO NOTHING;
        ELSE
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
            VALUES (
                NEW.claimed_by,
                10,
                'favor_fulfilled',
                NEW.id,
                COALESCE(NEW.title, 'Favor'),
                COALESCE(NEW.updated_at, now())
            )
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 12: Trigger for request creation + first milestone
CREATE OR REPLACE FUNCTION public.record_xp_on_request_created()
RETURNS TRIGGER AS $$
DECLARE
    v_is_first BOOLEAN;
BEGIN
    IF TG_TABLE_NAME = 'rides' THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
        VALUES (
            NEW.user_id, 5, 'ride_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride'),
            NEW.created_at
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.rides WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
            VALUES (NEW.user_id, 10, 'first_ride', NEW.id, 'First ride milestone', NEW.created_at)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    ELSE
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
        VALUES (
            NEW.user_id, 5, 'favor_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.title, 'Favor'),
            NEW.created_at
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.favors WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
            VALUES (NEW.user_id, 10, 'first_favor', NEW.id, 'First favor milestone', NEW.created_at)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 13: Trigger for review XP
CREATE OR REPLACE FUNCTION public.record_xp_on_review()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.rating >= 4 THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
        VALUES (
            NEW.fulfiller_id,
            CASE WHEN NEW.rating = 5 THEN 5 ELSE 2 END,
            'review_received',
            NEW.id,
            CASE WHEN NEW.rating = 5 THEN '5-star review' ELSE '4-star review' END,
            NEW.created_at
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 14: Attach all triggers
CREATE TRIGGER trg_rides_xp_on_completion
    AFTER UPDATE ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_completion();

CREATE TRIGGER trg_favors_xp_on_completion
    AFTER UPDATE ON public.favors
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_completion();

CREATE TRIGGER trg_rides_xp_on_create
    AFTER INSERT ON public.rides
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_request_created();

CREATE TRIGGER trg_favors_xp_on_create
    AFTER INSERT ON public.favors
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_request_created();

CREATE TRIGGER trg_reviews_xp
    AFTER INSERT ON public.reviews
    FOR EACH ROW
    EXECUTE FUNCTION public.record_xp_on_review();
