-- Migration: Request-scoped notification clearing
-- Adds RPC to mark request notifications read for the current user.

CREATE OR REPLACE FUNCTION mark_request_notifications_read(
    p_request_type TEXT,
    p_request_id UUID,
    p_notification_types TEXT[] DEFAULT NULL,
    p_include_reviews BOOLEAN DEFAULT FALSE
) RETURNS INTEGER AS $$
DECLARE
    v_types TEXT[];
    v_count INTEGER;
BEGIN
    IF p_notification_types IS NULL THEN
        v_types := ARRAY[
            'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
            'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
            'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
        ];

        IF p_include_reviews THEN
            v_types := v_types || ARRAY['review_request', 'review_reminder'];
        END IF;
    ELSE
        v_types := p_notification_types;
    END IF;

    UPDATE notifications
    SET read = true
    WHERE user_id = auth.uid()
      AND read = false
      AND created_at <= NOW()
      AND (
        (p_request_type = 'ride' AND ride_id = p_request_id) OR
        (p_request_type = 'favor' AND favor_id = p_request_id)
      )
      AND type = ANY(v_types);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION mark_request_notifications_read(TEXT, UUID, TEXT[], BOOLEAN) TO authenticated;

