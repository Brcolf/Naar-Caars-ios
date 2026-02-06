-- Fix: Add SECURITY DEFINER to get_badge_counts RPC
-- The function performs cleanup operations that need elevated permissions

ALTER FUNCTION public.get_badge_counts(BOOLEAN, UUID) SECURITY DEFINER;
