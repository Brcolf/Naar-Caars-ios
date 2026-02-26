-- Restrict notifications INSERT to self-only.
-- All notification creation already goes through SECURITY DEFINER RPCs
-- and Edge Functions that use the service role key.
-- Client code never inserts directly into this table (verified by grep).
-- Service role bypasses RLS entirely, so RPCs/Edge Functions are unaffected.

drop policy if exists "notifications_insert" on public.notifications;
drop policy if exists "notifications_insert_service_only" on public.notifications;

-- Only allow inserting notifications for yourself (self-notifications).
-- Service role (used by RPCs, triggers, Edge Functions) bypasses RLS entirely.
create policy "notifications_insert_service_only" on public.notifications
  for insert
  with check (
    auth.uid() = user_id
  );
