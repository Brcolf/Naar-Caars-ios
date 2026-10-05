-- 20260717213140_20260717_0004_add_missing_fk_indexes.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- PERF-3: cover the 19 unindexed foreign keys flagged by the performance advisor.
-- Purely additive; improves planner performance on FK lookups/joins. IF NOT EXISTS is idempotent.
CREATE INDEX IF NOT EXISTS idx_completion_reminders_claimer_user_id ON public.completion_reminders (claimer_user_id);
CREATE INDEX IF NOT EXISTS idx_content_moderation_events_acted_by ON public.content_moderation_events (acted_by);
CREATE INDEX IF NOT EXISTS idx_content_moderation_events_report_id ON public.content_moderation_events (report_id);
CREATE INDEX IF NOT EXISTS idx_conversation_participants_added_by ON public.conversation_participants (added_by);
CREATE INDEX IF NOT EXISTS idx_favor_participants_added_by ON public.favor_participants (added_by);
CREATE INDEX IF NOT EXISTS idx_favors_hidden_by ON public.favors (hidden_by);
CREATE INDEX IF NOT EXISTS idx_messages_hidden_by ON public.messages (hidden_by);
CREATE INDEX IF NOT EXISTS idx_notification_queue_recipient_user_id ON public.notification_queue (recipient_user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_conversation_id ON public.notifications (conversation_id);
CREATE INDEX IF NOT EXISTS idx_notifications_favor_id ON public.notifications (favor_id);
CREATE INDEX IF NOT EXISTS idx_notifications_ride_id ON public.notifications (ride_id);
CREATE INDEX IF NOT EXISTS idx_profiles_banned_by ON public.profiles (banned_by);
CREATE INDEX IF NOT EXISTS idx_reports_reviewed_by ON public.reports (reviewed_by);
CREATE INDEX IF NOT EXISTS idx_request_qa_answered_by ON public.request_qa (answered_by);
CREATE INDEX IF NOT EXISTS idx_ride_participants_added_by ON public.ride_participants (added_by);
CREATE INDEX IF NOT EXISTS idx_rides_hidden_by ON public.rides (hidden_by);
CREATE INDEX IF NOT EXISTS idx_town_hall_comments_hidden_by ON public.town_hall_comments (hidden_by);
CREATE INDEX IF NOT EXISTS idx_town_hall_posts_hidden_by ON public.town_hall_posts (hidden_by);
CREATE INDEX IF NOT EXISTS idx_typing_indicators_user_id ON public.typing_indicators (user_id);
