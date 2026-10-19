-- supabase/dryruns/20261019_phase5b_not_applied_check.sql
--
-- READ ONLY. Never applied. Proves that no Phase 5b file (20261019_0060-0063) is applied: run it after every
-- 5b dry run (iOS plan Task 11) and before the 5b gate. Every column must be true; all_unchanged sums them up.
-- false in any column (or an error such as "function ... does not exist") means something was applied: stop
-- and follow the dry-run section of the Phase 5 SQL plan ("If the check is not all true").
-- Expected values read through the Supabase MCP on 2026-10-19.
with c as (
  select
    (select count(*) = 6 and bool_and(b.public) from storage.buckets b
      where b.id in ('message-images', 'group-images', 'town-hall-images', 'review-images', 'audio-messages', 'avatars'))
      as buckets_all_public,
    to_regclass('public.invite_codes') is not null as invite_codes_exists,
    exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace and proname = 'validate_invite_code')
      as validate_invite_code_exists,
    coalesce((select md5(prosrc) = '135aca113be1ebf5281c03c288ee32c6' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.delete_user_account(uuid)')), false) as delete_user_account_unchanged,
    coalesce((select md5(prosrc) = '6241f67fc4e8618ac782b99a7b6d9295' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.fill_request_community()')), false) as fill_request_community_unchanged,
    coalesce((select md5(prosrc) = 'f18e6af6f7ca7a53acd193db115b1f27' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.redeem_community_invite(text, text, text)')), false) as redeem_community_invite_unchanged,
    coalesce((select md5(prosrc) = 'da89c2337d8102d4c284440c534c2b2a' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.request_to_join_community(uuid, text, text)')), false) as request_to_join_community_unchanged,
    coalesce((select md5(prosrc) = '48424e05ea801252b83ed8c893db5f4f' from pg_catalog.pg_proc
               where oid = to_regprocedure('public.protect_admin_fields()')), false) as protect_admin_fields_unchanged,
    (select count(*) = 2 from pg_catalog.pg_trigger where not tgisinternal
      and tgname in ('legacy_application_to_membership', 'a_sync_legacy_approval_to_membership')) as bridges_present,
    coalesce(has_function_privilege('authenticated', to_regprocedure('public.admin_reject_pending_user(uuid)'), 'execute'), false)
      as admin_reject_pending_user_open,
    coalesce(has_function_privilege('authenticated', to_regprocedure('public.send_broadcast_notifications(text, text, text, boolean)'), 'execute'), false)
      as send_broadcast_notifications_open,
    has_table_privilege('authenticated', 'public.geocoding_cache', 'select') as geocoding_cache_readable,
    (select count(*) = 7 from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('Allow public read access on message-images', 'Message image read',
                         'Allow public read access on group-images', 'Anyone can view group images',
                         'Allow public read access on town-hall-images', 'Town hall public read',
                         'Allow public access to review images')) as old_storage_read_policies_present,
    not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('message_images_read_participants', 'group_images_read_participants',
                         'town_hall_images_read_visible', 'review_images_read_visible',
                         'audio_messages_read_participants')) as new_storage_read_policies_absent
)
select c.*,
       (buckets_all_public and invite_codes_exists and validate_invite_code_exists and delete_user_account_unchanged
        and fill_request_community_unchanged and redeem_community_invite_unchanged
        and request_to_join_community_unchanged and protect_admin_fields_unchanged and bridges_present
        and admin_reject_pending_user_open and send_broadcast_notifications_open and geocoding_cache_readable
        and old_storage_read_policies_present and new_storage_read_policies_absent) as all_unchanged
  from c;
