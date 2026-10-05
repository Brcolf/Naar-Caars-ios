-- 20260206155622_fix_function_search_paths.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- ============================================================
-- FIX FUNCTION SEARCH_PATH SECURITY
-- Set search_path = '' on all public functions to prevent
-- search_path manipulation attacks
-- ============================================================

-- Trigger functions (no args)
ALTER FUNCTION public.handle_updated_at() SET search_path = '';
ALTER FUNCTION public.handle_invite_code_used() SET search_path = '';
ALTER FUNCTION public.handle_new_message() SET search_path = '';
ALTER FUNCTION public.handle_new_review() SET search_path = '';
ALTER FUNCTION public.protect_admin_fields() SET search_path = '';
ALTER FUNCTION public.mark_request_reviewed() SET search_path = '';
ALTER FUNCTION public.update_town_hall_comments_updated_at() SET search_path = '';
ALTER FUNCTION public.update_town_hall_votes_updated_at() SET search_path = '';
ALTER FUNCTION public.cleanup_stale_push_tokens() SET search_path = '';

-- Notification trigger functions (no args)
ALTER FUNCTION public.notify_new_ride() SET search_path = '';
ALTER FUNCTION public.notify_new_favor() SET search_path = '';
ALTER FUNCTION public.notify_ride_status_change() SET search_path = '';
ALTER FUNCTION public.notify_favor_status_change() SET search_path = '';
ALTER FUNCTION public.notify_qa_activity() SET search_path = '';
ALTER FUNCTION public.notify_qa_answer() SET search_path = '';
ALTER FUNCTION public.notify_town_hall_post() SET search_path = '';
ALTER FUNCTION public.notify_town_hall_comment() SET search_path = '';
ALTER FUNCTION public.notify_town_hall_vote() SET search_path = '';
ALTER FUNCTION public.notify_pending_user() SET search_path = '';
ALTER FUNCTION public.notify_user_approved() SET search_path = '';
ALTER FUNCTION public.notify_message_push() SET search_path = '';
ALTER FUNCTION public.notify_added_to_conversation() SET search_path = '';
ALTER FUNCTION public.process_batched_notifications() SET search_path = '';
ALTER FUNCTION public.process_immediate_notification() SET search_path = '';
ALTER FUNCTION public.trigger_notification_send() SET search_path = '';
ALTER FUNCTION public.process_completion_reminders() SET search_path = '';

-- Functions with specific signatures
ALTER FUNCTION public.is_user_approved(uuid) SET search_path = '';
ALTER FUNCTION public.is_conversation_participant(uuid, uuid) SET search_path = '';
ALTER FUNCTION public.is_user_blocked(uuid, uuid) SET search_path = '';
ALTER FUNCTION public.should_notify_user(uuid, text) SET search_path = '';

ALTER FUNCTION public.create_notification(uuid, text, text, text, uuid, uuid, uuid, uuid, uuid, uuid, boolean) SET search_path = '';
ALTER FUNCTION public.queue_push_notification(uuid, text, text, text, jsonb, text) SET search_path = '';
ALTER FUNCTION public.queue_push_notification(uuid, text, text, text, jsonb, text, uuid) SET search_path = '';
ALTER FUNCTION public.send_push_notification_direct(uuid, text, text, text, jsonb) SET search_path = '';
ALTER FUNCTION public.handle_completion_response(uuid, boolean) SET search_path = '';

ALTER FUNCTION public.edit_message(uuid, text) SET search_path = '';
ALTER FUNCTION public.unsend_message(uuid) SET search_path = '';
ALTER FUNCTION public.get_unread_message_count(uuid) SET search_path = '';
ALTER FUNCTION public.mark_messages_read(uuid, uuid) SET search_path = '';
ALTER FUNCTION public.mark_messages_read_batch(uuid[], uuid) SET search_path = '';

ALTER FUNCTION public.get_user_stats(uuid) SET search_path = '';
ALTER FUNCTION public.get_leaderboard(text, integer) SET search_path = '';
ALTER FUNCTION public.get_leaderboard(date, date) SET search_path = '';
ALTER FUNCTION public.get_unread_counts(uuid) SET search_path = '';
ALTER FUNCTION public.get_badge_counts(boolean, uuid) SET search_path = '';
ALTER FUNCTION public.get_pending_reviews(uuid) SET search_path = '';
ALTER FUNCTION public.mark_request_notifications_read(text, uuid, text[], boolean) SET search_path = '';

ALTER FUNCTION public.validate_invite_code(text) SET search_path = '';
ALTER FUNCTION public.get_or_create_request_conversation(uuid, uuid, uuid) SET search_path = '';

ALTER FUNCTION public.submit_report(uuid, uuid, uuid, text, text) SET search_path = '';
ALTER FUNCTION public.block_user(uuid, uuid, text) SET search_path = '';
ALTER FUNCTION public.unblock_user(uuid, uuid) SET search_path = '';
ALTER FUNCTION public.get_blocked_users(uuid) SET search_path = '';
