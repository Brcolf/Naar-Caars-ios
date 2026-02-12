-- The on_review_created trigger fires BEFORE INSERT, but handle_new_review
-- inserts into town_hall_posts with review_id = NEW.id.
-- Since the review row doesn't exist yet at BEFORE INSERT time,
-- the FK constraint town_hall_posts_review_id_fkey fails.
-- Fix: Change to AFTER INSERT so the review row exists when the trigger runs.

DROP TRIGGER IF EXISTS on_review_created ON public.reviews;

CREATE TRIGGER on_review_created
    AFTER INSERT ON public.reviews
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_review();
