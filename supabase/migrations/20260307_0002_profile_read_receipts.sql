-- Global read receipt preference on profile
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS show_read_receipts boolean NOT NULL DEFAULT true;
