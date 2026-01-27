-- ============================================================================
-- 087_reports_and_blocking.sql - User reports and blocking functionality
-- ============================================================================
-- Adds support for:
-- 1. Report messages or users for abuse
-- 2. Block/unblock users
-- 3. Report management for admins
-- ============================================================================

-- ============================================================================
-- PART 1: Create reports table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    reported_message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
    report_type TEXT NOT NULL CHECK (report_type IN ('spam', 'harassment', 'inappropriate_content', 'scam', 'other')),
    description TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'action_taken', 'dismissed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    admin_notes TEXT,
    
    -- Ensure at least one of reported_user_id or reported_message_id is set
    CONSTRAINT report_target_check CHECK (
        reported_user_id IS NOT NULL OR reported_message_id IS NOT NULL
    )
);

-- Add comments
COMMENT ON TABLE public.reports IS 'User-submitted reports of abusive content or users';
COMMENT ON COLUMN public.reports.report_type IS 'Type of violation being reported';
COMMENT ON COLUMN public.reports.status IS 'Current status of the report review';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_reports_reporter ON public.reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_reports_reported_user ON public.reports(reported_user_id);
CREATE INDEX IF NOT EXISTS idx_reports_reported_message ON public.reports(reported_message_id);
CREATE INDEX IF NOT EXISTS idx_reports_status ON public.reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_created_at ON public.reports(created_at DESC);

-- ============================================================================
-- PART 2: Create blocked_users table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.blocked_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reason TEXT,
    
    -- Prevent duplicate blocks
    CONSTRAINT unique_block UNIQUE (blocker_id, blocked_id),
    -- Prevent self-blocking
    CONSTRAINT no_self_block CHECK (blocker_id != blocked_id)
);

-- Add comments
COMMENT ON TABLE public.blocked_users IS 'Users who have blocked other users';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocker ON public.blocked_users(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked ON public.blocked_users(blocked_id);

-- ============================================================================
-- PART 3: RLS Policies for reports
-- ============================================================================

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Users can create reports
CREATE POLICY "Users can create reports"
ON public.reports FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = reporter_id);

-- Users can view their own reports
CREATE POLICY "Users can view own reports"
ON public.reports FOR SELECT
TO authenticated
USING (auth.uid() = reporter_id);

-- Admins can view all reports (implement admin check based on your schema)
-- For now, allowing authenticated users to read reports they're involved in
CREATE POLICY "Users can view reports about them"
ON public.reports FOR SELECT
TO authenticated
USING (auth.uid() = reported_user_id);

-- ============================================================================
-- PART 4: RLS Policies for blocked_users
-- ============================================================================

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

-- Users can view their own blocks
CREATE POLICY "Users can view own blocks"
ON public.blocked_users FOR SELECT
TO authenticated
USING (auth.uid() = blocker_id);

-- Users can create blocks
CREATE POLICY "Users can create blocks"
ON public.blocked_users FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = blocker_id);

-- Users can delete their own blocks (unblock)
CREATE POLICY "Users can delete own blocks"
ON public.blocked_users FOR DELETE
TO authenticated
USING (auth.uid() = blocker_id);

-- ============================================================================
-- PART 5: Helper functions
-- ============================================================================

-- Function to check if a user is blocked
CREATE OR REPLACE FUNCTION public.is_user_blocked(
    p_user_id UUID,
    p_other_user_id UUID
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.blocked_users
        WHERE (blocker_id = p_user_id AND blocked_id = p_other_user_id)
           OR (blocker_id = p_other_user_id AND blocked_id = p_user_id)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to submit a report
CREATE OR REPLACE FUNCTION public.submit_report(
    p_reporter_id UUID,
    p_reported_user_id UUID DEFAULT NULL,
    p_reported_message_id UUID DEFAULT NULL,
    p_report_type TEXT DEFAULT 'other',
    p_description TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_report_id UUID;
BEGIN
    -- Validate input
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL THEN
        RAISE EXCEPTION 'Must report either a user or a message';
    END IF;
    
    -- Insert report
    INSERT INTO public.reports (
        reporter_id,
        reported_user_id,
        reported_message_id,
        report_type,
        description
    ) VALUES (
        p_reporter_id,
        p_reported_user_id,
        p_reported_message_id,
        p_report_type,
        p_description
    )
    RETURNING id INTO v_report_id;
    
    RETURN v_report_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to block a user
CREATE OR REPLACE FUNCTION public.block_user(
    p_blocker_id UUID,
    p_blocked_id UUID,
    p_reason TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    -- Prevent self-blocking
    IF p_blocker_id = p_blocked_id THEN
        RAISE EXCEPTION 'Cannot block yourself';
    END IF;
    
    -- Insert or ignore if already blocked
    INSERT INTO public.blocked_users (blocker_id, blocked_id, reason)
    VALUES (p_blocker_id, p_blocked_id, p_reason)
    ON CONFLICT (blocker_id, blocked_id) DO NOTHING;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to unblock a user
CREATE OR REPLACE FUNCTION public.unblock_user(
    p_blocker_id UUID,
    p_blocked_id UUID
) RETURNS BOOLEAN AS $$
BEGIN
    DELETE FROM public.blocked_users
    WHERE blocker_id = p_blocker_id AND blocked_id = p_blocked_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get blocked users for a user
CREATE OR REPLACE FUNCTION public.get_blocked_users(
    p_user_id UUID
) RETURNS TABLE (
    blocked_id UUID,
    blocked_name TEXT,
    blocked_avatar_url TEXT,
    blocked_at TIMESTAMPTZ,
    reason TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        bu.blocked_id,
        p.name AS blocked_name,
        p.avatar_url AS blocked_avatar_url,
        bu.created_at AS blocked_at,
        bu.reason
    FROM public.blocked_users bu
    JOIN public.profiles p ON p.id = bu.blocked_id
    WHERE bu.blocker_id = p_user_id
    ORDER BY bu.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 6: Update message queries to respect blocks
-- ============================================================================

-- Create a view that filters messages from blocked users
CREATE OR REPLACE VIEW public.messages_filtered AS
SELECT m.*
FROM public.messages m
WHERE NOT EXISTS (
    SELECT 1 FROM public.blocked_users bu
    WHERE bu.blocker_id = auth.uid()
    AND bu.blocked_id = m.from_id
);

-- ============================================================================
-- PART 7: Verify changes
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 087_reports_and_blocking.sql completed successfully';
    RAISE NOTICE 'Created tables: reports, blocked_users';
    RAISE NOTICE 'Created functions: is_user_blocked, submit_report, block_user, unblock_user, get_blocked_users';
END $$;


