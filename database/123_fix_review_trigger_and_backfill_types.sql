-- Fix handle_new_review trigger to set type = 'review', use generic title,
-- and include star emojis in content. Also backfill existing posts.

-- 1. Update the trigger function
CREATE OR REPLACE FUNCTION public.handle_new_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    INSERT INTO public.town_hall_posts (user_id, title, content, review_id, type)
    VALUES (
        NEW.reviewer_id,
        'New Review',
        format('%s %s', repeat('⭐', NEW.rating), COALESCE(NEW.comment, '')),
        NEW.id,
        'review'
    );

    RETURN NEW;
END;
$function$;

-- 2. Backfill review posts that have review_id but null type
UPDATE public.town_hall_posts
SET type = 'review'
WHERE review_id IS NOT NULL AND type IS NULL;

-- 3. Backfill announcement posts (pinned posts without review_id)
UPDATE public.town_hall_posts
SET type = 'announcement'
WHERE pinned = true AND type IS NULL AND review_id IS NULL;
