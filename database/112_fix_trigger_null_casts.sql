-- Migration 112: Fix type casts in profile triggers
-- PostgreSQL cannot resolve overloaded functions when positional arguments
-- are untyped NULLs or string literals (type 'unknown').
-- All arguments must be explicitly cast to match the function signature.

CREATE OR REPLACE FUNCTION notify_user_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_notification_id UUID;
BEGIN
    IF OLD.approved = false AND NEW.approved = true THEN
        v_notification_id := create_notification(
            NEW.id,
            'user_approved'::TEXT,
            'Welcome to Naar''s Cars!'::TEXT,
            'Your account has been approved. Tap to enter the app.'::TEXT,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                NEW.id,
                'user_approved'::TEXT,
                'Welcome to Naar''s Cars!'::TEXT,
                'Your account has been approved. Tap to enter the app.'::TEXT,
                jsonb_build_object('action', 'enter_app'),
                NULL::TEXT,
                v_notification_id
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION notify_pending_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_id UUID;
    v_user_name TEXT;
    v_notification_id UUID;
BEGIN
    IF NEW.approved = true THEN
        RETURN NEW;
    END IF;

    v_user_name := COALESCE(NEW.name, NEW.email);

    FOR v_admin_id IN
        SELECT id FROM public.profiles WHERE is_admin = true AND approved = true
    LOOP
        v_notification_id := public.create_notification(
            v_admin_id,
            'pending_approval'::TEXT,
            'New User Pending Approval'::TEXT,
            (v_user_name || ' is waiting for approval')::TEXT,
            NULL::UUID, NULL::UUID, NULL::UUID, NULL::UUID, NULL::UUID, NEW.id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_admin_id,
                'pending_approval'::TEXT,
                'New User Pending Approval'::TEXT,
                (v_user_name || ' is waiting for approval')::TEXT,
                jsonb_build_object('user_id', NEW.id::text),
                NULL::TEXT,
                v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;
