-- 20261005_0022_reports_reporter_privacy.sql
--
-- APPLIED. Verified live on 2026-10-06: no policy on public.reports refers to
-- reported_user_id any more (pg_policies); the remaining SELECT policies are the reporter's
-- own reports and admins.
--
-- "Users can view reports about them" (SELECT, USING auth.uid() = reported_user_id) lets a
-- reported user read reporter_id and description of every report filed against them through
-- GET /rest/v1/reports. That exposes the reporter to retaliation and undermines the reporting
-- pathway. No client code reads public.reports directly (working tree and origin/main); admins
-- read through admin_get_reports(). Reporters keep "Users can view own reports".

drop policy if exists "Users can view reports about them" on public.reports;

-- Optional tidy-up, same reason (both are inert since 20261005_0018 / 0021 revoked the grants):
-- drop policy if exists "Users can create reports" on public.reports;
-- drop policy if exists completion_reminders_update_own on public.completion_reminders;
