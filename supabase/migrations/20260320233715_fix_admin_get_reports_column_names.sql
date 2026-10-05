-- 20260320233715_fix_admin_get_reports_column_names.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Fix admin_get_reports: correct column names for content preview.
-- messages.text (not content), rides.pickup/destination (not pickup_address/destination_address)
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
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_admin_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Unauthorized: caller is not an admin';
  END IF;

  RETURN QUERY
  WITH grouped AS (
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
    COALESCE(
      LEFT(msg.text, 200),
      LEFT(post.content, 200),
      LEFT(cmt.content, 200),
      LEFT(ride.pickup || ' → ' || ride.destination, 200),
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
