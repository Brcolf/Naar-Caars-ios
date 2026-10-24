-- 20261021_0023_example_content.sql
--
-- APPLIED 2026-10-22, all seven blocks, through the Supabase MCP apply_migration, one call per block, in file order,
-- each block's text sent byte for byte from this file (from its banner to its last statement), after the rolled-back
-- dry run below passed. Migration-history versions (UTC): 20261022151026 20261021_0023_block_1, 20261022151108
-- 20261021_0023_block_2, 20261022151146 20261021_0023_block_3, 20261022151221 20261021_0023_block_4, 20261022151255
-- 20261021_0023_block_5, 20261022151330 20261021_0023_block_6, 20261022151401 20261021_0023_block_7. No deviation:
-- every block ran as written below. Block 7's first run of refresh_example_requests() changed nothing (no example
-- row existed yet).
-- Deployed md5(prosrc), each read live after the apply and equal to the md5 of the text between this file's
-- $function$ delimiters (python3 -I over this file):
--   notify_new_ride()                         d6340863d0eabdd225cc89c5a0ed885f  (was 412d6ec764b021bed454a34bf55cb993)
--   notify_new_favor()                        5bf7bdd9a92be64672fcb50b5a0a2121  (was a4995495114a3936804b444de79df271)
--   notify_town_hall_post()                   88be4facf7fdb226d3789f1b6884c65c  (was 8067912ecd96ed2a655a82c1a9d247f7)
--   record_xp_on_request_created()            1e39d74adb74f12c5a3cd2f8dd2d9e91  (was a2f1a07e89f884da817302e9d13667a9)
--   expire_past_open_requests()               01311f2837a5a23a5eed143dc5943029  (was e798c760a31ed69697a23895238d52d7)
--   set_example_content(text, uuid, boolean)  86d6a53f226dd69bba811bffe55c2647  new
--   refresh_example_requests()                62f6d4826d19efd68eadd606c27e9d49  new
--   All seven are plpgsql, security definer, volatile, search_path "".
-- ACL (proacl; has_function_privilege anon / authenticated / service_role), read live after the apply (ruling R-G1):
--   set_example_content: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}; false / true / true
--     (revoked from public and anon, granted to authenticated and service_role; the function refuses everyone but a
--     platform admin).
--   refresh_example_requests and the five re-created functions: {postgres=X/postgres,service_role=X/postgres};
--     false / false / true (revoked from public, anon and authenticated). For the five re-created functions this is
--     the live ACL restated unchanged (read before the apply: the same text).
-- pg_cron: job refresh-example-requests, schedule '10 11 * * *', command 'select public.refresh_example_requests()',
-- active (read from cron.job after the apply; the jobs expire-past-open-requests '15 3 * * *' and
-- process-completion-reminders are unchanged).
--
-- Closing run (task S6), 2026-10-22, after S5a's data (Test Community's area, the four test communities flagged
-- is_test, 4 example rides, 4 example favors and 3 example posts in Test Community). The whole probe file
-- (supabase/probes/communities_probe.sql, unchanged) ran through the MCP in seven rolled-back execute_sql calls,
-- PARAMETERS and HELPERS in each (the call for legacy_bridges .. blocks carried HELPERS up to probe_world, every
-- helper those blocks call), full-line comments stripped, text otherwise as committed: 34 blocks,
-- every one PROBE ... OK (legacy_bridges returns SKIPPED, as it has since 20261019_0060), each call's last row its
-- last block's OK. posts_delete_policy and storage_private are the owner's SQL-editor blocks; the final
-- 'PROBE ALL OK' row comes from the owner's whole-file run. Nothing was left behind (counted afterwards: no probe
-- account, community, request, post, proposal, listing event or merged community; 11 example rows, 4 test
-- communities, the cron job active, the five status and updated_at triggers enabled).
-- EXECUTE matrix (ruling R-G1 as amended after S1), read live: md5(prosrc) of all seven functions equal the values
-- above. set_example_content: anon false, authenticated true. refresh_example_requests, notify_new_ride,
-- notify_new_favor, notify_town_hall_post, record_xp_on_request_created, expire_past_open_requests: anon false,
-- authenticated false. example_content ran over the live example rows inside its rolled-back transaction (the
-- second refresh changed nothing). No header or grant changed.
--
-- File D of Community Release 2 (discovery: community areas, search, listing rules, merging, example content;
-- Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md 4.11; plan
-- Docs/superpowers/plans/2026-10-21-community-release2-discovery-sql.md, task S4, with the orchestrator's rulings
-- R-G1, R3 and R11). Example requests and posts (is_example, added by File A, 20261021_0020 Block 5, and guarded by
-- its Block 10 so only definer code sets it) never notify, never earn XP and never expire, and a daily job keeps
-- example requests in the coming week.
--
-- What it does.
--   * Block 1, notify_new_ride() and notify_new_favor(): derived from pg_get_functiondef; right after each body's one
--     BEGIN, "IF NEW.is_example THEN RETURN NEW; END IF;". An example request writes no bell row and queues no push.
--   * Block 2, notify_town_hall_post(): the same guard first in the body, before the broadcast check. An example post
--     writes no "New in Town Hall" row or push.
--   * Block 3, record_xp_on_request_created(): the same guard first. An example request earns no XP, so the account
--     that posts the examples never leads a leaderboard.
--   * Block 4, expire_past_open_requests(): "and not r.is_example" and "and not f.is_example" after each
--     "status = 'open'" condition. The nightly expiry (03:15 UTC) never completes an example.
--   * Block 5, set_example_content(p_type, p_id, p_is_example) -> jsonb (new): a caller who is not a platform admin
--     -> {success: false, error: 'Not authorized - admin access required'}; p_type not in ride, favor,
--     town_hall_post, or a null id or flag -> {success: false, error, code: 'invalid'}; otherwise one definer update
--     of is_example on that row when it differs (guard_example_content lets a definer write through) ->
--     {success: true, changed} (changed false for an unknown id or a row that already has the value).
--   * Block 6, refresh_example_requests() -> integer (new; internal): for every example ride and favor with
--     hidden_at null, tomorrow = (now() at time zone coalesce(timezone, 'America/Los_Angeles'))::date + 1; a date
--     before tomorrow becomes date + 7 * ceil((tomorrow - date) / 7.0), the same weekday in [tomorrow, tomorrow + 6];
--     a row that is not open or has a helper becomes open with claimed_by null. Only rows that need a change are
--     written, so a second run the same day returns 0; a run after a missed week lands in the same window. Returns
--     the number of rows changed. No trigger is disabled: examples cannot be claimed, so the reopen branch is a
--     safety net; if it fires, notify_*_status_change may tell the poster ('ride_unclaimed' / 'favor_unclaimed'
--     when a helper is cleared), and set_updated_at runs on every row it moves.
--   * Block 7: cron.schedule('refresh-example-requests', '10 11 * * *', ...) (11:10 UTC daily, about 3-4 AM
--     Pacific, away from the 03:15 UTC expiry job), then one run of refresh_example_requests().
--
-- What old clients see. Nothing changes for a build in use until an example row exists (S5a writes them): no client
-- calls the two new functions (set_example_content is for the admin build or the SQL editor), the notifiers, XP and
-- expiry behave exactly as before for every row without the flag, and the registry stays at 34 types.
--
-- Apply order. Blocks 1-7 in file order, one Supabase MCP apply_migration per block, named
-- 20261021_0023_block_<n>, each block's text byte for byte from this file (banner to last statement), after the
-- rolled-back dry run (supabase/dryruns/20261021_0023_example_content.dryrun.sql) passed; probe short after each
-- block. Block 6 before Block 7. Nothing here is declined by the MCP (no DELETE, no DROP); the declined statements
-- are only in the rollback below.
--
-- Verification (supabase/probes/communities_probe.sql; every run through execute_sql, rolled back, with the probe
-- PARAMETERS and HELPERS in the same call). Outcomes, 2026-10-22:
--   P1-P4 read before the file was written: the five live md5 values below equal the source headers (and, for
--   expire_past_open_requests, ruling R11's value); the live bodies were read with pg_get_functiondef (base64, so
--   byte exact), their extracted prosrc md5 equal to the live values, and each edit's passage was found exactly once;
--   set_example_content, refresh_example_requests and the cron job did not exist; no 20261021_0023 file or
--   migration-history entry; no example row in rides, favors or town_hall_posts.
--   Dry run: supabase/dryruns/20261021_0023_example_content.dryrun.sql, assembled by script from the committed files
--   (the same assembler reproduces 20261021_0022's committed dry run byte for byte), structural check passed (no
--   commit; one begin; one rollback; 2 savepoints and 2 releases; 2 PROBE selects; helpers before begin; last two
--   statements the DRYRUN select and rollback;), sent verbatim in one call: DRYRUN 20261021_0023 OK after
--   example_content and short (each raises on its first failed check, so the final row means both passed), on the
--   first attempt. Afterwards the five P1 md5 values were unchanged, neither new function existed and cron.job had no
--   refresh-example-requests (Block 7's cron.schedule rolled back with the transaction).
--   Apply: PROBE short OK after each of the seven blocks. After Block 7: short, owner_notifications, reputation and
--   example_content in one call (last row PROBE example_content OK). Afterwards no probe profile and no example row
--   was left behind, and on_ride_status_change_notify / on_favor_status_change_notify are enabled (counted).
--
-- Implementer decisions (recorded for the review).
--   1. The guard is one line, "IF NEW.is_example THEN RETURN NEW; END IF;", placed right after BEGIN in all four
--      trigger functions (in notify_town_hall_post that is before the broadcast check, as "first in its body").
--   2. set_example_content also refuses a null id or flag with code 'invalid' (a null flag would otherwise write
--      nothing and report success); an unknown id answers {success: true, changed: false}. The 'invalid' text is
--      mine: 'Choose a ride, a favor or a post, and true or false'.
--   3. refresh_example_requests sets status = 'open' and claimed_by = null on every row it writes, including a row
--      written only for its date (values unchanged there); the row filter is the brief's "date < tomorrow, or not
--      open, or claimed".
--   4. example_content (ruling R3) posts in C1 as u(4) and goes beyond the brief's list: an example favor and its
--      control, no queued push for any example, a hidden example left alone, a 9-day-old example favor in
--      Pacific/Auckland moved within its own window, a future example left alone, a null flag and an unknown type
--      refused, anon and a member refused EXECUTE, and the definer / volatility / search_path of all seven functions.
--      The cron.job check is a read inside the probe's block (in the dry run the job existed only inside the
--      transaction). The probe calls expire_past_open_requests() and refresh_example_requests() over every live row
--      inside its rolled-back transaction, as the nightly jobs do.
--   5. The short runs after each block used the PARAMETERS and the helpers short needs (u, probe_subject, probe_run,
--      probe_call, probe_refused, probe_ok, probe_account, probe_member, with the commit), not the whole HELPERS
--      section; the dry run and the post-apply run used the whole section.
--
-- P1, the live values read on 2026-10-22 before this file (the rollback sources):
--   notify_new_ride()                 412d6ec764b021bed454a34bf55cb993  (20261017_0003 call 1)
--   notify_new_favor()                a4995495114a3936804b444de79df271  (20261017_0003 call 2)
--   notify_town_hall_post()           8067912ecd96ed2a655a82c1a9d247f7  (20261019_0002 block 1)
--   record_xp_on_request_created()    a2f1a07e89f884da817302e9d13667a9  (20261017_0003 call 7)
--   expire_past_open_requests()       e798c760a31ed69697a23895238d52d7  (20261006_0004, whose header records no md5;
--                                                                         ruling R11)
--
-- Rollback (in this order).
--   Block 7 (SQL editor, owner): select cron.unschedule('refresh-example-requests');
--   Blocks 6 and 5 (SQL editor, owner; the MCP declines DROP FUNCTION), after Block 7's:
--     drop function public.refresh_example_requests();
--     drop function public.set_example_content(text, uuid, boolean);
--   Blocks 4-1 (MCP): re-create expire_past_open_requests(), record_xp_on_request_created(), notify_town_hall_post(),
--     notify_new_favor() and notify_new_ride() from the P1 sources above (the md5 values above); the ACLs stay as
--     they are. Once example rows exist, restoring Block 4 lets the nightly expiry complete past examples and
--     restoring Blocks 1-3 makes a newly inserted example notify and earn XP again; set the examples' is_example to
--     false or remove them first (S5a's data).


-- ============================================================================================
-- BLOCK 1: public.notify_new_ride() and public.notify_new_favor()
--          live md5(prosrc) 412d6ec764b021bed454a34bf55cb993 and a4995495114a3936804b444de79df271
--          (20261017_0003 calls 1 and 2)
-- Derived from pg_get_functiondef: after the one BEGIN of each body (found once), an example request returns
-- before any bell row or push. Nothing else changes.
-- ============================================================================================
create or replace function public.notify_new_ride()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_poster_name TEXT;
    v_destination TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    IF NEW.is_example THEN RETURN NEW; END IF;
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    v_destination := COALESCE(NEW.destination, 'a destination');

    FOR v_user_record IN
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'new_ride', 'New Ride Request',
            v_poster_name || ' needs a ride to ' || v_destination,
            NEW.id, NULL, NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'new_ride', 'New Ride Request',
                v_poster_name || ' needs a ride to ' || v_destination,
                jsonb_build_object('ride_id', NEW.id::text, 'community_id', NEW.community_id::text),
                NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_new_ride() from public, anon, authenticated;

create or replace function public.notify_new_favor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    IF NEW.is_example THEN RETURN NEW; END IF;
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    FOR v_user_record IN
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'new_favor', 'New Favor Request',
            v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
            NULL, NEW.id, NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'new_favor', 'New Favor Request',
                v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
                jsonb_build_object('favor_id', NEW.id::text, 'community_id', NEW.community_id::text),
                NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_new_favor() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 2: public.notify_town_hall_post()
--          live md5(prosrc) 8067912ecd96ed2a655a82c1a9d247f7 (20261019_0002 block 1)
-- Derived from pg_get_functiondef: the same guard first in the body (after its one BEGIN), so an example post
-- writes no "New in Town Hall" row or push. Nothing else changes.
-- ============================================================================================
create or replace function public.notify_town_hall_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_batch_key TEXT;
    v_notification_id UUID;
BEGIN
    IF NEW.is_example THEN RETURN NEW; END IF;
    -- send_community_broadcast sends this announcement's own push (20261019_0002 block 2); the Town Hall notice
    -- would be a second, batched one. The setting is transaction-local and set only around that one insert.
    IF NEW.type = 'announcement'
       AND coalesce(current_setting('naars.broadcast_post', true), '') = '1' THEN
        RETURN NEW;
    END IF;

    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    v_batch_key := 'town_hall_' || NEW.community_id::text || '_' || to_char(date_trunc('minute', NOW()) -
        (EXTRACT(MINUTE FROM NOW())::int % 5) * INTERVAL '1 minute', 'YYYY-MM-DD-HH24-MI');

    FOR v_user_record IN
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND p.notify_town_hall = true
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'town_hall_post', 'New in Town Hall',
            v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
            NULL, NULL, NULL, NULL, NEW.id, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'town_hall_post', 'New in Town Hall',
                v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
                jsonb_build_object('town_hall_post_id', NEW.id::text, 'community_id', NEW.community_id::text),
                v_batch_key, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_town_hall_post() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 3: public.record_xp_on_request_created()
--          live md5(prosrc) a2f1a07e89f884da817302e9d13667a9 (20261017_0003 call 7)
-- Derived from pg_get_functiondef: the same guard first in the body (after its one BEGIN). An example request
-- earns no XP, so the account that posts the examples never leads a leaderboard. Nothing else changes.
-- ============================================================================================
create or replace function public.record_xp_on_request_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_is_first BOOLEAN;
BEGIN
    IF NEW.is_example THEN RETURN NEW; END IF;
    IF TG_TABLE_NAME = 'rides' THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
        VALUES (
            NEW.user_id, 5, 'ride_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride'),
            NEW.created_at, NEW.community_id
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.rides WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
            VALUES (NEW.user_id, 10, 'first_ride', NEW.id, 'First ride milestone', NEW.created_at, NEW.community_id)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    ELSE
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
        VALUES (
            NEW.user_id, 5, 'favor_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.title, 'Favor'),
            NEW.created_at, NEW.community_id
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.favors WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
            VALUES (NEW.user_id, 10, 'first_favor', NEW.id, 'First favor milestone', NEW.created_at, NEW.community_id)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

revoke all on function public.record_xp_on_request_created() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 4: public.expire_past_open_requests()
--          live md5(prosrc) e798c760a31ed69697a23895238d52d7 (20261006_0004; ruling R11)
-- Derived from pg_get_functiondef: "and not r.is_example" and "and not f.is_example" after each
-- "status = 'open'" condition (each found once). An example never expires; refresh_example_requests (Block 6)
-- moves it forward instead. Nothing else changes.
-- ============================================================================================
create or replace function public.expire_past_open_requests()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_count integer := 0;
    v_rides integer;
    v_favors integer;
begin
    -- The status-change triggers would message ride/favor participants ("marked as
    -- completed") and queue pushes for every stale row; expiry is housekeeping, so they are
    -- disabled for the duration of this function. The XP trigger is a no-op (claimed_by is
    -- null) and set_updated_at still runs.
    alter table public.rides disable trigger on_ride_status_change_notify;
    alter table public.favors disable trigger on_favor_status_change_notify;

    update public.rides r
    set status = 'completed'
    where r.status = 'open'
      and not r.is_example
      and r.claimed_by is null
      and ((r.date::date + r.time::time) at time zone coalesce(r.timezone, 'America/Los_Angeles'))
            < now() - interval '12 hours';
    get diagnostics v_rides = row_count;

    update public.favors f
    set status = 'completed'
    where f.status = 'open'
      and not f.is_example
      and f.claimed_by is null
      and (case
             when f.time is null
               then ((f.date::date + 1)::timestamp at time zone coalesce(f.timezone, 'America/Los_Angeles'))
             else ((f.date::date + f.time::time) at time zone coalesce(f.timezone, 'America/Los_Angeles'))
           end) < now() - interval '12 hours';
    get diagnostics v_favors = row_count;

    alter table public.rides enable trigger on_ride_status_change_notify;
    alter table public.favors enable trigger on_favor_status_change_notify;

    v_count := coalesce(v_rides, 0) + coalesce(v_favors, 0);
    return v_count;
exception when others then
    alter table public.rides enable trigger on_ride_status_change_notify;
    alter table public.favors enable trigger on_favor_status_change_notify;
    raise;
end;
$function$;

revoke all on function public.expire_past_open_requests() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 5: public.set_example_content(text, uuid, boolean)   (new; authenticated, service_role; platform admins)
-- ============================================================================================
create or replace function public.set_example_content(p_type text, p_id uuid, p_is_example boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer := 0;
begin
  if (select auth.uid()) is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;

  if p_type is null or p_type not in ('ride', 'favor', 'town_hall_post') or p_id is null or p_is_example is null then
    return jsonb_build_object('success', false, 'error', 'Choose a ride, a favor or a post, and true or false',
                              'code', 'invalid');
  end if;

  -- a definer write: guard_example_content (20261021_0020 Block 10) lets it through
  if p_type = 'ride' then
    update public.rides set is_example = p_is_example
     where id = p_id and is_example is distinct from p_is_example;
  elsif p_type = 'favor' then
    update public.favors set is_example = p_is_example
     where id = p_id and is_example is distinct from p_is_example;
  else
    update public.town_hall_posts set is_example = p_is_example
     where id = p_id and is_example is distinct from p_is_example;
  end if;
  get diagnostics v_count = row_count;

  return jsonb_build_object('success', true, 'changed', v_count > 0);
end
$function$;

revoke all on function public.set_example_content(text, uuid, boolean) from public, anon;
grant execute on function public.set_example_content(text, uuid, boolean) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 6: public.refresh_example_requests()   (new; internal: the daily job, Block 7)
-- Every example ride and favor that is not hidden: tomorrow is the day after today in the row's own time zone; a
-- date before tomorrow moves forward by whole weeks (same weekday) to the first such day on or after tomorrow, so
-- it lands in [tomorrow, tomorrow + 6]; a row that is not open or has a helper becomes open with no helper.
-- Only rows that need a change are written, so a second run the same day changes nothing. Returns the number of
-- rows changed. No trigger is disabled: examples cannot be claimed (guard_example_content), so the reopen branch is
-- a safety net, and if it fires the status trigger may tell the poster.
-- ============================================================================================
create or replace function public.refresh_example_requests()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_rides integer := 0;
  v_favors integer := 0;
begin
  with t as (
    select r.id, (now() at time zone coalesce(r.timezone, 'America/Los_Angeles'))::date + 1 as tomorrow
      from public.rides r
     where r.is_example and r.hidden_at is null
  )
  update public.rides r
     set date = case when r.date < t.tomorrow
                     then r.date + 7 * ceil((t.tomorrow - r.date) / 7.0)::int
                     else r.date end,
         status = 'open',
         claimed_by = null
    from t
   where r.id = t.id
     and (r.date < t.tomorrow or r.status::text <> 'open' or r.claimed_by is not null);
  get diagnostics v_rides = row_count;

  with t as (
    select f.id, (now() at time zone coalesce(f.timezone, 'America/Los_Angeles'))::date + 1 as tomorrow
      from public.favors f
     where f.is_example and f.hidden_at is null
  )
  update public.favors f
     set date = case when f.date < t.tomorrow
                     then f.date + 7 * ceil((t.tomorrow - f.date) / 7.0)::int
                     else f.date end,
         status = 'open',
         claimed_by = null
    from t
   where f.id = t.id
     and (f.date < t.tomorrow or f.status::text <> 'open' or f.claimed_by is not null);
  get diagnostics v_favors = row_count;

  return v_rides + v_favors;
end
$function$;

revoke all on function public.refresh_example_requests() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 7: the daily job refresh-example-requests at 11:10 UTC (about 3-4 AM Pacific, away from the 03:15 UTC
-- expiry job), then one run now
-- ============================================================================================
select cron.schedule('refresh-example-requests', '10 11 * * *', $$select public.refresh_example_requests()$$);

select public.refresh_example_requests();
