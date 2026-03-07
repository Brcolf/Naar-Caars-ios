-- Add added_by to track who added each participant
ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS added_by uuid REFERENCES public.profiles(id);

-- Add per-conversation mute fields
ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS notifications_muted boolean NOT NULL DEFAULT false;

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS muted_until timestamptz;

-- Add per-conversation read receipt override (null = use global setting)
ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS show_read_receipts boolean;
