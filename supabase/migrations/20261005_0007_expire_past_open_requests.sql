-- 20261005_0007_expire_past_open_requests.sql
--
-- Applied through the Supabase MCP on 2026-10-05 (cron job 'expire-past-open-requests').
--
-- Expire past-dated open requests. On 2026-10-05 all 71 "open" rides and 45 "open" favors
-- were dated in the past, so the dashboard was empty for everyone yet the admin stats still
-- reported "Active 125" and every full dashboard sync evaluated 158+ rows to render none.
-- A nightly job marks open requests whose event time is more than 12 hours past (the same
-- window RequestFilterManager uses client-side) as 'completed' with claimed_by = null, so
-- they move to Past Requests. 'completed' is used because the status enums have no
-- 'expired' value and the Swift RideStatus/FavorStatus decoders fall back to .open for an
-- unknown raw value, which would resurface the rows on the dashboard.

create or replace function public.expire_past_open_requests()
returns integer
language plpgsql
security definer
set search_path to ''
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
      and r.claimed_by is null
      and ((r.date::date + r.time::time) at time zone coalesce(r.timezone, 'America/Los_Angeles'))
            < now() - interval '12 hours';
    get diagnostics v_rides = row_count;

    update public.favors f
    set status = 'completed'
    where f.status = 'open'
      and f.claimed_by is null
      and ((f.date::date + coalesce(f.time::time, time '23:59')) at time zone coalesce(f.timezone, 'America/Los_Angeles'))
            < now() - interval '12 hours';
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

select cron.schedule(
    'expire-past-open-requests',
    '15 3 * * *',
    $$select public.expire_past_open_requests()$$
);
