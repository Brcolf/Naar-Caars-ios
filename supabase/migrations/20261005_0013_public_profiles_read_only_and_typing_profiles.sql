-- 20261005_0013_public_profiles_read_only_and_typing_profiles.sql
--
-- 1. SECURITY (P0): public_profiles must be read-only.
--    The view was created by 20260416_0002 WITH (security_invoker = false) so that it can
--    project the safe columns of profiles past the own-row/admin-only RLS. It is a simple
--    single-table view, i.e. auto-updatable, it is owned by postgres (BYPASSRLS), and
--    Supabase's default privileges had granted INSERT/UPDATE/DELETE/TRUNCATE on it to anon
--    and authenticated. Verified on 2026-10-05 in a rolled-back transaction: `set local role
--    anon; update public_profiles set approved = not approved, name = ... where id = <other
--    user>` changed the row. Anyone holding the public anon key could therefore rename or
--    approve any account, or delete any profile (cascading to that user's rides, favors,
--    messages and reviews). No client or edge function writes through the view.
--
-- 2. Typing indicators for non-admin users.
--    get_typing_users() runs as the caller and joined public.profiles, which since the
--    projection split only returns the caller's own row (or everything for admins). For a
--    regular member the join was empty, so "… is typing" never appeared. Join the read-only
--    public_profiles projection instead.

revoke insert, update, delete, truncate, references, trigger
    on public.public_profiles from anon, authenticated, public;

grant select on public.public_profiles to anon, authenticated;

create or replace function public.get_typing_users(p_conversation_id uuid)
returns table(user_id uuid, user_name text, avatar_url text, started_at timestamp with time zone)
language plpgsql
set search_path to 'public'
as $function$
begin
    return query
    select
        ti.user_id,
        p.name as user_name,
        p.avatar_url,
        ti.started_at
    from typing_indicators ti
    join public_profiles p on ti.user_id = p.id
    where ti.conversation_id = p_conversation_id
      and ti.started_at > now() - interval '5 seconds'
      and ti.user_id != auth.uid(); -- don't include the current user
end;
$function$;
