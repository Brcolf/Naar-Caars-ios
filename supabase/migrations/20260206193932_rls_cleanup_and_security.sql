-- 20260206193932_rls_cleanup_and_security.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Phase 3: Database RLS Cleanup
-- 3A: Remove duplicate/overlapping RLS policies

-- Favors: remove duplicate INSERT and overly-permissive UPDATE
DROP POLICY IF EXISTS "Users can create own favors" ON public.favors;
DROP POLICY IF EXISTS "Users can claim favors" ON public.favors;

-- Rides: remove duplicate INSERT and overly-permissive UPDATE
DROP POLICY IF EXISTS "Users can create own rides" ON public.rides;
DROP POLICY IF EXISTS "Users can claim rides" ON public.rides;

-- Messages: remove duplicate INSERT and SELECT
DROP POLICY IF EXISTS "Participants can send messages" ON public.messages;
DROP POLICY IF EXISTS "Participants can view messages" ON public.messages;

-- Invite codes: remove duplicate SELECT policies (keep the functional ones)
DROP POLICY IF EXISTS "invite_codes_select_for_validation" ON public.invite_codes;
DROP POLICY IF EXISTS "invite_codes_select_own" ON public.invite_codes;

-- Invite codes: remove overly permissive UPDATE policy
DROP POLICY IF EXISTS "System can update invite codes" ON public.invite_codes;

-- Notifications: remove duplicate UPDATE
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;

-- 3B: Restrict overly permissive policies

-- conversation_participants INSERT: restrict from true to require auth
DROP POLICY IF EXISTS "authenticated_users_can_add_participants" ON public.conversation_participants;
CREATE POLICY "authenticated_users_can_add_participants" ON public.conversation_participants
    FOR INSERT TO authenticated
    WITH CHECK (
        -- User can add themselves, or is the conversation creator
        user_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.conversations c
            WHERE c.id = conversation_participants.conversation_id
            AND c.created_by = auth.uid()
        )
    );

-- completion_reminders: change from public to authenticated role
DROP POLICY IF EXISTS "completion_reminders_insert_service" ON public.completion_reminders;
CREATE POLICY "completion_reminders_insert_service" ON public.completion_reminders
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "completion_reminders_update_service" ON public.completion_reminders;
CREATE POLICY "completion_reminders_update_service" ON public.completion_reminders
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

-- notification_queue: change from public to authenticated
DROP POLICY IF EXISTS "notification_queue_insert_authenticated" ON public.notification_queue;
CREATE POLICY "notification_queue_insert_authenticated" ON public.notification_queue
    FOR INSERT TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "notification_queue_update_service" ON public.notification_queue;
CREATE POLICY "notification_queue_update_service" ON public.notification_queue
    FOR UPDATE TO authenticated
    USING (true)
    WITH CHECK (true);

-- notifications INSERT: change from public to authenticated
DROP POLICY IF EXISTS "notifications_insert_authenticated" ON public.notifications;
CREATE POLICY "notifications_insert_authenticated" ON public.notifications
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- 3B: Fix review-images storage bucket (allow only image MIME types)
UPDATE storage.buckets 
SET allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'review-images';
