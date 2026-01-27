-- Notification infra checks (run in Supabase SQL editor)
-- These should FAIL before migrations are applied.
select 'push_tokens' as table_name, to_regclass('public.push_tokens') is not null as exists;
select 'get_badge_counts' as fn_name, exists (
  select 1 from pg_proc where proname = 'get_badge_counts'
) as exists;
select 'mark_request_notifications_read' as fn_name, exists (
  select 1 from pg_proc where proname = 'mark_request_notifications_read'
) as exists;
