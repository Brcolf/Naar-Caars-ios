-- 20261019_0050_geocoding_multiplier_lookup.sql
--
-- NOT APPLIED. Phase 5a of the multi-community design (Docs/superpowers/specs/2026-10-07-multi-community-design.md
-- §4 "Phase 5", D16), under amendment A5 of Docs/superpowers/specs/2026-10-17-multi-community-decisions.md
-- ("add a definer geocoding lookup and move the client to it"; the SELECT revoke is 5b, 20261019_0062).
--
-- What it does.
--   * get_geocoding_multiplier(p_location_key) -> numeric: the multiplier of a cached place, only for an
--     active account (is_active_user, caller-bound), only for a well-formed key (the client's 3-decimal
--     "lat_lon", RideCostEstimator.cacheKey), only when the row was written in the last 24 hours (updated_at,
--     falling back to created_at). Null otherwise. No other column is ever returned.
--   * put_geocoding_multiplier(p_location_key, p_latitude, p_longitude, p_multiplier) -> boolean: the client's
--     write after an on-device reverse geocode. Active accounts only; the key must be well formed and match
--     the coordinates to 3 decimals; the multiplier must lie in the range the client computes (0.9-1.5,
--     GeocodingCacheService.placemarkMultiplier). Upsert on location_key, placemark_data always null,
--     updated_at = now(). Answers false on any refusal (the client treats the cache as best effort).
--   * Block 3 (optional, D-S8): clears the placemark data written so far. No reader exists. A ONE-TIME
--     clean-up: the installed build and Phase 1-4 builds keep upserting placemark_data directly
--     (main:NaarsCars/Core/Utilities/GeocodingCacheService.swift:152) until 20261019_0062 closes the table,
--     which repeats the clear (its block 2).
--
-- What old clients see. Nothing. The installed build and the Phase 1-4 builds keep reading
-- select("multiplier") and upserting the table directly; this file changes no policy and no grant on it.
-- A row such a build refreshes keeps its old updated_at (PostgREST updates only the columns sent), so the
-- 5a client treats it as expired until it writes the key itself. Harmless: the multiplier is recomputed.
--
-- Apply. Supabase MCP apply_migration, one block per call, in order. Nothing here is declined.
-- Verification. Dry run: blocks 1-3 in one begin; ... rollback; with the probe PARAMETERS, the HELPERS without
-- their commit;, and the probe blocks geocoding_lookup and short with begin;/rollback; turned into savepoints
-- (the plan's runbook step 2; the same assembly as the 5b dry-run scripts). Then short after each block and
-- geocoding_lookup at the end.
-- Outcomes: not yet run.
--
-- Rollback. drop function public.put_geocoding_multiplier(text, numeric, numeric, numeric);
-- drop function public.get_geocoding_multiplier(text); (the 5a client then finds no function, turns its
-- lookup off for the session and still estimates every ride). Block 3 cannot be undone; the multipliers are
-- untouched by it.


-- ============================================================================================
-- BLOCK 1: public.get_geocoding_multiplier(text)   (new)
-- ============================================================================================
create or replace function public.get_geocoding_multiplier(p_location_key text)
returns numeric
language sql
stable
security definer
set search_path = ''
as $function$
  select g.multiplier
    from public.geocoding_cache g
   where public.is_active_user((select auth.uid()))
     and p_location_key ~ '^-?[0-9]{1,3}\.[0-9]{3}_-?[0-9]{1,3}\.[0-9]{3}$'
     and g.location_key = p_location_key
     and coalesce(g.updated_at, g.created_at) >= now() - interval '24 hours'
   limit 1;
$function$;

revoke all on function public.get_geocoding_multiplier(text) from public, anon;
grant execute on function public.get_geocoding_multiplier(text) to authenticated;


-- ============================================================================================
-- BLOCK 2: public.put_geocoding_multiplier(text, numeric, numeric, numeric)   (new)
-- The checks are split so a malformed key never reaches the numeric casts (OR has no evaluation order).
-- ============================================================================================
create or replace function public.put_geocoding_multiplier(
    p_location_key text,
    p_latitude numeric,
    p_longitude numeric,
    p_multiplier numeric
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if not public.is_active_user((select auth.uid())) then
    return false;
  end if;
  if p_location_key is null
     or p_location_key !~ '^-?[0-9]{1,3}\.[0-9]{3}_-?[0-9]{1,3}\.[0-9]{3}$'
     or p_latitude is null or p_longitude is null or p_multiplier is null then
    return false;
  end if;
  if p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180
     or abs(split_part(p_location_key, '_', 1)::numeric - p_latitude) > 0.0005
     or abs(split_part(p_location_key, '_', 2)::numeric - p_longitude) > 0.0005
     or p_multiplier < 0.9 or p_multiplier > 1.5 then
    return false;
  end if;

  insert into public.geocoding_cache (latitude, longitude, location_key, multiplier, placemark_data, created_at, updated_at)
  values (p_latitude, p_longitude, p_location_key, p_multiplier, null, now(), now())
  on conflict (location_key) do update
     set latitude = excluded.latitude,
         longitude = excluded.longitude,
         multiplier = excluded.multiplier,
         placemark_data = null,
         updated_at = now();
  return true;
end
$function$;

revoke all on function public.put_geocoding_multiplier(text, numeric, numeric, numeric) from public, anon;
grant execute on function public.put_geocoding_multiplier(text, numeric, numeric, numeric) to authenticated;


-- ============================================================================================
-- BLOCK 3 (optional, D-S8): the placemarks written so far. Seven rows on 2026-10-19; no client or function
-- reads placemark_data. One-time: builds without the 5a client keep writing placemarks until 20261019_0062,
-- whose block 2 clears them again.
-- ============================================================================================
update public.geocoding_cache set placemark_data = null where placemark_data is not null;
