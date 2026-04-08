# Content Moderation Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement real, reversible moderation for reported content so `Hide` affects the underlying content, authors see placeholders plus reasons, admins can reverse decisions safely, and all supported UGC surfaces behave consistently.

**Architecture:** Use content-row moderation fields (`hidden_at`, `hidden_by`, `hidden_reason`) as the source of truth, keep `reports` as the user-submission workflow record, and add an append-only `content_moderation_events` audit log. Server-side SQL enforces visibility rules and notification delivery; Swift models, SwiftData, and UI render author-only placeholders and reversible admin controls.

**Tech Stack:** PostgreSQL (Supabase migrations + RPCs + RLS), TypeScript (shared notification registry), Swift (SwiftUI, UIKit messaging, SwiftData)

**Constraints:** Do **not** add new automated tests unless the user explicitly asks. Verification for this plan is build + script validation + manual end-to-end moderation checks.

**Live DB verification date:** 2026-04-03 via Supabase MCP (`execute_sql` against `pg_proc`, `information_schema.columns`, and `pg_policies`)

---

## Live Findings That Shape This Plan

| Item | Repo / UI implied | Live reality | Plan impact |
|---|---|---|---|
| `admin_moderate_content` | Hide should affect content | RPC only updates `reports` metadata and `content_hidden` | Replace RPC so it updates target rows and writes audit events |
| Auto-hide | Broad moderation system | Only Town Hall post/comment auto-hide exists | Keep auto-hide limited to Town Hall in v1 |
| Author moderation notice | Expected by product | No `content_hidden` notification exists | Add new notification type and author delivery |
| Message moderation visibility | No real behavior | `messages` only support `deleted_at`, no moderation fields | Add hidden moderation fields and sender-only placeholder rendering |
| Report queue reversibility | UI looks one-way | Current UI only presents actions for pending rows | Change admin action availability to depend on content state, not just report status |
| Notification registry | Swift enum includes `content_reported` | `NotificationTypeRegistry.swift` is missing it | Fix registry drift while adding `content_hidden` |

---

## File Structure

### Server contract
- Create: `supabase/migrations/20260403_0011_content_moderation_redesign.sql`
- Modify: `supabase/functions/_shared/notificationTypes.ts`

### Shared Swift models / storage
- Modify: `NaarsCars/Core/Models/AppNotification.swift`
- Modify: `NaarsCars/Core/Models/NotificationTypeRegistry.swift`
- Modify: `NaarsCars/Core/Models/Message.swift`
- Modify: `NaarsCars/Core/Models/Ride.swift`
- Modify: `NaarsCars/Core/Models/Favor.swift`
- Modify: `NaarsCars/Core/Models/TownHallPost.swift`
- Modify: `NaarsCars/Core/Models/TownHallComment.swift`
- Modify: `NaarsCars/Core/Storage/SDModels.swift`
- Modify: `NaarsCars/Core/Storage/MessagingMapper.swift`
- Modify: `NaarsCars/Core/Storage/BackgroundSyncActor.swift`

### Admin moderation UI
- Modify: `NaarsCars/Core/Services/AdminModerationService.swift`
- Modify: `NaarsCars/Features/Admin/Views/AdminReportsView.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

### Messaging
- Create: `NaarsCars/UI/Components/Messaging/Cells/ModerationHiddenMessageView.swift`
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift`
- Modify: `NaarsCars/Core/Services/MessageService.swift`

### Town Hall + requests
- Modify: `NaarsCars/Core/Services/TownHallService.swift`
- Modify: `NaarsCars/Core/Services/TownHallCommentService.swift`
- Modify: `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift`
- Modify: `NaarsCars/Features/TownHall/Views/PostCommentsView.swift`
- Modify: `NaarsCars/Core/Services/RideService.swift`
- Modify: `NaarsCars/Core/Services/FavorService.swift`
- Modify: `NaarsCars/UI/Components/Cards/RideCard.swift`
- Modify: `NaarsCars/UI/Components/Cards/FavorCard.swift`
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift`
- Modify: `NaarsCars/Features/Favors/Views/FavorDetailView.swift`

### Routing / validation
- Modify: `NaarsCars/Core/Utilities/DeepLinkParser.swift`
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationNavigationRouter.swift`
- Modify: `scripts/validate-notification-types.sh`

---

## Task 1: Create The Moderation Schema And Audit Log

**Files:**
- Create: `supabase/migrations/20260403_0011_content_moderation_redesign.sql`

**Why this is safe:** It is additive schema work plus replacement of RPCs/triggers that are already dedicated to moderation. No existing user-facing path depends on the current broken `admin_moderate_content` behavior.

- [ ] **Step 1: Write the moderation columns and audit table**

```sql
-- Content moderation redesign
-- - Real hide/restore semantics on content rows
-- - Author-facing hide notification support
-- - Append-only moderation event log

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
    target_type TEXT NOT NULL CHECK (target_type IN ('message', 'town_hall_post', 'town_hall_comment', 'ride', 'favor')),
    target_id UUID NOT NULL,
    report_id UUID REFERENCES public.reports(id) ON DELETE SET NULL,
    action TEXT NOT NULL CHECK (action IN ('hide', 'dismiss', 'restore', 'auto_hide')),
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
```

- [ ] **Step 2: Replace read policies so hidden rows are author-only**

```sql
-- Messages: participants see visible rows; sender can still see their own hidden rows.
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

-- Town Hall posts: visible to approved users and guests; hidden only to author.
DROP POLICY IF EXISTS "Approved users can view town hall posts" ON public.town_hall_posts;
DROP POLICY IF EXISTS town_hall_posts_select_anon_guest ON public.town_hall_posts;

CREATE POLICY "Authenticated users can view visible or own hidden town hall posts"
ON public.town_hall_posts
FOR SELECT
TO authenticated
USING (
    ((hidden_at IS NULL) AND COALESCE((SELECT approved FROM public.profiles WHERE id = auth.uid()), false))
    OR (user_id = auth.uid())
);

CREATE POLICY "Guests can view visible town hall posts"
ON public.town_hall_posts
FOR SELECT
TO anon
USING (hidden_at IS NULL);

-- Town Hall comments: visible to all signed-in users and guests; hidden only to author.
DROP POLICY IF EXISTS "Users can view all comments" ON public.town_hall_comments;
DROP POLICY IF EXISTS town_hall_comments_select_anon_guest ON public.town_hall_comments;

CREATE POLICY "Authenticated users can view visible or own hidden town hall comments"
ON public.town_hall_comments
FOR SELECT
TO authenticated
USING ((hidden_at IS NULL) OR (user_id = auth.uid()));

CREATE POLICY "Guests can view visible town hall comments"
ON public.town_hall_comments
FOR SELECT
TO anon
USING (hidden_at IS NULL);

-- Rides
DROP POLICY IF EXISTS "Approved users can view rides" ON public.rides;
DROP POLICY IF EXISTS "Users can view rides" ON public.rides;
DROP POLICY IF EXISTS rides_select_anon_guest ON public.rides;

CREATE POLICY "Authenticated users can view visible or own hidden rides"
ON public.rides
FOR SELECT
TO authenticated
USING ((hidden_at IS NULL) OR (user_id = auth.uid()));

CREATE POLICY "Guests can view visible rides"
ON public.rides
FOR SELECT
TO anon
USING (hidden_at IS NULL);

-- Favors
DROP POLICY IF EXISTS "Approved users can view favors" ON public.favors;
DROP POLICY IF EXISTS "Users can view favors" ON public.favors;
DROP POLICY IF EXISTS favors_select_anon_guest ON public.favors;

CREATE POLICY "Authenticated users can view visible or own hidden favors"
ON public.favors
FOR SELECT
TO authenticated
USING ((hidden_at IS NULL) OR (user_id = auth.uid()));

CREATE POLICY "Guests can view visible favors"
ON public.favors
FOR SELECT
TO anon
USING (hidden_at IS NULL);
```

- [ ] **Step 3: Add the author-facing notification helper and `should_notify_user` support**

```sql
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
SET search_path TO 'public'
AS $$
DECLARE
    v_notification_id UUID;
    v_body TEXT;
BEGIN
    v_body := CASE
        WHEN COALESCE(TRIM(p_reason), '') = '' THEN 'A moderator hid your content.'
        ELSE 'A moderator hid your content: ' || p_reason
    END;

    v_notification_id := create_notification(
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
        PERFORM queue_push_notification(
            p_user_id,
            'content_hidden',
            'Your content was hidden',
            v_body,
            jsonb_strip_nulls(jsonb_build_object(
                'ride_id', p_ride_id,
                'favor_id', p_favor_id,
                'conversation_id', p_conversation_id,
                'town_hall_post_id', p_town_hall_post_id
            )),
            NULL,
            v_notification_id
        );
    END IF;

    RETURN v_notification_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.should_notify_user(
    p_user_id UUID,
    p_notification_type TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT * INTO v_profile
    FROM public.profiles
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    IF p_notification_type = 'content_reported' THEN
        RETURN v_profile.is_admin;
    END IF;

    IF p_notification_type = 'content_hidden' THEN
        RETURN TRUE;
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
        ELSE
            RETURN false;
    END CASE;
END;
$$;
```

- [ ] **Step 4: Apply the migration via Supabase MCP and verify the new columns exist**

Verify with:

```sql
select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and table_name in ('messages','rides','favors','town_hall_posts','town_hall_comments')
  and column_name in ('hidden_at','hidden_by','hidden_reason')
order by table_name, column_name;
```

Expected: rows for all five tables, with `hidden_reason` present on each and `hidden_at` / `hidden_by` present on all moderated tables.

---

## Task 2: Replace The Moderation RPCs And Report Trigger

**Files:**
- Modify: `supabase/migrations/20260403_0011_content_moderation_redesign.sql`

**Why this is safe:** These functions are already admin/report specific. Replacing them corrects behavior without changing non-moderation request flows.

- [ ] **Step 1: Expand `admin_get_reports` so the app can reason about every target type**

```sql
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
SET search_path TO 'public'
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_admin_id AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an admin';
    END IF;

    RETURN QUERY
    WITH grouped AS (
        SELECT
            COALESCE(r.reported_message_id, r.reported_post_id, r.reported_comment_id,
                     r.reported_ride_id, r.reported_favor_id, r.reported_user_id) AS target_key,
            count(*)::INT AS dup_count
        FROM public.reports r
        GROUP BY target_key
    )
    SELECT
        r.id,
        r.reporter_id,
        rp.name,
        r.reported_user_id,
        ru.name,
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
        r.report_type,
        r.description,
        r.status,
        r.created_at,
        r.reviewed_at,
        COALESCE(
            LEFT(msg.text, 200),
            LEFT(post.content, 200),
            LEFT(cmt.content, 200),
            LEFT(ride.pickup || ' → ' || ride.destination, 200),
            LEFT(fav.title || ': ' || COALESCE(fav.description, ''), 200),
            ru.name
        ) AS content_preview,
        CASE
            WHEN r.reported_message_id IS NOT NULL THEN msg.hidden_at IS NOT NULL
            WHEN r.reported_post_id IS NOT NULL THEN post.hidden_at IS NOT NULL
            WHEN r.reported_comment_id IS NOT NULL THEN cmt.hidden_at IS NOT NULL
            WHEN r.reported_ride_id IS NOT NULL THEN ride.hidden_at IS NOT NULL
            WHEN r.reported_favor_id IS NOT NULL THEN fav.hidden_at IS NOT NULL
            ELSE false
        END AS content_hidden,
        COALESCE(g.dup_count, 1)
    FROM public.reports r
    LEFT JOIN public.profiles rp ON rp.id = r.reporter_id
    LEFT JOIN public.profiles ru ON ru.id = r.reported_user_id
    LEFT JOIN public.messages msg ON msg.id = r.reported_message_id
    LEFT JOIN public.town_hall_posts post ON post.id = r.reported_post_id
    LEFT JOIN public.town_hall_comments cmt ON cmt.id = r.reported_comment_id
    LEFT JOIN public.rides ride ON ride.id = r.reported_ride_id
    LEFT JOIN public.favors fav ON fav.id = r.reported_favor_id
    LEFT JOIN grouped g ON g.target_key = COALESCE(
        r.reported_message_id, r.reported_post_id, r.reported_comment_id,
        r.reported_ride_id, r.reported_favor_id, r.reported_user_id
    )
    WHERE (p_status IS NULL OR r.status = p_status)
    ORDER BY r.created_at DESC;
END;
$$;
```

- [ ] **Step 2: Replace `admin_moderate_content` so it hides/restores real content and writes audit rows**

```sql
CREATE OR REPLACE FUNCTION public.admin_moderate_content(
    p_admin_id UUID,
    p_report_id UUID,
    p_action TEXT,
    p_admin_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_report public.reports%ROWTYPE;
    v_target_type TEXT;
    v_reason TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_admin_id AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an admin';
    END IF;

    IF p_action NOT IN ('hide', 'restore', 'dismiss') THEN
        RAISE EXCEPTION 'Invalid action: %', p_action;
    END IF;

    SELECT * INTO v_report
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

    IF p_action = 'hide' THEN
        UPDATE public.reports
        SET status = 'action_taken',
            reviewed_at = NOW(),
            reviewed_by = p_admin_id,
            admin_notes = v_reason,
            content_hidden = true
        WHERE (
            (v_report.reported_message_id IS NOT NULL AND reported_message_id = v_report.reported_message_id) OR
            (v_report.reported_post_id IS NOT NULL AND reported_post_id = v_report.reported_post_id) OR
            (v_report.reported_comment_id IS NOT NULL AND reported_comment_id = v_report.reported_comment_id) OR
            (v_report.reported_ride_id IS NOT NULL AND reported_ride_id = v_report.reported_ride_id) OR
            (v_report.reported_favor_id IS NOT NULL AND reported_favor_id = v_report.reported_favor_id)
        )
          AND (
              id = v_report.id
              OR status <> 'dismissed'
          );

        UPDATE public.messages
        SET hidden_at = NOW(), hidden_by = p_admin_id, hidden_reason = v_reason
        WHERE id = v_report.reported_message_id;

        UPDATE public.town_hall_posts
        SET hidden_at = NOW(), hidden_by = p_admin_id, hidden_reason = v_reason
        WHERE id = v_report.reported_post_id;

        UPDATE public.town_hall_comments
        SET hidden_at = NOW(), hidden_by = p_admin_id, hidden_reason = v_reason
        WHERE id = v_report.reported_comment_id;

        UPDATE public.rides
        SET hidden_at = NOW(), hidden_by = p_admin_id, hidden_reason = v_reason
        WHERE id = v_report.reported_ride_id;

        UPDATE public.favors
        SET hidden_at = NOW(), hidden_by = p_admin_id, hidden_reason = v_reason
        WHERE id = v_report.reported_favor_id;

        INSERT INTO public.content_moderation_events(target_type, target_id, report_id, action, acted_by, reason)
        VALUES (
            v_target_type,
            COALESCE(v_report.reported_message_id, v_report.reported_post_id, v_report.reported_comment_id, v_report.reported_ride_id, v_report.reported_favor_id),
            v_report.id,
            'hide',
            p_admin_id,
            v_reason
        );

        PERFORM public.create_content_hidden_notification(
            COALESCE(v_report.reported_user_id, (
                SELECT from_id FROM public.messages WHERE id = v_report.reported_message_id
            )),
            v_reason,
            (SELECT conversation_id FROM public.messages WHERE id = v_report.reported_message_id),
            COALESCE(
                v_report.reported_post_id,
                (SELECT post_id FROM public.town_hall_comments WHERE id = v_report.reported_comment_id)
            ),
            v_report.reported_ride_id,
            v_report.reported_favor_id
        );
    ELSIF p_action = 'restore' THEN
        UPDATE public.messages
        SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL
        WHERE id = v_report.reported_message_id;

        UPDATE public.town_hall_posts
        SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL
        WHERE id = v_report.reported_post_id;

        UPDATE public.town_hall_comments
        SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL
        WHERE id = v_report.reported_comment_id;

        UPDATE public.rides
        SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL
        WHERE id = v_report.reported_ride_id;

        UPDATE public.favors
        SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL
        WHERE id = v_report.reported_favor_id;

        INSERT INTO public.content_moderation_events(target_type, target_id, report_id, action, acted_by, reason)
        VALUES (
            v_target_type,
            COALESCE(v_report.reported_message_id, v_report.reported_post_id, v_report.reported_comment_id, v_report.reported_ride_id, v_report.reported_favor_id),
            v_report.id,
            'restore',
            p_admin_id,
            v_reason
        );
    ELSE
        UPDATE public.reports
        SET status = 'dismissed',
            reviewed_at = NOW(),
            reviewed_by = p_admin_id,
            admin_notes = COALESCE(v_reason, admin_notes)
        WHERE id = v_report.id;

        INSERT INTO public.content_moderation_events(target_type, target_id, report_id, action, acted_by, reason)
        VALUES (
            v_target_type,
            COALESCE(v_report.reported_message_id, v_report.reported_post_id, v_report.reported_comment_id, v_report.reported_ride_id, v_report.reported_favor_id),
            v_report.id,
            'dismiss',
            p_admin_id,
            v_reason
        );
    END IF;
END;
$$;
```

- [ ] **Step 3: Update `handle_new_report` so auto-hide writes audit history but does not author-notify**

```sql
CREATE OR REPLACE FUNCTION public.handle_new_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_report_count INT;
    v_content_preview TEXT;
    v_admin RECORD;
    v_notification_id UUID;
    v_body TEXT;
BEGIN
    IF NEW.reported_post_id IS NOT NULL THEN
        SELECT COUNT(DISTINCT reporter_id) INTO v_report_count
        FROM public.reports
        WHERE reported_post_id = NEW.reported_post_id;

        SELECT LEFT(content, 80) INTO v_content_preview
        FROM public.town_hall_posts
        WHERE id = NEW.reported_post_id;

        IF v_report_count >= 3 THEN
            UPDATE public.town_hall_posts
            SET hidden_at = NOW(), hidden_by = NULL, hidden_reason = NULL
            WHERE id = NEW.reported_post_id AND hidden_at IS NULL;

            INSERT INTO public.content_moderation_events(target_type, target_id, report_id, action, acted_by, reason)
            VALUES ('town_hall_post', NEW.reported_post_id, NEW.id, 'auto_hide', NULL, NULL);
        END IF;
    END IF;

    IF NEW.reported_comment_id IS NOT NULL THEN
        SELECT COUNT(DISTINCT reporter_id) INTO v_report_count
        FROM public.reports
        WHERE reported_comment_id = NEW.reported_comment_id;

        SELECT LEFT(content, 80) INTO v_content_preview
        FROM public.town_hall_comments
        WHERE id = NEW.reported_comment_id;

        IF v_report_count >= 3 THEN
            UPDATE public.town_hall_comments
            SET hidden_at = NOW(), hidden_by = NULL, hidden_reason = NULL
            WHERE id = NEW.reported_comment_id AND hidden_at IS NULL;

            INSERT INTO public.content_moderation_events(target_type, target_id, report_id, action, acted_by, reason)
            VALUES ('town_hall_comment', NEW.reported_comment_id, NEW.id, 'auto_hide', NULL, NULL);
        END IF;
    END IF;

    IF v_content_preview IS NULL THEN
        v_content_preview := 'User or message report';
    END IF;

    v_body := INITCAP(REPLACE(NEW.report_type, '_', ' ')) || ': ' || LEFT(v_content_preview, 60);

    FOR v_admin IN SELECT id FROM public.profiles WHERE is_admin = true
    LOOP
        v_notification_id := create_notification(
            v_admin.id,
            'content_reported',
            'Content Reported',
            v_body,
            NEW.reported_ride_id,
            NEW.reported_favor_id,
            (SELECT conversation_id FROM public.messages WHERE id = NEW.reported_message_id),
            NULL,
            COALESCE(NEW.reported_post_id, (SELECT post_id FROM public.town_hall_comments WHERE id = NEW.reported_comment_id)),
            NEW.reporter_id
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_admin.id,
                'content_reported',
                'Content Reported',
                v_body,
                jsonb_strip_nulls(jsonb_build_object(
                    'ride_id', NEW.reported_ride_id,
                    'favor_id', NEW.reported_favor_id,
                    'conversation_id', (SELECT conversation_id FROM public.messages WHERE id = NEW.reported_message_id),
                    'town_hall_post_id', COALESCE(NEW.reported_post_id, (SELECT post_id FROM public.town_hall_comments WHERE id = NEW.reported_comment_id))
                )),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;
```

- [ ] **Step 4: Verify the live functions now include the new target IDs and content-row updates**

Verify with:

```sql
select proname, oidvectortypes(proargtypes) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and proname in ('admin_get_reports', 'admin_moderate_content', 'handle_new_report', 'create_content_hidden_notification')
order by proname;
```

Expected: all four functions present, with `admin_get_reports` / `admin_moderate_content` replaced and `create_content_hidden_notification` added.

---

## Task 3: Add Notification Types And Shared Routing Support

**Files:**
- Modify: `supabase/functions/_shared/notificationTypes.ts`
- Modify: `NaarsCars/Core/Models/AppNotification.swift`
- Modify: `NaarsCars/Core/Models/NotificationTypeRegistry.swift`
- Modify: `NaarsCars/Core/Utilities/DeepLinkParser.swift`
- Modify: `NaarsCars/Features/Notifications/ViewModels/NotificationNavigationRouter.swift`
- Modify: `scripts/validate-notification-types.sh`

- [ ] **Step 1: Add `content_hidden` to both registries**

```typescript
export const NOTIFICATION_TYPES = {
  MESSAGE: 'message',
  ADDED_TO_CONVERSATION: 'added_to_conversation',
  // ...
  CONTENT_REPORTED: 'content_reported',
  CONTENT_HIDDEN: 'content_hidden',
  ANNOUNCEMENT: 'announcement',
  // ...
} as const
```

```swift
enum NotificationType: String, Codable, CaseIterable {
    // ...
    case contentReported = "content_reported"
    case contentHidden = "content_hidden"
    // ...
}

enum NotificationTypeRegistry {
    static let allTypes: Set<String> = [
        // ...
        "content_reported",
        "content_hidden",
        // ...
    ]
}
```

- [ ] **Step 2: Route `content_hidden` to the correct destination using existing ID fields**

```swift
extension NotificationType {
    var affectedDomains: Set<RefreshDomain> {
        switch self {
        case .contentHidden:
            return [.conversations, .townHall, .dashboard]
        // existing cases...
        default:
            // existing switch body
            return []
        }
    }

    var entityIdKey: String? {
        switch self {
        case .contentHidden:
            return nil
        // existing cases...
        default:
            return nil
        }
    }
}
```

```swift
static func parse(userInfo: [AnyHashable: Any]) -> DeepLink {
    guard let type = userInfo["type"] as? String else { return .unknown }

    switch type {
    case "content_hidden":
        if let conversationIdString = userInfo["conversation_id"] as? String,
           let conversationId = UUID(uuidString: conversationIdString) {
            return .conversation(id: conversationId)
        }
        if let rideIdString = userInfo["ride_id"] as? String,
           let rideId = UUID(uuidString: rideIdString) {
            return .ride(id: rideId)
        }
        if let favorIdString = userInfo["favor_id"] as? String,
           let favorId = UUID(uuidString: favorIdString) {
            return .favor(id: favorId)
        }
        if let postIdString = userInfo["town_hall_post_id"] as? String,
           let postId = UUID(uuidString: postIdString) {
            return .townHallPostHighlight(id: postId)
        }
        return .dashboard
    // existing cases...
    default:
        return .unknown
    }
}
```

```swift
func notificationIntent(for notification: AppNotification) -> NotificationIntent? {
    switch notification.type {
    case .contentHidden:
        if let conversationId = notification.conversationId {
            return .openConversation(conversationId: conversationId, scrollTarget: nil)
        }
        if let rideId = notification.rideId {
            return .openRide(rideId: rideId, anchor: nil)
        }
        if let favorId = notification.favorId {
            return .openFavor(favorId: favorId, anchor: nil)
        }
        if let postId = notification.townHallPostId {
            return .openTownHallPost(postId: postId, mode: .highlightPost)
        }
        return .openDashboard
    // existing cases...
    default:
        return nil
    }
}
```

- [ ] **Step 3: Extend the validation script to assert registry drift, not just Swift-vs-TypeScript**

```bash
REGISTRY_FILE="${ROOT_DIR}/NaarsCars/Core/Models/NotificationTypeRegistry.swift"

if [[ ! -f "${REGISTRY_FILE}" ]]; then
  echo "Missing registry file: ${REGISTRY_FILE}"
  exit 1
fi

REGISTRY_TYPES="$(
  awk -F'"' '/^[[:space:]]*"[^"]+"/ { print $2 }' "${REGISTRY_FILE}" | sort -u
)"

DIFF_REGISTRY_OUTPUT="$(diff <(echo "${SWIFT_TYPES}") <(echo "${REGISTRY_TYPES}") || true)"

if [[ -n "${DIFF_REGISTRY_OUTPUT}" ]]; then
  echo "MISMATCH between Swift enum and NotificationTypeRegistry:"
  echo "${DIFF_REGISTRY_OUTPUT}"
  exit 1
fi
```

- [ ] **Step 4: Validate notification types before touching UI**

Run:

```bash
scripts/validate-notification-types.sh
```

Expected: `Notification types validated:` with all three sources in sync.

---

## Task 4: Propagate Moderation Fields Through Swift Models And SwiftData

**Files:**
- Modify: `NaarsCars/Core/Models/Message.swift`
- Modify: `NaarsCars/Core/Models/Ride.swift`
- Modify: `NaarsCars/Core/Models/Favor.swift`
- Modify: `NaarsCars/Core/Models/TownHallPost.swift`
- Modify: `NaarsCars/Core/Models/TownHallComment.swift`
- Modify: `NaarsCars/Core/Storage/SDModels.swift`
- Modify: `NaarsCars/Core/Storage/MessagingMapper.swift`
- Modify: `NaarsCars/Core/Storage/BackgroundSyncActor.swift`

- [ ] **Step 1: Add moderation fields to the domain models**

```swift
struct Message: Codable, Identifiable, Equatable, Sendable {
    // existing fields...
    var hiddenAt: Date?
    var hiddenBy: UUID?
    var hiddenReason: String?

    var isModerationHidden: Bool {
        hiddenAt != nil
    }

    enum CodingKeys: String, CodingKey {
        // existing cases...
        case hiddenAt = "hidden_at"
        case hiddenBy = "hidden_by"
        case hiddenReason = "hidden_reason"
    }
}
```

```swift
struct Ride: Codable, Identifiable, Equatable, Sendable {
    // existing fields...
    let hiddenAt: Date?
    let hiddenBy: UUID?
    let hiddenReason: String?

    var isModerationHidden: Bool { hiddenAt != nil }

    enum CodingKeys: String, CodingKey {
        // existing cases...
        case hiddenAt = "hidden_at"
        case hiddenBy = "hidden_by"
        case hiddenReason = "hidden_reason"
    }
}
```

Apply the same three fields and `isModerationHidden` computed property to `Favor`, `TownHallPost`, and `TownHallComment`.

- [ ] **Step 2: Add the same fields to SwiftData**

```swift
@Model
final class SDMessage {
    // existing fields...
    var hiddenAt: Date?
    var hiddenBy: UUID?
    var hiddenReason: String?

    init(
        id: UUID,
        conversationId: UUID,
        fromId: UUID,
        text: String,
        // existing args...
        hiddenAt: Date? = nil,
        hiddenBy: UUID? = nil,
        hiddenReason: String? = nil
    ) {
        // existing assignments...
        self.hiddenAt = hiddenAt
        self.hiddenBy = hiddenBy
        self.hiddenReason = hiddenReason
    }
}
```

Apply the same pattern to `SDRide` and `SDFavor`.

- [ ] **Step 3: Update the mappers so moderation fields survive repository/realtime flow**

```swift
static func mapToSDMessage(_ message: Message, isPending: Bool = false) -> SDMessage {
    SDMessage(
        id: message.id,
        conversationId: message.conversationId,
        fromId: message.fromId,
        text: message.text,
        imageUrl: message.imageUrl,
        readBy: message.readBy,
        createdAt: message.createdAt,
        messageType: message.messageType?.rawValue ?? "text",
        replyToId: message.replyToId,
        audioUrl: message.audioUrl,
        audioDuration: message.audioDuration,
        imageWidth: message.imageWidth,
        imageHeight: message.imageHeight,
        latitude: message.latitude,
        longitude: message.longitude,
        locationName: message.locationName,
        editedAt: message.editedAt,
        deletedAt: message.deletedAt,
        isPending: isPending,
        status: message.sendStatus?.rawValue ?? (isPending ? "sending" : "sent"),
        localAttachmentPath: message.localAttachmentPath,
        hiddenAt: message.hiddenAt,
        hiddenBy: message.hiddenBy,
        hiddenReason: message.hiddenReason
    )
}
```

```swift
static func parseMessage(from record: [String: Any]) -> Message? {
    // existing parsing...
    let hiddenAt = parseDate(record["hidden_at"])
    let hiddenBy = parseUUID(record["hidden_by"])
    let hiddenReason = parseString(record["hidden_reason"])

    return Message(
        id: id,
        conversationId: convId,
        fromId: fromId,
        text: text,
        imageUrl: imageUrl,
        readBy: readBy,
        createdAt: createdAt,
        messageType: messageType,
        replyToId: replyToId,
        editedAt: editedAt,
        deletedAt: deletedAt,
        audioUrl: audioUrl,
        audioDuration: audioDuration,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        latitude: latitude,
        longitude: longitude,
        locationName: locationName,
        hiddenAt: hiddenAt,
        hiddenBy: hiddenBy,
        hiddenReason: hiddenReason
    )
}
```

- [ ] **Step 4: Update `BackgroundSyncActor` and change detection helpers**

```swift
private func updateSDRide(_ sd: SDRide, with ride: Ride) {
    // existing assignments...
    sd.hiddenAt = ride.hiddenAt
    sd.hiddenBy = ride.hiddenBy
    sd.hiddenReason = ride.hiddenReason
}

private func updateSDFavor(_ sd: SDFavor, with favor: Favor) {
    // existing assignments...
    sd.hiddenAt = favor.hiddenAt
    sd.hiddenBy = favor.hiddenBy
    sd.hiddenReason = favor.hiddenReason
}

private func updateSDRideIfChanged(_ sd: SDRide, with ride: Ride) -> Bool {
    var changed = false
    // existing comparisons...
    if sd.hiddenAt != ride.hiddenAt { sd.hiddenAt = ride.hiddenAt; changed = true }
    if sd.hiddenBy != ride.hiddenBy { sd.hiddenBy = ride.hiddenBy; changed = true }
    if sd.hiddenReason != ride.hiddenReason { sd.hiddenReason = ride.hiddenReason; changed = true }
    return changed
}
```

Mirror the same comparison updates for `SDFavor`, and add `hiddenAt` / `hiddenBy` / `hiddenReason` handling wherever `SDMessage` is upserted or diffed.

---

## Task 5: Upgrade The Admin Report Queue To Reversible Moderation UX

**Files:**
- Modify: `NaarsCars/Core/Services/AdminModerationService.swift`
- Modify: `NaarsCars/Features/Admin/Views/AdminReportsView.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

- [ ] **Step 1: Extend `AdminReport` so the UI knows every target type**

```swift
struct AdminReport: Codable, Identifiable, Equatable {
    let reportId: UUID
    let reporterId: UUID
    let reporterName: String?
    let reportedUserId: UUID?
    let reportedUserName: String?
    let reportedMessageId: UUID?
    let reportedPostId: UUID?
    let reportedCommentId: UUID?
    let reportedRideId: UUID?
    let reportedFavorId: UUID?
    let targetType: String
    let reportType: String
    let description: String?
    let status: String
    let createdAt: Date
    let reviewedAt: Date?
    let contentPreview: String?
    let contentHidden: Bool
    let reportCount: Int

    var contentTypeLabel: String {
        switch targetType {
        case "message": return "Message"
        case "town_hall_post": return "Post"
        case "town_hall_comment": return "Comment"
        case "ride": return "Ride"
        case "favor": return "Favor"
        default: return "User"
        }
    }
}
```

- [ ] **Step 2: Add explicit action state and confirmation UX**

```swift
private enum ModerationAction: String, Identifiable {
    case hide
    case restore
    case dismiss

    var id: String { rawValue }
}

private struct PendingModerationAction: Identifiable {
    let report: AdminReport
    let action: ModerationAction
    var note: String = ""

    var id: String { "\(report.reportId.uuidString)-\(action.rawValue)" }
}
```

```swift
@State private var pendingAction: PendingModerationAction?
@State private var isSubmittingAction = false
@State private var errorAlertMessage: String?
```

Use `MemberDetailView`’s sheet pattern for `Hide`:

```swift
.sheet(item: $pendingAction) { action in
    NavigationStack {
        Form {
            Section {
                Text(action.action == .hide
                     ? "admin_reports_hide_confirm_message".localized
                     : action.action == .restore
                        ? "admin_reports_restore_confirm_message".localized
                        : "admin_reports_dismiss_confirm_message".localized)
            }

            Section("admin_reports_note_title".localized) {
                TextField(
                    action.action == .hide
                        ? "admin_reports_hide_reason_placeholder".localized
                        : "admin_reports_optional_note_placeholder".localized,
                    text: Binding(
                        get: { pendingAction?.note ?? "" },
                        set: { pendingAction?.note = $0 }
                    ),
                    axis: .vertical
                )
                .lineLimit(3...6)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common_cancel".localized) { pendingAction = nil }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action.action == .hide ? "admin_reports_hide".localized : action.action == .restore ? "admin_reports_restore".localized : "admin_reports_dismiss".localized) {
                    Task { await submitPendingAction() }
                }
                .disabled(isSubmittingAction || (action.action == .hide && action.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
    }
}
```

- [ ] **Step 3: Make available actions depend on content state, not only pending status**

```swift
private func availableActions(for report: AdminReport) -> [ModerationAction] {
    switch report.status {
    case "pending":
        return report.contentHidden ? [.hide, .restore] : [.hide, .dismiss]
    case "dismissed", "action_taken":
        return report.contentHidden ? [.restore] : [.hide]
    default:
        return []
    }
}
```

Use these actions in `ReportCardView` instead of the current `if report.status == "pending"` branch.

- [ ] **Step 4: Surface moderation errors and localize all new copy**

```swift
.alert("common_error".localized, isPresented: Binding(
    get: { errorAlertMessage != nil },
    set: { if !$0 { errorAlertMessage = nil } }
)) {
    Button("common_ok".localized, role: .cancel) {}
} message: {
    Text(errorAlertMessage ?? "")
}
```

Add localized keys for:

```text
admin_reports_hide
admin_reports_restore
admin_reports_dismiss
admin_reports_hide_confirm_message
admin_reports_restore_confirm_message
admin_reports_dismiss_confirm_message
admin_reports_note_title
admin_reports_hide_reason_placeholder
admin_reports_optional_note_placeholder
admin_reports_auto_hidden
admin_reports_action_taken
admin_reports_dismissed
```

---

## Task 6: Implement Messaging Moderation Placeholders And Fix Thread Reporting

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/ModerationHiddenMessageView.swift`
- Modify: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift`
- Modify: `NaarsCars/Core/Services/MessageService.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

- [ ] **Step 1: Create a dedicated hidden-message placeholder view**

```swift
//
//  ModerationHiddenMessageView.swift
//  NaarsCars
//

import UIKit

final class ModerationHiddenMessageView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let borderLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.systemOrange.cgColor
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)

        iconView.image = UIImage(systemName: "eye.slash")
        iconView.tintColor = .systemOrange
        addSubview(iconView)

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .label
        titleLabel.text = "messaging_moderation_hidden_title".localized
        addSubview(titleLabel)

        subtitleLabel.font = .preferredFont(forTextStyle: .caption2)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.text = "messaging_moderation_hidden_subtitle".localized
        subtitleLabel.numberOfLines = 0
        addSubview(subtitleLabel)
    }

    func configure(reason: String?) {
        accessibilityLabel = reason?.isEmpty == false
            ? "messaging_moderation_hidden_accessibility_with_reason".localized(with: reason ?? "")
            : "messaging_moderation_hidden_accessibility".localized
        setNeedsLayout()
    }
}
```

- [ ] **Step 2: Render hidden messages before unsent messages**

```swift
private var moderationHiddenMessage: ModerationHiddenMessageView?

func configure(with config: MessageCellConfig) {
    self.config = config
    let msg = config.message

    hideAllContent()

    if msg.isModerationHidden {
        showModerationHidden(config: config)
    } else if msg.isUnsent {
        showUnsent(config: config)
    } else if isSystemMessage(msg) {
        showSystem(msg: msg)
    } else {
        showRegular(config: config)
    }
}

private func showModerationHidden(config: MessageCellConfig) {
    let view = moderationHiddenMessage ?? {
        let v = ModerationHiddenMessageView()
        addSubview(v)
        moderationHiddenMessage = v
        return v
    }()
    view.isHidden = false
    view.configure(reason: config.message.hiddenReason)
}
```

Update layout, size measurement, `hideAllContent()`, and `prepareForReuse()` anywhere `unsentMessage` is currently handled.

- [ ] **Step 3: Disable message actions on hidden placeholders and fix thread reporting**

```swift
private func handleOverlayAction(_ action: OverlayAction, for message: Message) {
    guard !message.isModerationHidden else { return }

    switch action {
    case .react(let emoji):
        Task { await conversationViewModel.addReaction(messageId: message.id, reaction: emoji) }
    // existing cases...
    case .report:
        presentReportSheet(for: message)
    }
}
```

In `ConversationDetailView`, show feedback on report success/failure:

```swift
private func submitReport(message: Message, type: MessageService.ReportType, description: String?) async {
    guard let userId = AuthService.shared.currentUserId else { return }

    do {
        try await MessageService.shared.reportMessage(
            reporterId: userId,
            messageId: message.id,
            type: type,
            description: description
        )
        toastMessage = "messaging_report_submitted".localized
        messageToReport = nil
    } catch {
        reportErrorMessage = error.localizedDescription
    }
}
```

- [ ] **Step 4: Ensure message fetch helpers keep moderation fields**

In `MessageService`, keep using message row selects but stop treating moderation as deletion:

```swift
let response = try await supabase
    .from("messages")
    .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
    .eq("conversation_id", value: conversationId.uuidString)
    .order("created_at", ascending: true)
    .limit(limit)
    .execute()
```

Do **not** add `.is("hidden_at", value: nil)` on message fetches. The server-side SELECT policy now decides who can see hidden rows, which is what enables sender-only placeholders.

---

## Task 7: Implement Author-Only Placeholders For Town Hall, Rides, And Favors

**Files:**
- Modify: `NaarsCars/Core/Services/TownHallService.swift`
- Modify: `NaarsCars/Core/Services/TownHallCommentService.swift`
- Modify: `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift`
- Modify: `NaarsCars/Features/TownHall/Views/PostCommentsView.swift`
- Modify: `NaarsCars/Core/Services/RideService.swift`
- Modify: `NaarsCars/Core/Services/FavorService.swift`
- Modify: `NaarsCars/UI/Components/Cards/RideCard.swift`
- Modify: `NaarsCars/UI/Components/Cards/FavorCard.swift`
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift`
- Modify: `NaarsCars/Features/Favors/Views/FavorDetailView.swift`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

- [ ] **Step 1: Stop hard-filtering hidden Town Hall rows in the client**

```swift
func fetchPosts(limit: Int = 20, offset: Int = 0) async throws -> [TownHallPost] {
    let response = try await supabase
        .from("town_hall_posts")
        .select()
        .order("created_at", ascending: false)
        .range(from: offset, to: offset + limit - 1)
        .execute()

    let decoder = createDateDecoder()
    var posts: [TownHallPost] = try decoder.decode([TownHallPost].self, from: response.data)
    // existing enrichment...
    return posts
}

func fetchPost(id: UUID) async throws -> TownHallPost {
    let response: TownHallPost = try await supabase
        .from("town_hall_posts")
        .select()
        .eq("id", value: id.uuidString)
        .single()
        .execute()
        .value
    return response
}
```

Make the same removal in `TownHallCommentService.fetchComments`. The new server-side visibility rules determine whether hidden rows are returned.

- [ ] **Step 2: Render Town Hall placeholders only for the author**

```swift
private var isModerationHidden: Bool {
    post.hiddenAt != nil
}

private var isOwnHiddenPost: Bool {
    isModerationHidden && currentUserId == post.userId
}

// In body:
if isOwnHiddenPost {
    VStack(alignment: .leading, spacing: 8) {
        Label("townhall_moderation_hidden_title".localized, systemImage: "eye.slash")
            .font(.naarsSubheadline)
            .foregroundColor(.orange)

        Text("townhall_moderation_hidden_body".localized)
            .font(.naarsBody)
            .foregroundColor(.secondary)
    }
} else {
    Text(post.content)
        .font(.naarsBody)
        .foregroundColor(.primary)
}
```

For comments:

```swift
let isOwnHiddenComment = comment.hiddenAt != nil && currentUserId == comment.userId

if isOwnHiddenComment {
    Label("townhall_comment_hidden_title".localized, systemImage: "eye.slash")
        .font(.naarsCaption)
        .foregroundColor(.orange)
} else {
    Text(comment.content)
        .font(.naarsBody)
}
```

Disable vote/comment/reply/report actions when the placeholder is shown.

- [ ] **Step 3: Render ride/favor placeholders in cards and detail views**

```swift
struct RideCard: View {
    let ride: Ride

    private var isOwnHiddenRide: Bool {
        ride.isModerationHidden && AuthService.shared.currentUserId == ride.userId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isOwnHiddenRide {
                Label("requests_hidden_title".localized, systemImage: "eye.slash")
                    .font(.naarsHeadline)
                    .foregroundColor(.orange)

                Text("requests_hidden_body".localized)
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
            } else {
                // existing ride card content
            }
        }
    }
}
```

Mirror the same pattern in `FavorCard`, and in `RideDetailView` / `FavorDetailView` short-circuit the main action area:

```swift
if ride.isModerationHidden && currentUserId == ride.userId {
    ContentUnavailableView(
        "requests_hidden_title".localized,
        systemImage: "eye.slash",
        description: Text("requests_hidden_body".localized)
    )
} else {
    existingDetailContent
}
```

Hide or disable claim, Q&A, edit, share, and report actions in the placeholder state.

- [ ] **Step 4: Build the localization keys used by placeholders**

Add keys for:

```text
messaging_moderation_hidden_title
messaging_moderation_hidden_subtitle
messaging_moderation_hidden_accessibility
messaging_moderation_hidden_accessibility_with_reason
messaging_report_submitted
townhall_moderation_hidden_title
townhall_moderation_hidden_body
townhall_comment_hidden_title
requests_hidden_title
requests_hidden_body
```

---

## Task 8: Validate The Whole Moderation Flow

**Files:**
- No new source files

- [ ] **Step 1: Validate notification type sync**

Run:

```bash
scripts/validate-notification-types.sh
```

Expected: success output with no registry mismatch.

- [ ] **Step 2: Build the app**

Run:

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Verify live SQL contract**

Run:

```sql
select proname, oidvectortypes(proargtypes) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and proname in ('admin_get_reports', 'admin_moderate_content', 'handle_new_report', 'create_content_hidden_notification', 'should_notify_user')
order by proname;
```

Expected: all functions present and updated.

- [ ] **Step 4: Manual moderation matrix**

1. Report a Town Hall post from user A; verify admin sees report in `AdminReportsView`.
2. Hide the post with a reason from the admin UI; verify user B no longer sees it, user A sees the placeholder, and user A receives `content_hidden`.
3. Restore the post; verify user B sees it again and the audit row remains in `content_moderation_events`.
4. Dismiss a visible ride report; verify the ride stays visible and the same report target still allows a later `Hide`.
5. Hide a ride; verify only the author sees the placeholder card/detail state.
6. Report a message from the main conversation view; verify sender-only placeholder after hide.
7. Report a message from the thread view; verify the action is no longer a no-op.
8. Auto-hide a Town Hall comment via 3 distinct reports; verify admins see it as auto-hidden, then convert it to reviewed hide by providing a moderator reason.
9. Confirm `content_reported` still routes admins to Admin Reports and `content_hidden` routes authors to the affected surface.

- [ ] **Step 5: Do not commit unless the user explicitly asks**

This repo is in a dirty worktree and the user has not asked for a commit. Stop after verification and report what changed.
