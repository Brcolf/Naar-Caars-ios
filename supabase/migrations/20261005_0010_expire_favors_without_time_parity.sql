-- 20261005_0010_expire_favors_without_time_parity.sql
--
-- Follow-up to 20261005_0007. For a favor without a time, the client treats the event time as
-- the favor's date at midnight (RequestItem.eventTime) and hides it from the dashboard 12 h
-- later; the expiry job defaulted to 23:59 and so kept such favors "open" (and counted as
-- Active) for almost another day. Use midnight on the server too.

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
      and ((f.date::date + coalesce(f.time::time, time '00:00')) at time zone coalesce(f.timezone, 'America/Los_Angeles'))
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
