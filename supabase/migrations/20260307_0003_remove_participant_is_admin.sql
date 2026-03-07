-- Remove is_admin from conversation_participants (flat permission model)
-- Note: profiles.is_admin (app-level admin) is NOT affected
ALTER TABLE public.conversation_participants
  DROP COLUMN IF EXISTS is_admin;
