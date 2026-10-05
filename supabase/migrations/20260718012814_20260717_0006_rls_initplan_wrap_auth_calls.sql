-- 20260718012814_20260717_0006_rls_initplan_wrap_auth_calls.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- PERF-1: wrap auth.uid()/auth.role()/auth.jwt()/auth.email() in scalar subqueries so
-- Postgres evaluates them once per query (initplan) instead of once per row. Purely a
-- performance optimization — the boolean logic of every policy is identical. Atomic:
-- any malformed ALTER rolls the whole migration back. Only rewrites still-unwrapped policies.
DO $$
DECLARE
  r RECORD;
  v_stmt TEXT;
  v_qual TEXT;
  v_check TEXT;
  v_count INT := 0;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (qual ~ 'auth\.(uid|role|jwt|email)\(\)' OR with_check ~ 'auth\.(uid|role|jwt|email)\(\)')
      AND coalesce(qual, '')       !~ '\(\s*select\s+auth\.'
      AND coalesce(with_check, '') !~ '\(\s*select\s+auth\.'
  LOOP
    v_stmt := format('ALTER POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);

    IF r.qual IS NOT NULL THEN
      v_qual := regexp_replace(regexp_replace(regexp_replace(regexp_replace(
        r.qual, 'auth\.uid\(\)',  '(select auth.uid())',  'g'),
                'auth\.role\(\)', '(select auth.role())', 'g'),
                'auth\.jwt\(\)',  '(select auth.jwt())',  'g'),
                'auth\.email\(\)','(select auth.email())','g');
      v_stmt := v_stmt || format(' USING (%s)', v_qual);
    END IF;

    IF r.with_check IS NOT NULL THEN
      v_check := regexp_replace(regexp_replace(regexp_replace(regexp_replace(
        r.with_check, 'auth\.uid\(\)',  '(select auth.uid())',  'g'),
                      'auth\.role\(\)', '(select auth.role())', 'g'),
                      'auth\.jwt\(\)',  '(select auth.jwt())',  'g'),
                      'auth\.email\(\)','(select auth.email())','g');
      v_stmt := v_stmt || format(' WITH CHECK (%s)', v_check);
    END IF;

    EXECUTE v_stmt;
    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE 'Rewrote % RLS policies for initplan optimization', v_count;
END $$;
