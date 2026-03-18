-- Allow any emoji as a reaction, not just a hardcoded whitelist.
-- The previous CHECK constraint (message_reactions_reaction_check) only
-- allowed 21 specific emoji, causing custom emoji reactions to silently
-- fail on insert/upsert. The client already validates that reactions are
-- non-empty strings; RLS policies protect per-user access.
ALTER TABLE message_reactions DROP CONSTRAINT IF EXISTS message_reactions_reaction_check;

-- Keep a minimal safety net: reaction must be non-empty text
ALTER TABLE message_reactions ADD CONSTRAINT message_reactions_reaction_not_empty
    CHECK (reaction IS NOT NULL AND length(trim(reaction)) > 0);
