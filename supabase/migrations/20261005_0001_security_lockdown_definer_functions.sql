-- 20261005_0001_security_lockdown_definer_functions.sql
--
-- Lock down SECURITY DEFINER functions flagged by the Supabase security advisor
-- (observed 2026-10-05: 45 anon-executable / 75 authenticated-executable definer functions).
--
-- Principles:
--   * Trigger functions and internal helpers are never callable over the REST RPC surface.
--   * RPCs that act on behalf of a user verify auth.uid() themselves.
--   * anon keeps EXECUTE only on what guest mode and signup genuinely need
--     (validate_invite_code, leaderboard/stat getters, RLS helper predicates).
--   * service_role keeps its explicit grants (edge functions and cron use it).


-- ---------------------------------------------------------------------------
-- 1. Neutralise the legacy unguarded signup helper.
--    It was anon-callable and its ON CONFLICT DO UPDATE let any caller overwrite
--    any user's name / email / car given their id. The client uses
--    create_signup_profile(), which checks auth.uid(). EXECUTE is revoked from
--    every API role; the function can be dropped from the SQL editor at leisure:
--      drop function public.upsert_profile_for_signup(uuid, text, text, text, uuid);
-- ---------------------------------------------------------------------------
revoke execute on function public.upsert_profile_for_signup(uuid, text, text, text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2./3. send_approval_notification and the typing-status RPCs: anon EXECUTE revoked
--    here. The caller guards (CREATE OR REPLACE bodies) live in
--    20261005_0004_function_caller_guards.sql, which must be run from the SQL
--    editor because the MCP tool holds CREATE OR REPLACE for interactive confirmation.
-- ---------------------------------------------------------------------------
revoke execute on function public.send_approval_notification(uuid) from public, anon;
revoke execute on function public.set_typing_status(uuid, uuid)   from public, anon;
revoke execute on function public.clear_typing_status(uuid, uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- 4. Internal-only functions: never callable through /rest/v1/rpc.
--    Trigger functions run with the table owner's rights regardless of the
--    caller's EXECUTE privilege, and the helpers below are only invoked from
--    other SECURITY DEFINER functions, cron, or edge functions (service_role).
-- ---------------------------------------------------------------------------
revoke execute on function public.create_content_hidden_notification(uuid, text, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.cleanup_stale_push_tokens()        from public, anon, authenticated;
revoke execute on function public.cleanup_stale_typing_indicators()  from public, anon, authenticated;
revoke execute on function public.process_batched_notifications()    from public, anon, authenticated;
revoke execute on function public.should_notify_user(uuid, text)     from public, anon;

revoke execute on function public.handle_new_report()                from public, anon, authenticated;
revoke execute on function public.handle_new_review()                from public, anon, authenticated;
revoke execute on function public.notify_added_to_conversation()     from public, anon, authenticated;
revoke execute on function public.notify_favor_status_change()       from public, anon, authenticated;
revoke execute on function public.notify_new_favor()                 from public, anon, authenticated;
revoke execute on function public.notify_new_ride()                  from public, anon, authenticated;
revoke execute on function public.notify_pending_user()              from public, anon, authenticated;
revoke execute on function public.notify_qa_activity()               from public, anon, authenticated;
revoke execute on function public.notify_qa_answer()                 from public, anon, authenticated;
revoke execute on function public.notify_ride_status_change()        from public, anon, authenticated;
revoke execute on function public.notify_town_hall_comment()         from public, anon, authenticated;
revoke execute on function public.notify_town_hall_post()            from public, anon, authenticated;
revoke execute on function public.notify_town_hall_vote()            from public, anon, authenticated;
revoke execute on function public.notify_user_approved()             from public, anon, authenticated;
revoke execute on function public.process_immediate_notification()   from public, anon, authenticated;
revoke execute on function public.record_xp_on_completion()          from public, anon, authenticated;
revoke execute on function public.record_xp_on_request_created()     from public, anon, authenticated;
revoke execute on function public.record_xp_on_review()              from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Authenticated-only RPCs: anon has no legitimate use for these.
--    (Each already checks auth.uid() internally; this removes the attack surface.)
-- ---------------------------------------------------------------------------
revoke execute on function public.edit_message(uuid, text)                                              from public, anon;
revoke execute on function public.unsend_message(uuid)                                                  from public, anon;
revoke execute on function public.leave_conversation(uuid, uuid)                                        from public, anon;
revoke execute on function public.submit_report(uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text)   from public, anon;
revoke execute on function public.get_badge_counts(boolean, uuid)                                       from public, anon;
revoke execute on function public.get_user_savings(text)                                                from public, anon;
revoke execute on function public.get_user_total_savings()                                              from public, anon;
revoke execute on function public.get_user_total_xp()                                                   from public, anon;
revoke execute on function public.get_user_xp_events()                                                  from public, anon;
revoke execute on function public.is_user_approved(uuid)                                                from public, anon;

-- Kept anon-callable on purpose (guest mode / signup / RLS predicates):
--   validate_invite_code, get_leaderboard, get_leaderboard_spotlights, get_xp_leaderboard,
--   get_user_badges, get_user_stats, is_active_user, is_conversation_participant.

-- ---------------------------------------------------------------------------
-- 6. search_path hardening for the one remaining mutable-search_path function.
-- ---------------------------------------------------------------------------
alter function public.get_reply_counts(uuid, uuid[]) set search_path = public;
