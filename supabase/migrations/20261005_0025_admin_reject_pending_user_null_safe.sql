-- 20261005_0025_admin_reject_pending_user_null_safe.sql
--
-- APPLIED. Verified live on 2026-10-06: the deployed body is byte-identical to this file, and
-- a rolled-back probe showed a caller with no profile row, and a caller with no JWT subject,
-- both refused with the pending applicant left in place, while a real admin could still reject.
--
-- What it fixed (critical): admin_reject_pending_user() checked the caller with
--     SELECT is_admin INTO v_caller_is_admin FROM profiles WHERE id = v_caller_id;
--     IF NOT v_caller_is_admin THEN RETURN ...
-- When the caller has no profiles row the variable stays NULL, `NOT NULL` is NULL, plpgsql treats
-- a NULL condition as false, and execution falls through to both DELETEs. A signed-in account
-- without a profile row is trivially reachable (sign up through the auth API and never call
-- create_signup_profile), and public_profiles lists pending applicants (approved = false). So
-- any such account could delete every pending applicant's profile and auth.users row, and any
-- auth.users row that had no profile yet. Approved users are protected by the existing check.
--
-- Only the admin check changes; the return shape used by AdminService.rejectUser is unchanged.

CREATE OR REPLACE FUNCTION public.admin_reject_pending_user(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_caller_id UUID;
    v_target_approved BOOLEAN;
    v_rows_deleted INTEGER;
BEGIN
    v_caller_id := auth.uid();

    -- NULL-safe admin check (a caller with no profiles row used to pass).
    IF v_caller_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_caller_id AND is_admin = true
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
    END IF;

    SELECT approved INTO v_target_approved FROM public.profiles WHERE id = p_user_id;
    IF v_target_approved = true THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cannot reject an already approved user');
    END IF;

    DELETE FROM public.profiles WHERE id = p_user_id AND approved = false;
    GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;

    DELETE FROM auth.users WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'deleted_user_id', p_user_id,
        'rows_deleted', v_rows_deleted
    );
END $function$;
