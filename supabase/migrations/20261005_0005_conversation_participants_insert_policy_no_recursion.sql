-- 20261005_0005_conversation_participants_insert_policy_no_recursion.sql
--
-- Why: the INSERT policy on conversation_participants checked conversation ownership with a
-- direct subquery on conversations. Postgres expands RLS recursively: INSERT on
-- conversation_participants -> conversations SELECT policy (users_can_view_their_conversations)
-- -> conversation_participants again, which trips "infinite recursion detected in policy for
-- relation conversation_participants" (verified 2026-10-05). Every conversation created by the
-- app since the participants policies were tightened has therefore had zero participants
-- (6 orphans in production), because ConversationService swallowed the error.
--
-- Fix: evaluate ownership through a SECURITY DEFINER helper, which is opaque to the planner and
-- cannot re-enter conversation_participants' policy stack. Behaviour is unchanged: a user may
-- insert their own participant row, or any row into a conversation they created.
--
-- Note for tests: an INSERT ... RETURNING still fails the SELECT policy for the just-inserted
-- row because is_conversation_participant() is STABLE (statement snapshot). The app inserts
-- with return=minimal, so this does not affect it.

create or replace function public.is_conversation_creator(conv_id uuid, check_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversations
    where id = conv_id and created_by = check_user_id
  );
$$;

revoke all on function public.is_conversation_creator(uuid, uuid) from public, anon;
grant execute on function public.is_conversation_creator(uuid, uuid) to authenticated, service_role;

alter policy authenticated_users_can_add_participants on public.conversation_participants
  with check (
    (user_id = (select auth.uid()))
    or public.is_conversation_creator(conversation_id, (select auth.uid()))
  );
