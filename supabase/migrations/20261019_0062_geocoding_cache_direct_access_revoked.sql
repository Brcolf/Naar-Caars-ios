-- 20261019_0062_geocoding_cache_direct_access_revoked.sql
--
-- NOT APPLIED. GATED: apply only after the owner confirms from App Store Connect that no pre-community build
-- remains in use (A5 point 2) AND that every build in use contains the Phase 5a client (its ride-cost lookup
-- calls get_geocoding_multiplier / put_geocoding_multiplier, 20261019_0050). Phase 5b (§4 "Phase 5":
-- geocoding_cache read through a definer lookup, direct SELECT revoked; D16).
--
-- What it does. Block 1 revokes every table privilege on public.geocoding_cache from anon and authenticated (SELECT,
-- and also INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER: the 5a client writes through
-- put_geocoding_multiplier, and an upsert without SELECT fails anyway; D-S6). The three policies stay and are
-- inert without the grants (removing them is a DROP POLICY, SQL-editor work for a later cleanup). The two
-- definer functions keep working (they run as the table owner). Block 2 clears the placemark data that builds
-- without the 5a client wrote after 20261019_0050 block 3 (they upsert it directly until block 1 closes the table).
--
-- What old clients see. A build without the 5a client (the installed build, Phase 1-4 builds): its
-- availability probe (select id limit 1) fails with 42501. It does not treat 42501 as a missing table
-- (main:NaarsCars/Core/Utilities/GeocodingCacheService.swift:173-198, :200-207 match only 42P01 or a
-- "does not exist" message), so it never turns caching off: every ride end that reaches the lookup sends one
-- failing probe before the read and another before the write, then reverse-geocodes on the device (2 s timeout
-- per end, the same multiplier rules); the estimate is still computed and saved. Nothing else changes for it.
--
-- Apply. Supabase MCP apply_migration, one call per block. Verification: dry run (now) through
-- supabase/dryruns/20261019_0062_geocoding_cache_direct_access_revoked.dryrun.sql (geocoding_revoked,
-- geocoding_lookup and short as savepoints), then the not-applied check; at the gate, the three probes after
-- the calls. Outcomes: not yet run. Block 2 cannot be undone (the multipliers are untouched).
-- Rollback. grant select, insert, update, delete, truncate, references, trigger on table public.geocoding_cache
-- to anon, authenticated; (the grants read in the plan's P2).

-- BLOCK 1
revoke all privileges on table public.geocoding_cache from anon, authenticated;

-- BLOCK 2: placemarks written by builds without the 5a client since 20261019_0050 block 3
update public.geocoding_cache set placemark_data = null where placemark_data is not null;
