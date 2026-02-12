-- Migration: Fix RLS policies to allow claiming and unclaiming rides and favors
--
-- Problem: The existing UPDATE policies on rides and favors require
--   auth.uid() = user_id OR auth.uid() = claimed_by
-- When a claimer tries to claim an open request (claimed_by IS NULL),
-- neither condition is satisfied, so the UPDATE silently returns 0 rows.
-- Similarly, unclaim fails because the WITH CHECK requires claimed_by = auth.uid()
-- but after update claimed_by becomes NULL.
--
-- Fix: Add dedicated claim and unclaim policies for both tables.

-- ============================================================
-- RIDES
-- ============================================================

-- Allow any authenticated user to claim an open, unclaimed ride
-- (as long as they are not the poster)
DROP POLICY IF EXISTS "Authenticated users can claim open rides" ON public.rides;
CREATE POLICY "Authenticated users can claim open rides"
ON public.rides FOR UPDATE
USING (claimed_by IS NULL AND status = 'open' AND user_id != auth.uid())
WITH CHECK (claimed_by = auth.uid() AND status = 'confirmed');

-- Allow the current claimer to unclaim (reset to open)
DROP POLICY IF EXISTS "Claimers can unclaim rides" ON public.rides;
CREATE POLICY "Claimers can unclaim rides"
ON public.rides FOR UPDATE
USING (claimed_by = auth.uid() AND status = 'confirmed')
WITH CHECK (claimed_by IS NULL AND status = 'open');

-- ============================================================
-- FAVORS
-- ============================================================

-- Allow any authenticated user to claim an open, unclaimed favor
-- (as long as they are not the poster)
DROP POLICY IF EXISTS "Authenticated users can claim open favors" ON public.favors;
CREATE POLICY "Authenticated users can claim open favors"
ON public.favors FOR UPDATE
USING (claimed_by IS NULL AND status = 'open' AND user_id != auth.uid())
WITH CHECK (claimed_by = auth.uid() AND status = 'confirmed');

-- Allow the current claimer to unclaim (reset to open)
DROP POLICY IF EXISTS "Claimers can unclaim favors" ON public.favors;
CREATE POLICY "Claimers can unclaim favors"
ON public.favors FOR UPDATE
USING (claimed_by = auth.uid() AND status = 'confirmed')
WITH CHECK (claimed_by IS NULL AND status = 'open');
