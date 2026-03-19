-- Add ride and favor report target columns to the reports table.
-- Extends submit_report RPC to accept p_reported_ride_id and p_reported_favor_id.

-- Step 1: Add columns
ALTER TABLE public.reports
    ADD COLUMN IF NOT EXISTS reported_ride_id UUID REFERENCES public.rides(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reported_favor_id UUID REFERENCES public.favors(id) ON DELETE SET NULL;

-- Step 2: Indexes
CREATE INDEX IF NOT EXISTS idx_reports_reported_ride ON public.reports (reported_ride_id) WHERE reported_ride_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_reported_favor ON public.reports (reported_favor_id) WHERE reported_favor_id IS NOT NULL;

-- Step 3: Drop and recreate the target check constraint to include new columns.
-- The constraint name may vary (report_target_check or reports_target_check) so drop both.
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS report_target_check;
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_target_check;

ALTER TABLE public.reports ADD CONSTRAINT report_target_check CHECK (
    reported_user_id IS NOT NULL
    OR reported_message_id IS NOT NULL
    OR reported_post_id IS NOT NULL
    OR reported_comment_id IS NOT NULL
    OR reported_ride_id IS NOT NULL
    OR reported_favor_id IS NOT NULL
);

-- Step 4: Replace submit_report to accept new params
CREATE OR REPLACE FUNCTION public.submit_report(
    p_reporter_id uuid,
    p_reported_user_id uuid DEFAULT NULL::uuid,
    p_reported_message_id uuid DEFAULT NULL::uuid,
    p_reported_post_id uuid DEFAULT NULL::uuid,
    p_reported_comment_id uuid DEFAULT NULL::uuid,
    p_reported_ride_id uuid DEFAULT NULL::uuid,
    p_reported_favor_id uuid DEFAULT NULL::uuid,
    p_report_type text DEFAULT 'other'::text,
    p_description text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_report_id UUID;
BEGIN
    -- Target validation
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL
       AND p_reported_post_id IS NULL AND p_reported_comment_id IS NULL
       AND p_reported_ride_id IS NULL AND p_reported_favor_id IS NULL THEN
        RAISE EXCEPTION 'Must report a user, message, post, comment, ride, or favor';
    END IF;

    -- SECURITY: Verify the caller is the reporter (prevent spoofing)
    IF auth.uid() IS NULL OR auth.uid() != p_reporter_id THEN
        RAISE EXCEPTION 'Reporter ID must match authenticated user';
    END IF;

    -- Prevent duplicate reports per content type (use auth.uid() not p_reporter_id)
    IF p_reported_post_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports
                   WHERE reporter_id = auth.uid()
                   AND reported_post_id = p_reported_post_id) THEN
            RETURN NULL;
        END IF;
    END IF;
    IF p_reported_comment_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports
                   WHERE reporter_id = auth.uid()
                   AND reported_comment_id = p_reported_comment_id) THEN
            RETURN NULL;
        END IF;
    END IF;
    IF p_reported_ride_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports
                   WHERE reporter_id = auth.uid()
                   AND reported_ride_id = p_reported_ride_id) THEN
            RETURN NULL;
        END IF;
    END IF;
    IF p_reported_favor_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports
                   WHERE reporter_id = auth.uid()
                   AND reported_favor_id = p_reported_favor_id) THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Insert using auth.uid() as the trusted reporter identity
    INSERT INTO reports (
        reporter_id, reported_user_id, reported_message_id,
        reported_post_id, reported_comment_id,
        reported_ride_id, reported_favor_id,
        report_type, description
    ) VALUES (
        auth.uid(), p_reported_user_id, p_reported_message_id,
        p_reported_post_id, p_reported_comment_id,
        p_reported_ride_id, p_reported_favor_id,
        p_report_type, p_description
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$function$;
