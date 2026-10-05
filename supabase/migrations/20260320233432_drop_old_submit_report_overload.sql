-- 20260320233432_drop_old_submit_report_overload.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Drop the old submit_report overload that lacks ride/favor params.
-- Two overloads with overlapping default params cause PostgreSQL to fail
-- with "Could not choose the best candidate function" when calling with
-- only the common parameters.
DROP FUNCTION IF EXISTS public.submit_report(
  uuid, uuid, uuid, uuid, uuid, text, text
);
