-- 20260206233344_fix_handle_new_review_trigger.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- The handle_new_review trigger inserts into town_hall_posts with
-- user_id = NEW.fulfiller_id, but the authenticated user is the reviewer.
-- RLS policy requires auth.uid() = user_id, so this always fails.
-- 
-- Fix: Make the function SECURITY DEFINER so it bypasses RLS,
-- AND change to use reviewer_id (the authenticated user posting the review)
-- to match the behavior expected by the app.

CREATE OR REPLACE FUNCTION public.handle_new_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    reviewer_name TEXT;
    fulfiller_name TEXT;
BEGIN
    SELECT name INTO reviewer_name FROM public.profiles WHERE id = NEW.reviewer_id;
    SELECT name INTO fulfiller_name FROM public.profiles WHERE id = NEW.fulfiller_id;
    
    INSERT INTO public.town_hall_posts (user_id, title, content, review_id)
    VALUES (
        NEW.reviewer_id,
        format('%s reviewed %s', COALESCE(reviewer_name, 'Someone'), COALESCE(fulfiller_name, 'someone')),
        COALESCE(NEW.comment, format('Rating: %s/5', NEW.rating::text)),
        NEW.id
    );
    
    RETURN NEW;
END;
$function$;
