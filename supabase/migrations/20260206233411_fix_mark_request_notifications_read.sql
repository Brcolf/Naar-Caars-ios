-- 20260206233411_fix_mark_request_notifications_read.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Fix mark_request_notifications_read: uses unqualified 'notifications' table
-- reference with empty search_path, causing "relation does not exist" error.

CREATE OR REPLACE FUNCTION public.mark_request_notifications_read(p_request_type text, p_request_id uuid, p_notification_types text[] DEFAULT NULL::text[], p_include_reviews boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
    v_types text[];
    v_count integer;
begin
    if p_notification_types is null then
        v_types := array[
            'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
            'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
            'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
        ];

        if p_include_reviews then
            v_types := v_types || array['review_request', 'review_reminder'];
        end if;
    else
        v_types := p_notification_types;
    end if;

    update public.notifications
    set read = true
    where user_id = auth.uid()
      and read = false
      and created_at <= now()
      and (
        (p_request_type = 'ride' and ride_id = p_request_id) or
        (p_request_type = 'favor' and favor_id = p_request_id)
      )
      and type = any(v_types);

    get diagnostics v_count = row_count;
    return v_count;
end;
$function$;
