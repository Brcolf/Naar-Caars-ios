-- 20261005_0020_rls_helpers_answer_only_for_caller.sql
--
-- APPLIED 2026-10-05 (Supabase MCP, one function per call) and verified with a rolled-back probe.
--
-- Three SECURITY DEFINER RLS helpers answered for ANY user id through /rest/v1/rpc:
--   * is_active_user(uuid)  - callable by anon: a false result for a publicly "approved" member
--     revealed that the member is banned;
--   * is_admin_user(uuid)   - let any signed-in account enumerate the admins;
--   * is_conversation_participant(uuid, uuid) - callable by anon: membership oracle for any
--     (conversation, user) pair.
-- Every consumer passes the caller's own id: the *_insert_active_user policies and the messages
-- INSERT policy, profiles_select_admin / profiles_update_admin / moderation_events_select_admin,
-- send_approval_notification, protect_admin_fields_on_insert, send_reply_message, and the
-- conversation_participants SELECT policy (checked in pg_policies across all schemas and in
-- pg_proc). Each helper now answers only when its argument equals auth.uid() and returns false
-- otherwise, so policy results are unchanged.
--
-- is_conversation_participant keeps no left_at filter on purpose (the client reads its own left
-- rows to bound message history) and loses its PUBLIC/anon grant (its only policy is TO
-- authenticated). is_active_user keeps its grants so an anonymous insert still fails as an RLS
-- violation rather than a function permission error.
--
-- Server-side code that needs another user's status must query the tables directly.
--
-- Probe (begin/rollback): an admin still sees all 19 profiles and a non-admin exactly 1; a member
-- sees the same 111 participant rows as before, 45 conversations, and can send; each helper is
-- true for the caller's own id and false for another user's; anon gets false / permission
-- denied; public_profiles stays readable for guests.

CREATE OR REPLACE FUNCTION public.is_active_user(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Answers only for the calling user. Every policy passes (select auth.uid()); for anon or any
  -- other id the result is false, so it can no longer be used to find out who is banned.
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_user_id
      AND p_user_id = (SELECT auth.uid())
      AND p.approved = true
      AND p.is_banned = false
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_admin_user(user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Answers only for the calling user (all policies and functions pass auth.uid()); it used to
  -- let any signed-in account enumerate the admins.
  IF user_id IS NULL OR user_id IS DISTINCT FROM auth.uid() THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = user_id
    AND is_admin = true
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_conversation_participant(conv_id uuid, check_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- RLS helper for the conversation_participants SELECT policy. Answers only for the calling
  -- user. Deliberately no left_at filter: the client reads its own left rows to bound history.
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_participants
    WHERE conversation_id = conv_id
      AND user_id = check_user_id
      AND check_user_id = (SELECT auth.uid())
  );
$function$;

revoke execute on function public.is_conversation_participant(uuid, uuid) from public, anon;
grant execute on function public.is_conversation_participant(uuid, uuid) to authenticated, service_role;
