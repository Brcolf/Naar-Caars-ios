-- 20261005_0015_conversation_membership_write_lockdown.sql
--
-- APPLIED 2026-10-05 (Supabase MCP, one transaction) and verified with rolled-back probes.
--
-- Before this migration any signed-in user could:
--   * insert their own row into ANY conversation id (the INSERT policy had a
--     `user_id = auth.uid()` branch) and backdate joined_at, which made every message in that
--     conversation readable through the messages SELECT policy;
--   * rewrite any column of their own participant row (left_at back to null after being
--     removed, joined_at into the past);
--   * as a current or former participant, change conversations.created_by and then delete the
--     thread for everyone (messages cascade).
--
-- Callers checked (working tree and origin/main, the shipped build):
--   * participant inserts send only {conversation_id, user_id} (createConversationWithUsers,
--     always as the creator) or add added_by (addParticipantsToConversation, creator);
--   * participant updates touch only last_seen, notifications_muted, muted_until,
--     show_read_receipts;
--   * conversation updates touch only updated_at, title, group_image_url;
--   * leave / remove go through the SECURITY DEFINER RPCs (owner postgres, unaffected).
--
-- updated_at MUST stay granted on conversations: handle_new_message() is a SECURITY INVOKER
-- AFTER INSERT trigger on messages that runs `update conversations set updated_at = now()` as
-- the sender. Without the grant every message insert fails with 42501.
--
-- Deliberately NOT changed: users_can_view_their_conversations keeps left members (they keep a
-- frozen read-only thread; the messages SELECT policy bounds them by left_at).
--
-- Probes run as authenticated inside begin/rollback on 2026-10-05:
--   non-creator member: send (trigger bumped updated_at), own-row mute/last_seen update, rename
--   -> all succeed; self-join another conversation -> RLS violation; joined_at update and
--   created_by update -> permission denied.
--   creator: create conversation + both participant rows, add a member with added_by -> succeed.

alter policy authenticated_users_can_add_participants on public.conversation_participants
  with check (public.is_conversation_creator(conversation_id, (select auth.uid())));

revoke insert, update on public.conversation_participants from anon, authenticated;
grant insert (conversation_id, user_id, added_by) on public.conversation_participants to authenticated;
grant update (last_seen, notifications_muted, muted_until, show_read_receipts)
  on public.conversation_participants to authenticated;

revoke update on public.conversations from anon, authenticated;
grant update (title, group_image_url, updated_at) on public.conversations to authenticated;

alter policy participants_can_update_conversations on public.conversations
  using (exists (
    select 1 from public.conversation_participants cp
    where cp.conversation_id = conversations.id
      and cp.user_id = (select auth.uid())
      and cp.left_at is null
  ));
