-- Enable RLS on content_moderation_events.
--
-- Audit ref: Supabase advisor `rls_disabled_in_public` on
-- public.content_moderation_events. The table was created in
-- 20260403_0011_content_moderation_redesign without an
-- ALTER TABLE ... ENABLE ROW LEVEL SECURITY, leaving the moderation
-- audit log readable and insertable by any client with the publishable
-- anon key.
--
-- Live exposure before this fix:
--   - Read: anon/authenticated could SELECT every row (who hid what
--     content, by which admin, with what reason, linked to which report).
--   - Write: anon/authenticated could INSERT arbitrary rows, planting
--     fake auto_hide events into the audit trail.
--   - UPDATE/DELETE were already blocked by the append-only trigger
--     installed in 20260403_0011.
--
-- Fix: enable RLS, allow only admin SELECT. No INSERT/UPDATE/DELETE
-- policies — all client-direct writes denied by default. The legitimate
-- insert path is the SECURITY DEFINER moderation RPCs in 20260403_0011,
-- which run as postgres (the table owner) and bypass RLS.

ALTER TABLE public.content_moderation_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "moderation_events_select_admin"
ON public.content_moderation_events
FOR SELECT
TO authenticated
USING (is_admin_user(auth.uid()));

COMMENT ON TABLE public.content_moderation_events IS
    'Append-only audit log of moderation actions. RLS: admins read only. '
    'Inserts flow through SECURITY DEFINER RPCs in 20260403_0011 which '
    'run as postgres and bypass RLS. UPDATE/DELETE blocked by the '
    'content_moderation_events_append_only trigger.';
