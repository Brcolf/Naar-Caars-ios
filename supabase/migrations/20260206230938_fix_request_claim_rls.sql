-- 20260206230938_fix_request_claim_rls.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Fix RLS policies to allow claiming and unclaiming rides and favors

-- RIDES: Allow any authenticated user to claim an open, unclaimed ride (not the poster)
DROP POLICY IF EXISTS "Authenticated users can claim open rides" ON public.rides;
CREATE POLICY "Authenticated users can claim open rides"
ON public.rides FOR UPDATE
USING (claimed_by IS NULL AND status = 'open' AND user_id != auth.uid())
WITH CHECK (claimed_by = auth.uid() AND status = 'confirmed');

-- RIDES: Allow the current claimer to unclaim (reset to open)
DROP POLICY IF EXISTS "Claimers can unclaim rides" ON public.rides;
CREATE POLICY "Claimers can unclaim rides"
ON public.rides FOR UPDATE
USING (claimed_by = auth.uid() AND status = 'confirmed')
WITH CHECK (claimed_by IS NULL AND status = 'open');

-- FAVORS: Allow any authenticated user to claim an open, unclaimed favor (not the poster)
DROP POLICY IF EXISTS "Authenticated users can claim open favors" ON public.favors;
CREATE POLICY "Authenticated users can claim open favors"
ON public.favors FOR UPDATE
USING (claimed_by IS NULL AND status = 'open' AND user_id != auth.uid())
WITH CHECK (claimed_by = auth.uid() AND status = 'confirmed');

-- FAVORS: Allow the current claimer to unclaim (reset to open)
DROP POLICY IF EXISTS "Claimers can unclaim favors" ON public.favors;
CREATE POLICY "Claimers can unclaim favors"
ON public.favors FOR UPDATE
USING (claimed_by = auth.uid() AND status = 'confirmed')
WITH CHECK (claimed_by IS NULL AND status = 'open');