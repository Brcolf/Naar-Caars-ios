-- 20261005_0012_find_conversation_for_participants.sql
--
-- One thread per participant set (iMessage semantics). "Message Participants" on a ride or
-- favor detail created a brand-new conversation on every tap (six Brendan ↔ Alice threads
-- existed on 2026-10-05), and find_dm_conversation() only covers two-member threads. This
-- RPC returns the most recently updated untitled conversation whose active members are
-- exactly the given set (the caller must be one of them); the client calls it before
-- createConversationWithUsers(). Named groups (title set) stay distinct threads.

create or replace function public.find_conversation_for_participants(p_user_ids uuid[])
returns uuid
language sql
security definer
set search_path to 'public'
as $function$
    with wanted as (
        select array_agg(distinct u order by u) as ids from unnest(p_user_ids) as u
    )
    select c.id
    from conversations c, wanted w
    where c.title is null
      and (select auth.uid()) = any(w.ids)
      and (
          select coalesce(array_agg(cp.user_id order by cp.user_id), '{}'::uuid[])
          from conversation_participants cp
          where cp.conversation_id = c.id and cp.left_at is null
      ) = w.ids
    -- Prefer the thread people actually use: latest user message first, then updated_at.
    order by (
        select max(m.created_at) from messages m
        where m.conversation_id = c.id and m.message_type <> 'system'
    ) desc nulls last, c.updated_at desc nulls last, c.created_at desc
    limit 1;
$function$;

revoke all on function public.find_conversation_for_participants(uuid[]) from public, anon;
grant execute on function public.find_conversation_for_participants(uuid[]) to authenticated;
