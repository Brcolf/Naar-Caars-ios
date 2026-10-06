-- 20261006_0004_expire_dateonly_favors_after_their_day.sql
-- APPLIED 2026-10-06 through the Supabase MCP (expire_dateonly_favors_after_their_day).
--
-- A favor with no time is good for its whole day. The expiry job (20261005_0007 / 0010) and
-- the app both treated it as starting and ending at midnight, so a favor posted for "today"
-- was hidden in the app from noon and marked completed by this job that same evening
-- (03:15 UTC = 8:15 PM Pacific). The 12-hour grace now counts from the END of the favor's day;
-- timed favors and rides are unchanged. The app applies the same rule through
-- RequestItem.windowEnd (RequestFilterManager, PastRequestsViewModel).
--
-- Checked after applying (read-only): at 03:20 Pacific on Oct 6, a date-only favor dated
-- Oct 5 is not yet expired (old rule: expired), one dated Oct 4 is; both status-change triggers
-- are still enabled.

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
