-- ============================================================================
-- 059_create_participants_tables.sql
-- ============================================================================
-- 
-- Creates ride_participants and favor_participants tables for co-requestors
--
-- Schema matches PRD requirements:
-- - ride_participants: Stores participants (co-requestors) for ride requests
-- - favor_participants: Stores participants (co-requestors) for favor requests
--
-- RLS policies allow:
-- - SELECT: All approved users
-- - INSERT: Ride/favor owner
-- - DELETE: Ride/favor owner
-- ============================================================================

-- ============================================================================
-- Create ride_participants table
-- ============================================================================

-- Drop table if it exists (to handle schema changes)
DROP TABLE IF EXISTS public.ride_participants CASCADE;

CREATE TABLE public.ride_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    added_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Prevent duplicate participants for the same ride
    UNIQUE(ride_id, user_id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_ride_participants_ride_id ON public.ride_participants(ride_id);
CREATE INDEX IF NOT EXISTS idx_ride_participants_user_id ON public.ride_participants(user_id);

-- ============================================================================
-- Create favor_participants table
-- ============================================================================

-- Drop table if it exists (to handle schema changes)
DROP TABLE IF EXISTS public.favor_participants CASCADE;

CREATE TABLE public.favor_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    favor_id UUID NOT NULL REFERENCES public.favors(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    added_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Prevent duplicate participants for the same favor
    UNIQUE(favor_id, user_id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_favor_participants_favor_id ON public.favor_participants(favor_id);
CREATE INDEX IF NOT EXISTS idx_favor_participants_user_id ON public.favor_participants(user_id);

-- ============================================================================
-- Enable Row Level Security
-- ============================================================================

ALTER TABLE public.ride_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favor_participants ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS Policies for ride_participants
-- ============================================================================

-- SELECT: All approved users can see participants
CREATE POLICY ride_participants_select
ON public.ride_participants
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND approved = true
    )
);

-- INSERT: Ride owner can add participants
CREATE POLICY ride_participants_insert
ON public.ride_participants
FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.rides
        WHERE id = ride_id AND user_id = auth.uid()
    )
    AND added_by = auth.uid()
);

-- DELETE: Ride owner can remove participants
CREATE POLICY ride_participants_delete
ON public.ride_participants
FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM public.rides
        WHERE id = ride_id AND user_id = auth.uid()
    )
);

-- ============================================================================
-- RLS Policies for favor_participants
-- ============================================================================

-- SELECT: All approved users can see participants
CREATE POLICY favor_participants_select
ON public.favor_participants
FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND approved = true
    )
);

-- INSERT: Favor owner can add participants
CREATE POLICY favor_participants_insert
ON public.favor_participants
FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.favors
        WHERE id = favor_id AND user_id = auth.uid()
    )
    AND added_by = auth.uid()
);

-- DELETE: Favor owner can remove participants
CREATE POLICY favor_participants_delete
ON public.favor_participants
FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM public.favors
        WHERE id = favor_id AND user_id = auth.uid()
    )
);

