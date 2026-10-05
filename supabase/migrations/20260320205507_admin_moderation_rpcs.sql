-- 20260320205507_admin_moderation_rpcs.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- ============================================================
-- admin_moderation_rpcs
-- Adds the two RPC functions required by AdminModerationService.swift:
--   1. admin_get_reports  — returns reports for the admin panel
--   2. admin_moderate_content — lets admins hide/restore/dismiss reports
-- Also adds the content_hidden column that AdminReport.contentHidden expects.
-- ============================================================

-- 1. Add content_hidden flag to reports (defaults false, safe additive change)
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS content_hidden BOOLEAN NOT NULL DEFAULT false;

-- 2. admin_get_reports
--    Returns rows matching the AdminReport Codable struct:
--      reportId, reporterId, reporterName, reportedUserId, reportedUserName,
--      reportedPostId, reportedCommentId, reportType, description, status,
--      createdAt, reviewedAt, contentPreview, contentHidden, reportCount
CREATE OR REPLACE FUNCTION public.admin_get_reports(
  p_admin_id UUID,
  p_status   TEXT DEFAULT NULL
)
RETURNS TABLE (
  report_id         UUID,
  reporter_id       UUID,
  reporter_name     TEXT,
  reported_user_id  UUID,
  reported_user_name TEXT,
  reported_post_id  UUID,
  reported_comment_id UUID,
  report_type       TEXT,
  description       TEXT,
  status            TEXT,
  created_at        TIMESTAMPTZ,
  reviewed_at       TIMESTAMPTZ,
  content_preview   TEXT,
  content_hidden    BOOLEAN,
  report_count      INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify caller is admin
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_admin_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Unauthorized: caller is not an admin';
  END IF;

  RETURN QUERY
  WITH grouped AS (
    -- Count duplicate reports per unique target
    SELECT
      COALESCE(r.reported_message_id, r.reported_post_id, r.reported_comment_id,
               r.reported_ride_id, r.reported_favor_id, r.reported_user_id) AS target_key,
      count(*)::INT AS dup_count
    FROM public.reports r
    GROUP BY target_key
  )
  SELECT
    r.id                              AS report_id,
    r.reporter_id                     AS reporter_id,
    rp.name                           AS reporter_name,
    r.reported_user_id                AS reported_user_id,
    ru.name                           AS reported_user_name,
    r.reported_post_id                AS reported_post_id,
    r.reported_comment_id             AS reported_comment_id,
    r.report_type                     AS report_type,
    r.description                     AS description,
    r.status                          AS status,
    r.created_at                      AS created_at,
    r.reviewed_at                     AS reviewed_at,
    -- Build a content preview from whichever target exists
    COALESCE(
      LEFT(msg.content, 200),
      LEFT(post.content, 200),
      LEFT(cmt.content, 200),
      LEFT(ride.pickup_address || ' → ' || ride.destination_address, 200),
      LEFT(fav.title || ': ' || COALESCE(fav.description, ''), 200),
      ru.name
    )                                 AS content_preview,
    r.content_hidden                  AS content_hidden,
    COALESCE(g.dup_count, 1)          AS report_count
  FROM public.reports r
  LEFT JOIN public.profiles rp  ON rp.id = r.reporter_id
  LEFT JOIN public.profiles ru  ON ru.id = r.reported_user_id
  LEFT JOIN public.messages msg ON msg.id = r.reported_message_id
  LEFT JOIN public.town_hall_posts post ON post.id = r.reported_post_id
  LEFT JOIN public.town_hall_comments cmt ON cmt.id = r.reported_comment_id
  LEFT JOIN public.rides ride   ON ride.id = r.reported_ride_id
  LEFT JOIN public.favors fav   ON fav.id = r.reported_favor_id
  LEFT JOIN grouped g           ON g.target_key = COALESCE(
      r.reported_message_id, r.reported_post_id, r.reported_comment_id,
      r.reported_ride_id, r.reported_favor_id, r.reported_user_id)
  WHERE (p_status IS NULL OR r.status = p_status)
  ORDER BY r.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.admin_get_reports IS
  'Returns all reports for the admin panel, optionally filtered by status. Caller must be admin.';


-- 3. admin_moderate_content
--    Actions: hide, restore, dismiss
--    Updates the report row and, for hide/restore, also sets content_hidden on
--    all reports sharing the same target so the flag stays consistent.
CREATE OR REPLACE FUNCTION public.admin_moderate_content(
  p_admin_id    UUID,
  p_report_id   UUID,
  p_action      TEXT,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_status TEXT;
  v_post_id    UUID;
  v_comment_id UUID;
  v_message_id UUID;
  v_ride_id    UUID;
  v_favor_id   UUID;
BEGIN
  -- Verify caller is admin
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_admin_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Unauthorized: caller is not an admin';
  END IF;

  -- Validate action
  IF p_action NOT IN ('hide', 'restore', 'dismiss') THEN
    RAISE EXCEPTION 'Invalid action: %. Must be hide, restore, or dismiss.', p_action;
  END IF;

  -- Determine new status
  IF p_action = 'dismiss' THEN
    v_new_status := 'dismissed';
  ELSE
    v_new_status := 'action_taken';
  END IF;

  -- Fetch the report's target IDs
  SELECT
    reported_post_id, reported_comment_id, reported_message_id,
    reported_ride_id, reported_favor_id
  INTO v_post_id, v_comment_id, v_message_id, v_ride_id, v_favor_id
  FROM public.reports
  WHERE id = p_report_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Report % not found', p_report_id;
  END IF;

  -- Update the report itself
  UPDATE public.reports
  SET
    status      = v_new_status,
    reviewed_at = NOW(),
    reviewed_by = p_admin_id,
    admin_notes = COALESCE(p_admin_notes, admin_notes),
    content_hidden = (p_action = 'hide')
  WHERE id = p_report_id;

  -- For hide/restore, also update all sibling reports on the same target
  -- so the content_hidden flag stays consistent across duplicate reports.
  IF p_action IN ('hide', 'restore') THEN
    UPDATE public.reports
    SET content_hidden = (p_action = 'hide')
    WHERE id <> p_report_id
      AND (
        (v_post_id    IS NOT NULL AND reported_post_id    = v_post_id)    OR
        (v_comment_id IS NOT NULL AND reported_comment_id = v_comment_id) OR
        (v_message_id IS NOT NULL AND reported_message_id = v_message_id) OR
        (v_ride_id    IS NOT NULL AND reported_ride_id    = v_ride_id)    OR
        (v_favor_id   IS NOT NULL AND reported_favor_id   = v_favor_id)
      );
  END IF;
END;
$$;

COMMENT ON FUNCTION public.admin_moderate_content IS
  'Admin action on a report: hide (mark content hidden), restore (un-hide), dismiss. Caller must be admin.';
