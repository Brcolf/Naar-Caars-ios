-- Content moderation redesign foundation
-- - Real hide metadata on moderated content rows
-- - Author-only visibility for hidden content
-- - Audit log for moderation actions
-- - Author-facing hidden-content notifications

ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS hidden_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS hidden_reason TEXT;

ALTER TABLE public.rides
    ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS hidden_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS hidden_reason TEXT;

ALTER TABLE public.favors
    ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS hidden_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS hidden_reason TEXT;

ALTER TABLE public.town_hall_posts
    ADD COLUMN IF NOT EXISTS hidden_reason TEXT;

ALTER TABLE public.town_hall_comments
    ADD COLUMN IF NOT EXISTS hidden_reason TEXT;

CREATE TABLE IF NOT EXISTS public.content_moderation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type TEXT NOT NULL
        CHECK (target_type IN ('message', 'town_hall_post', 'town_hall_comment', 'ride', 'favor')),
    target_id UUID NOT NULL,
    report_id UUID REFERENCES public.reports(id) ON DELETE SET NULL,
    action TEXT NOT NULL
        CHECK (action IN ('hide', 'dismiss', 'restore', 'auto_hide')),
    acted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_content_moderation_events_target
    ON public.content_moderation_events(target_type, target_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_hidden_at
    ON public.messages(hidden_at)
    WHERE hidden_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_rides_hidden_at
    ON public.rides(hidden_at)
    WHERE hidden_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_favors_hidden_at
    ON public.favors(hidden_at)
    WHERE hidden_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.prevent_content_moderation_events_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
    RAISE EXCEPTION 'content_moderation_events is append-only';
END;
$function$;

DROP TRIGGER IF EXISTS content_moderation_events_append_only ON public.content_moderation_events;

CREATE TRIGGER content_moderation_events_append_only
BEFORE UPDATE OR DELETE ON public.content_moderation_events
FOR EACH ROW
EXECUTE FUNCTION public.prevent_content_moderation_events_mutation();

-- Messages: participants can see visible rows; senders can still see their own hidden rows.
DROP POLICY IF EXISTS "messages_select_for_participants" ON public.messages;
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.messages;

CREATE POLICY "Users can view messages in their conversations"
ON public.messages
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.conversation_participants cp
        WHERE cp.conversation_id = messages.conversation_id
          AND cp.user_id = auth.uid()
    )
    AND (
        messages.hidden_at IS NULL
        OR messages.from_id = auth.uid()
    )
);

-- Town Hall posts: approved authenticated users see visible rows; authors can still see their own hidden rows.
DROP POLICY IF EXISTS "Approved users can view town hall posts" ON public.town_hall_posts;
DROP POLICY IF EXISTS "Authenticated users can view visible or own hidden town hall posts" ON public.town_hall_posts;
DROP POLICY IF EXISTS "Guests can view visible town hall posts" ON public.town_hall_posts;
DROP POLICY IF EXISTS "town_hall_posts_select_anon_guest" ON public.town_hall_posts;

CREATE POLICY "Authenticated users can view visible or own hidden town hall posts"
ON public.town_hall_posts
FOR SELECT
TO authenticated
USING (
    (
        hidden_at IS NULL
        AND COALESCE((
            SELECT p.approved
            FROM public.profiles p
            WHERE p.id = auth.uid()
        ), false)
    )
    OR user_id = auth.uid()
);

CREATE POLICY "Guests can view visible town hall posts"
ON public.town_hall_posts
FOR SELECT
TO anon
USING (hidden_at IS NULL);

-- Town Hall comments: authenticated users see visible rows; authors can still see their own hidden rows.
DROP POLICY IF EXISTS "Users can view all comments" ON public.town_hall_comments;
DROP POLICY IF EXISTS "Authenticated users can view visible or own hidden town hall comments" ON public.town_hall_comments;
DROP POLICY IF EXISTS "Guests can view visible town hall comments" ON public.town_hall_comments;
DROP POLICY IF EXISTS "town_hall_comments_select_anon_guest" ON public.town_hall_comments;

CREATE POLICY "Authenticated users can view visible or own hidden town hall comments"
ON public.town_hall_comments
FOR SELECT
TO authenticated
USING (
    hidden_at IS NULL
    OR user_id = auth.uid()
);

CREATE POLICY "Guests can view visible town hall comments"
ON public.town_hall_comments
FOR SELECT
TO anon
USING (hidden_at IS NULL);

-- Rides: authenticated users see visible rows; authors can still see their own hidden rows.
DROP POLICY IF EXISTS "Approved users can view rides" ON public.rides;
DROP POLICY IF EXISTS "Users can view rides" ON public.rides;
DROP POLICY IF EXISTS "Authenticated users can view visible or own hidden rides" ON public.rides;
DROP POLICY IF EXISTS "Guests can view visible rides" ON public.rides;
DROP POLICY IF EXISTS "rides_select_anon_guest" ON public.rides;

CREATE POLICY "Authenticated users can view visible or own hidden rides"
ON public.rides
FOR SELECT
TO authenticated
USING (
    hidden_at IS NULL
    OR user_id = auth.uid()
);

CREATE POLICY "Guests can view visible rides"
ON public.rides
FOR SELECT
TO anon
USING (hidden_at IS NULL);

-- Favors: authenticated users see visible rows; authors can still see their own hidden rows.
DROP POLICY IF EXISTS "Approved users can view favors" ON public.favors;
DROP POLICY IF EXISTS "Users can view favors" ON public.favors;
DROP POLICY IF EXISTS "Authenticated users can view visible or own hidden favors" ON public.favors;
DROP POLICY IF EXISTS "Guests can view visible favors" ON public.favors;
DROP POLICY IF EXISTS "favors_select_anon_guest" ON public.favors;

CREATE POLICY "Authenticated users can view visible or own hidden favors"
ON public.favors
FOR SELECT
TO authenticated
USING (
    hidden_at IS NULL
    OR user_id = auth.uid()
);

CREATE POLICY "Guests can view visible favors"
ON public.favors
FOR SELECT
TO anon
USING (hidden_at IS NULL);

CREATE OR REPLACE FUNCTION public.create_content_hidden_notification(
    p_user_id UUID,
    p_reason TEXT,
    p_conversation_id UUID DEFAULT NULL,
    p_town_hall_post_id UUID DEFAULT NULL,
    p_ride_id UUID DEFAULT NULL,
    p_favor_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_notification_id UUID;
    v_reason TEXT;
    v_body TEXT;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    v_reason := NULLIF(BTRIM(p_reason), '');
    v_body := CASE
        WHEN v_reason IS NULL THEN 'A moderator hid your content.'
        ELSE 'A moderator hid your content: ' || v_reason
    END;

    v_notification_id := public.create_notification(
        p_user_id,
        'content_hidden',
        'Your content was hidden',
        v_body,
        p_ride_id,
        p_favor_id,
        p_conversation_id,
        NULL,
        p_town_hall_post_id,
        NULL
    );

    IF v_notification_id IS NOT NULL THEN
        PERFORM public.queue_push_notification(
            p_user_id,
            'content_hidden',
            'Your content was hidden',
            v_body,
            jsonb_strip_nulls(jsonb_build_object(
                'ride_id', p_ride_id::TEXT,
                'favor_id', p_favor_id::TEXT,
                'conversation_id', p_conversation_id::TEXT,
                'town_hall_post_id', p_town_hall_post_id::TEXT
            )),
            NULL,
            v_notification_id
        );
    END IF;

    RETURN v_notification_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.should_notify_user(
    p_user_id UUID,
    p_notification_type TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    CASE
        WHEN p_notification_type IN ('new_ride', 'new_favor') THEN
            RETURN true;
        WHEN p_notification_type IN ('announcement', 'admin_announcement', 'broadcast') THEN
            RETURN true;
        WHEN p_notification_type IN ('user_approved', 'user_rejected') THEN
            RETURN true;
        WHEN p_notification_type = 'pending_approval' THEN
            RETURN v_profile.is_admin;
        WHEN p_notification_type IN ('message', 'added_to_conversation') THEN
            RETURN v_profile.notify_messages;
        WHEN p_notification_type IN (
            'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
            'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed'
        ) THEN
            RETURN v_profile.notify_ride_updates;
        WHEN p_notification_type IN ('qa_activity', 'qa_question', 'qa_answer') THEN
            RETURN v_profile.notify_qa_activity;
        WHEN p_notification_type IN (
            'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder'
        ) THEN
            RETURN v_profile.notify_review_reminders;
        WHEN p_notification_type IN ('town_hall_post', 'town_hall_comment', 'town_hall_reaction') THEN
            RETURN v_profile.notify_town_hall;
        WHEN p_notification_type = 'content_reported' THEN
            RETURN v_profile.is_admin;
        WHEN p_notification_type = 'content_hidden' THEN
            RETURN true;
        ELSE
            RETURN false;
    END CASE;
END;
$function$;

ALTER TABLE public.reports
    ADD COLUMN IF NOT EXISTS content_hidden BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.content_moderation_events
    DROP CONSTRAINT IF EXISTS content_moderation_events_target_type_check;

ALTER TABLE public.content_moderation_events
    ADD CONSTRAINT content_moderation_events_target_type_check
    CHECK (target_type IN ('message', 'town_hall_post', 'town_hall_comment', 'ride', 'favor', 'user'));

DROP FUNCTION IF EXISTS public.admin_get_reports(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.admin_get_reports(
    p_admin_id UUID,
    p_status TEXT DEFAULT NULL
)
RETURNS TABLE (
    report_id UUID,
    reporter_id UUID,
    reporter_name TEXT,
    reported_user_id UUID,
    reported_user_name TEXT,
    reported_message_id UUID,
    reported_post_id UUID,
    reported_comment_id UUID,
    reported_ride_id UUID,
    reported_favor_id UUID,
    target_type TEXT,
    report_type TEXT,
    description TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    content_preview TEXT,
    content_hidden BOOLEAN,
    report_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_actor_id UUID;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL OR v_actor_id <> p_admin_id THEN
        RAISE EXCEPTION 'Unauthorized: caller mismatch';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = v_actor_id
          AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an admin';
    END IF;

    RETURN QUERY
    WITH enriched AS (
        SELECT
            r.id AS report_id,
            r.reporter_id,
            rp.name AS reporter_name,
            r.reported_user_id,
            ru.name AS reported_user_name,
            r.reported_message_id,
            r.reported_post_id,
            r.reported_comment_id,
            r.reported_ride_id,
            r.reported_favor_id,
            CASE
                WHEN r.reported_message_id IS NOT NULL THEN 'message'
                WHEN r.reported_post_id IS NOT NULL THEN 'town_hall_post'
                WHEN r.reported_comment_id IS NOT NULL THEN 'town_hall_comment'
                WHEN r.reported_ride_id IS NOT NULL THEN 'ride'
                WHEN r.reported_favor_id IS NOT NULL THEN 'favor'
                ELSE 'user'
            END AS target_type,
            COALESCE(
                r.reported_message_id,
                r.reported_post_id,
                r.reported_comment_id,
                r.reported_ride_id,
                r.reported_favor_id,
                r.reported_user_id
            ) AS target_id,
            r.report_type,
            r.description,
            r.status,
            r.created_at,
            r.reviewed_at,
            COALESCE(
                LEFT(msg.text, 200),
                LEFT(post.content, 200),
                LEFT(cmt.content, 200),
                LEFT(CONCAT_WS(' -> ', ride.pickup, ride.destination), 200),
                LEFT(CONCAT_WS(': ', fav.title, NULLIF(fav.description, '')), 200),
                ru.name
            ) AS content_preview,
            CASE
                WHEN r.reported_message_id IS NOT NULL THEN msg.hidden_at IS NOT NULL
                WHEN r.reported_post_id IS NOT NULL THEN post.hidden_at IS NOT NULL
                WHEN r.reported_comment_id IS NOT NULL THEN cmt.hidden_at IS NOT NULL
                WHEN r.reported_ride_id IS NOT NULL THEN ride.hidden_at IS NOT NULL
                WHEN r.reported_favor_id IS NOT NULL THEN fav.hidden_at IS NOT NULL
                ELSE false
            END AS content_hidden
        FROM public.reports r
        LEFT JOIN public.profiles rp
            ON rp.id = r.reporter_id
        LEFT JOIN public.profiles ru
            ON ru.id = r.reported_user_id
        LEFT JOIN public.messages msg
            ON msg.id = r.reported_message_id
        LEFT JOIN public.town_hall_posts post
            ON post.id = r.reported_post_id
        LEFT JOIN public.town_hall_comments cmt
            ON cmt.id = r.reported_comment_id
        LEFT JOIN public.rides ride
            ON ride.id = r.reported_ride_id
        LEFT JOIN public.favors fav
            ON fav.id = r.reported_favor_id
    ),
    grouped AS (
        SELECT
            e.target_type,
            e.target_id,
            COUNT(*)::INT AS dup_count
        FROM enriched e
        GROUP BY e.target_type, e.target_id
    )
    SELECT
        e.report_id,
        e.reporter_id,
        e.reporter_name,
        e.reported_user_id,
        e.reported_user_name,
        e.reported_message_id,
        e.reported_post_id,
        e.reported_comment_id,
        e.reported_ride_id,
        e.reported_favor_id,
        e.target_type,
        e.report_type,
        e.description,
        e.status,
        e.created_at,
        e.reviewed_at,
        e.content_preview,
        e.content_hidden,
        COALESCE(g.dup_count, 1) AS report_count
    FROM enriched e
    LEFT JOIN grouped g
        ON g.target_type = e.target_type
       AND g.target_id = e.target_id
    WHERE p_status IS NULL OR e.status = p_status
    ORDER BY e.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_moderate_content(
    p_admin_id UUID,
    p_report_id UUID,
    p_action TEXT,
    p_admin_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_actor_id UUID;
    v_report public.reports%ROWTYPE;
    v_target_type TEXT;
    v_target_id UUID;
    v_reason TEXT;
    v_author_id UUID;
    v_conversation_id UUID;
    v_town_hall_post_id UUID;
    v_content_hidden BOOLEAN := false;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL OR v_actor_id <> p_admin_id THEN
        RAISE EXCEPTION 'Unauthorized: caller mismatch';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = v_actor_id
          AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an admin';
    END IF;

    IF p_action NOT IN ('hide', 'restore', 'dismiss') THEN
        RAISE EXCEPTION 'Invalid action: %', p_action;
    END IF;

    SELECT *
    INTO v_report
    FROM public.reports
    WHERE id = p_report_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report % not found', p_report_id;
    END IF;

    v_reason := NULLIF(BTRIM(p_admin_notes), '');
    IF p_action = 'hide' AND v_reason IS NULL THEN
        RAISE EXCEPTION 'Hide action requires admin notes';
    END IF;

    v_target_type := CASE
        WHEN v_report.reported_message_id IS NOT NULL THEN 'message'
        WHEN v_report.reported_post_id IS NOT NULL THEN 'town_hall_post'
        WHEN v_report.reported_comment_id IS NOT NULL THEN 'town_hall_comment'
        WHEN v_report.reported_ride_id IS NOT NULL THEN 'ride'
        WHEN v_report.reported_favor_id IS NOT NULL THEN 'favor'
        ELSE 'user'
    END;

    v_target_id := COALESCE(
        v_report.reported_message_id,
        v_report.reported_post_id,
        v_report.reported_comment_id,
        v_report.reported_ride_id,
        v_report.reported_favor_id,
        v_report.reported_user_id
    );

    CASE v_target_type
        WHEN 'message' THEN
            SELECT
                m.from_id,
                m.conversation_id,
                NULL::UUID,
                m.hidden_at IS NOT NULL
            INTO
                v_author_id,
                v_conversation_id,
                v_town_hall_post_id,
                v_content_hidden
            FROM public.messages m
            WHERE m.id = v_target_id;
        WHEN 'town_hall_post' THEN
            SELECT
                p.user_id,
                NULL::UUID,
                p.id,
                p.hidden_at IS NOT NULL
            INTO
                v_author_id,
                v_conversation_id,
                v_town_hall_post_id,
                v_content_hidden
            FROM public.town_hall_posts p
            WHERE p.id = v_target_id;
        WHEN 'town_hall_comment' THEN
            SELECT
                c.user_id,
                NULL::UUID,
                c.post_id,
                c.hidden_at IS NOT NULL
            INTO
                v_author_id,
                v_conversation_id,
                v_town_hall_post_id,
                v_content_hidden
            FROM public.town_hall_comments c
            WHERE c.id = v_target_id;
        WHEN 'ride' THEN
            SELECT
                r.user_id,
                NULL::UUID,
                NULL::UUID,
                r.hidden_at IS NOT NULL
            INTO
                v_author_id,
                v_conversation_id,
                v_town_hall_post_id,
                v_content_hidden
            FROM public.rides r
            WHERE r.id = v_target_id;
        WHEN 'favor' THEN
            SELECT
                f.user_id,
                NULL::UUID,
                NULL::UUID,
                f.hidden_at IS NOT NULL
            INTO
                v_author_id,
                v_conversation_id,
                v_town_hall_post_id,
                v_content_hidden
            FROM public.favors f
            WHERE f.id = v_target_id;
        ELSE
            v_author_id := v_report.reported_user_id;
            v_conversation_id := NULL;
            v_town_hall_post_id := NULL;
            v_content_hidden := COALESCE(v_report.content_hidden, false);
    END CASE;

    IF v_target_type = 'user' AND p_action <> 'dismiss' THEN
        RAISE EXCEPTION 'User reports only support dismiss';
    END IF;

    IF p_action <> 'dismiss' AND v_author_id IS NULL THEN
        RAISE EXCEPTION 'Moderation target % not found', v_target_id;
    END IF;

    IF p_action = 'hide' THEN
        CASE v_target_type
            WHEN 'message' THEN
                UPDATE public.messages
                SET hidden_at = COALESCE(hidden_at, NOW()),
                    hidden_by = v_actor_id,
                    hidden_reason = v_reason
                WHERE id = v_target_id;
            WHEN 'town_hall_post' THEN
                UPDATE public.town_hall_posts
                SET hidden_at = COALESCE(hidden_at, NOW()),
                    hidden_by = v_actor_id,
                    hidden_reason = v_reason
                WHERE id = v_target_id;
            WHEN 'town_hall_comment' THEN
                UPDATE public.town_hall_comments
                SET hidden_at = COALESCE(hidden_at, NOW()),
                    hidden_by = v_actor_id,
                    hidden_reason = v_reason
                WHERE id = v_target_id;
            WHEN 'ride' THEN
                UPDATE public.rides
                SET hidden_at = COALESCE(hidden_at, NOW()),
                    hidden_by = v_actor_id,
                    hidden_reason = v_reason
                WHERE id = v_target_id;
            WHEN 'favor' THEN
                UPDATE public.favors
                SET hidden_at = COALESCE(hidden_at, NOW()),
                    hidden_by = v_actor_id,
                    hidden_reason = v_reason
                WHERE id = v_target_id;
        END CASE;

        UPDATE public.reports
        SET content_hidden = true
        WHERE (
            (v_target_type = 'message' AND reported_message_id = v_target_id)
            OR (v_target_type = 'town_hall_post' AND reported_post_id = v_target_id)
            OR (v_target_type = 'town_hall_comment' AND reported_comment_id = v_target_id)
            OR (v_target_type = 'ride' AND reported_ride_id = v_target_id)
            OR (v_target_type = 'favor' AND reported_favor_id = v_target_id)
        );

        UPDATE public.reports
        SET status = 'action_taken',
            reviewed_at = NOW(),
            reviewed_by = v_actor_id,
            admin_notes = v_reason,
            content_hidden = true
        WHERE (
            (v_target_type = 'message' AND reported_message_id = v_target_id)
            OR (v_target_type = 'town_hall_post' AND reported_post_id = v_target_id)
            OR (v_target_type = 'town_hall_comment' AND reported_comment_id = v_target_id)
            OR (v_target_type = 'ride' AND reported_ride_id = v_target_id)
            OR (v_target_type = 'favor' AND reported_favor_id = v_target_id)
        )
          AND (
              id = v_report.id
              OR status = 'pending'
          );

        INSERT INTO public.content_moderation_events (
            target_type,
            target_id,
            report_id,
            action,
            acted_by,
            reason
        )
        VALUES (
            v_target_type,
            v_target_id,
            v_report.id,
            'hide',
            v_actor_id,
            v_reason
        );

        PERFORM public.create_content_hidden_notification(
            v_author_id,
            v_reason,
            v_conversation_id,
            v_town_hall_post_id,
            CASE WHEN v_target_type = 'ride' THEN v_target_id ELSE NULL END,
            CASE WHEN v_target_type = 'favor' THEN v_target_id ELSE NULL END
        );
    ELSIF p_action = 'restore' THEN
        CASE v_target_type
            WHEN 'message' THEN
                UPDATE public.messages
                SET hidden_at = NULL,
                    hidden_by = NULL,
                    hidden_reason = NULL
                WHERE id = v_target_id;
            WHEN 'town_hall_post' THEN
                UPDATE public.town_hall_posts
                SET hidden_at = NULL,
                    hidden_by = NULL,
                    hidden_reason = NULL
                WHERE id = v_target_id;
            WHEN 'town_hall_comment' THEN
                UPDATE public.town_hall_comments
                SET hidden_at = NULL,
                    hidden_by = NULL,
                    hidden_reason = NULL
                WHERE id = v_target_id;
            WHEN 'ride' THEN
                UPDATE public.rides
                SET hidden_at = NULL,
                    hidden_by = NULL,
                    hidden_reason = NULL
                WHERE id = v_target_id;
            WHEN 'favor' THEN
                UPDATE public.favors
                SET hidden_at = NULL,
                    hidden_by = NULL,
                    hidden_reason = NULL
                WHERE id = v_target_id;
        END CASE;

        UPDATE public.reports
        SET content_hidden = false
        WHERE (
            (v_target_type = 'message' AND reported_message_id = v_target_id)
            OR (v_target_type = 'town_hall_post' AND reported_post_id = v_target_id)
            OR (v_target_type = 'town_hall_comment' AND reported_comment_id = v_target_id)
            OR (v_target_type = 'ride' AND reported_ride_id = v_target_id)
            OR (v_target_type = 'favor' AND reported_favor_id = v_target_id)
        );

        INSERT INTO public.content_moderation_events (
            target_type,
            target_id,
            report_id,
            action,
            acted_by,
            reason
        )
        VALUES (
            v_target_type,
            v_target_id,
            v_report.id,
            'restore',
            v_actor_id,
            v_reason
        );
    ELSE
        UPDATE public.reports
        SET status = 'dismissed',
            reviewed_at = NOW(),
            reviewed_by = v_actor_id,
            admin_notes = COALESCE(v_reason, admin_notes),
            content_hidden = v_content_hidden
        WHERE id = v_report.id;

        INSERT INTO public.content_moderation_events (
            target_type,
            target_id,
            report_id,
            action,
            acted_by,
            reason
        )
        VALUES (
            v_target_type,
            v_target_id,
            v_report.id,
            'dismiss',
            v_actor_id,
            v_reason
        );
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.handle_new_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_report_count INT;
    v_content_preview TEXT;
    v_admin RECORD;
    v_notification_id UUID;
    v_body TEXT;
    v_target_type TEXT;
    v_conversation_id UUID;
    v_town_hall_post_id UUID;
BEGIN
    IF NEW.reported_post_id IS NOT NULL THEN
        v_target_type := 'town_hall_post';

        SELECT COUNT(DISTINCT r.reporter_id)::INT
        INTO v_report_count
        FROM public.reports r
        WHERE r.reported_post_id = NEW.reported_post_id;

        SELECT LEFT(p.content, 80), p.id
        INTO v_content_preview, v_town_hall_post_id
        FROM public.town_hall_posts p
        WHERE p.id = NEW.reported_post_id;

        IF v_report_count >= 3 THEN
            UPDATE public.reports
            SET content_hidden = true
            WHERE reported_post_id = NEW.reported_post_id;

            UPDATE public.town_hall_posts
            SET hidden_at = NOW(),
                hidden_by = NULL,
                hidden_reason = NULL
            WHERE id = NEW.reported_post_id
              AND hidden_at IS NULL;

            IF FOUND THEN
                INSERT INTO public.content_moderation_events (
                    target_type,
                    target_id,
                    report_id,
                    action,
                    acted_by,
                    reason
                )
                VALUES (
                    'town_hall_post',
                    NEW.reported_post_id,
                    NEW.id,
                    'auto_hide',
                    NULL,
                    NULL
                );
            END IF;
        END IF;
    ELSIF NEW.reported_comment_id IS NOT NULL THEN
        v_target_type := 'town_hall_comment';

        SELECT COUNT(DISTINCT r.reporter_id)::INT
        INTO v_report_count
        FROM public.reports r
        WHERE r.reported_comment_id = NEW.reported_comment_id;

        SELECT LEFT(c.content, 80), c.post_id
        INTO v_content_preview, v_town_hall_post_id
        FROM public.town_hall_comments c
        WHERE c.id = NEW.reported_comment_id;

        IF v_report_count >= 3 THEN
            UPDATE public.reports
            SET content_hidden = true
            WHERE reported_comment_id = NEW.reported_comment_id;

            UPDATE public.town_hall_comments
            SET hidden_at = NOW(),
                hidden_by = NULL,
                hidden_reason = NULL
            WHERE id = NEW.reported_comment_id
              AND hidden_at IS NULL;

            IF FOUND THEN
                INSERT INTO public.content_moderation_events (
                    target_type,
                    target_id,
                    report_id,
                    action,
                    acted_by,
                    reason
                )
                VALUES (
                    'town_hall_comment',
                    NEW.reported_comment_id,
                    NEW.id,
                    'auto_hide',
                    NULL,
                    NULL
                );
            END IF;
        END IF;
    ELSIF NEW.reported_message_id IS NOT NULL THEN
        v_target_type := 'message';

        SELECT LEFT(m.text, 80), m.conversation_id
        INTO v_content_preview, v_conversation_id
        FROM public.messages m
        WHERE m.id = NEW.reported_message_id;
    ELSIF NEW.reported_ride_id IS NOT NULL THEN
        v_target_type := 'ride';

        SELECT LEFT(CONCAT_WS(' -> ', r.pickup, r.destination), 80)
        INTO v_content_preview
        FROM public.rides r
        WHERE r.id = NEW.reported_ride_id;
    ELSIF NEW.reported_favor_id IS NOT NULL THEN
        v_target_type := 'favor';

        SELECT LEFT(CONCAT_WS(': ', f.title, NULLIF(f.description, '')), 80)
        INTO v_content_preview
        FROM public.favors f
        WHERE f.id = NEW.reported_favor_id;
    ELSE
        v_target_type := 'user';

        SELECT LEFT(COALESCE(p.name, 'User report'), 80)
        INTO v_content_preview
        FROM public.profiles p
        WHERE p.id = NEW.reported_user_id;
    END IF;

    IF v_content_preview IS NULL THEN
        v_content_preview := 'Reported content';
    END IF;

    v_body := INITCAP(REPLACE(COALESCE(NEW.report_type, 'other'), '_', ' ')) || ': ' || LEFT(v_content_preview, 60);

    FOR v_admin IN
        SELECT p.id
        FROM public.profiles p
        WHERE p.is_admin = true
    LOOP
        v_notification_id := public.create_notification(
            v_admin.id,
            'content_reported',
            'Content Reported',
            v_body,
            NEW.reported_ride_id,
            NEW.reported_favor_id,
            v_conversation_id,
            NULL,
            v_town_hall_post_id,
            NEW.reporter_id
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_admin.id,
                'content_reported',
                'Content Reported',
                v_body,
                jsonb_strip_nulls(jsonb_build_object(
                    'report_id', NEW.id::TEXT,
                    'target_type', v_target_type,
                    'reported_user_id', NEW.reported_user_id::TEXT,
                    'reported_message_id', NEW.reported_message_id::TEXT,
                    'reported_post_id', NEW.reported_post_id::TEXT,
                    'reported_comment_id', NEW.reported_comment_id::TEXT,
                    'reported_ride_id', NEW.reported_ride_id::TEXT,
                    'reported_favor_id', NEW.reported_favor_id::TEXT,
                    'ride_id', NEW.reported_ride_id::TEXT,
                    'favor_id', NEW.reported_favor_id::TEXT,
                    'conversation_id', v_conversation_id::TEXT,
                    'town_hall_post_id', v_town_hall_post_id::TEXT
                )),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS on_report_created ON public.reports;

CREATE TRIGGER on_report_created
AFTER INSERT ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_report();

GRANT EXECUTE ON FUNCTION public.admin_get_reports(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_moderate_content(UUID, UUID, TEXT, TEXT) TO authenticated;
