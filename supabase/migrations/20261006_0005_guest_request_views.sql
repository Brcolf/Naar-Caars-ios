-- 20261006_0005_guest_request_views.sql
-- APPLIED 2026-10-06 through the Supabase MCP (guest_request_views).
--
-- Guests (the anon role) browse rides and favors without an account, and the app does not show
-- them addresses. These two views are what a guest reads: the same rows and the same column
-- set as the tables, with the address columns blanked on the server.
--   guest_rides   pickup, destination -> ''
--   guest_favors  location            -> ''
-- Everything else a guest sees on screen (title, notes, description, requirements, gift,
-- flight, date and time, status) is unchanged. Hiding more is a one-line change here.
--
-- The views run with the owner's rights (security_invoker = false), the same pattern as
-- public_profiles, filter hidden_at IS NULL themselves, and are readable by anon only. A
-- signed-in client never reads them (RideService / FavorService pick the relation from whether
-- a session exists) and gets "permission denied" if it ever does, instead of blank addresses
-- in its cache.
--
-- A column added to rides or favors must be added to the matching view in the same migration.
--
-- Verified after applying: column names, types and order match the tables; over REST as anon
-- guest_rides returns every visible ride and guest_favors every visible favor with no address
-- text; anon cannot write to the views; a signed-in role cannot read them.

create or replace view public.guest_rides
with (security_barrier = true, security_invoker = false) as
select
    r.id, r.user_id, r.type, r.date, r."time",
    ''::text as pickup,
    ''::text as destination,
    r.seats, r.notes, r.gift, r.status, r.claimed_by, r.reviewed, r.review_skipped, r.review_skipped_at,
    r.created_at, r.updated_at, r.estimated_cost, r.flight_normalized, r.timezone,
    r.hidden_at, r.hidden_by, r.hidden_reason
from public.rides r
where r.hidden_at is null;

create or replace view public.guest_favors
with (security_barrier = true, security_invoker = false) as
select
    f.id, f.user_id, f.title, f.description,
    ''::text as location,
    f.duration, f.requirements, f.date, f."time", f.gift, f.status, f.claimed_by, f.reviewed,
    f.review_skipped, f.review_skipped_at, f.created_at, f.updated_at, f.timezone,
    f.hidden_at, f.hidden_by, f.hidden_reason
from public.favors f
where f.hidden_at is null;

revoke all on public.guest_rides from public, anon, authenticated;
revoke all on public.guest_favors from public, anon, authenticated;
grant select on public.guest_rides to anon;
grant select on public.guest_favors to anon;

comment on view public.guest_rides is 'Rides as a guest may see them: visible rows only, pickup and destination blanked.';
comment on view public.guest_favors is 'Favors as a guest may see them: visible rows only, location blanked.';
