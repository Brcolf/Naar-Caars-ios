-- Drop the get_badge_counts(uuid, boolean) overload from migration 107 so only
-- get_badge_counts(boolean, uuid) remains (from 20260216_0001). Avoids ambiguous
-- RPC when the app calls with only p_include_details.

drop function if exists public.get_badge_counts(uuid, boolean);
