-- 20260717200109_20260717_0002_revoke_public_execute_messaging_rpcs.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Complete the anon lockdown: the EXECUTE grant was held via PUBLIC (inherited by anon),
-- not an explicit anon grant. Grant authenticated/service_role explicitly, then revoke PUBLIC.
-- Matches the hardened ACL shape of delete_user_account ({authenticated=X, service_role=X}).

DO $$
DECLARE
  fn text;
  fns text[] := ARRAY[
    'public.get_conversations_with_details(uuid,integer,integer)',
    'public.send_reply_message(uuid,uuid,text,uuid,text)',
    'public.remove_conversation_participant(uuid,uuid,uuid)',
    'public.mark_messages_read(uuid,uuid)',
    'public.mark_messages_read_batch(uuid[],uuid)',
    'public.get_unread_counts(uuid)',
    'public.get_pending_reviews(uuid)',
    'public.get_or_create_request_conversation(uuid,uuid,uuid)',
    'public.find_dm_conversation(uuid,uuid)'
  ];
BEGIN
  FOREACH fn IN ARRAY fns LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role;', fn);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon;', fn);
  END LOOP;
END $$;
