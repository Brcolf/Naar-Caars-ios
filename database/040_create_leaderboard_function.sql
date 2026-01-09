-- Migration: Create leaderboard database function
-- Purpose: Server-side calculation of leaderboard rankings for performance
-- Based on PRD: prd-leaderboards.md Section 3.2

-- Function to get leaderboard entries for a time period
-- Returns top 100 users sorted by requests fulfilled (descending)
CREATE OR REPLACE FUNCTION get_leaderboard(
    start_date DATE DEFAULT '1970-01-01',
    end_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
    user_id UUID,
    name TEXT,
    avatar_url TEXT,
    requests_fulfilled BIGINT,
    requests_made BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.name,
        p.avatar_url,
        (
            SELECT COUNT(*) FROM rides r
            WHERE r.claimed_by = p.id 
            AND r.status = 'completed'
            AND DATE(r.updated_at) BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM favors f
            WHERE f.claimed_by = p.id 
            AND f.status = 'completed'
            AND DATE(f.updated_at) BETWEEN start_date AND end_date
        ) as requests_fulfilled,
        (
            SELECT COUNT(*) FROM rides r
            WHERE r.user_id = p.id
            AND DATE(r.created_at) BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM favors f
            WHERE f.user_id = p.id
            AND DATE(f.created_at) BETWEEN start_date AND end_date
        ) as requests_made
    FROM profiles p
    WHERE p.approved = true
    ORDER BY requests_fulfilled DESC
    LIMIT 100;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_leaderboard(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_leaderboard(DATE, DATE) TO anon;

-- Index for efficient sorting (if not already exists)
CREATE INDEX IF NOT EXISTS idx_rides_claimed_by_completed 
ON rides(claimed_by, status, updated_at) 
WHERE status = 'completed';

CREATE INDEX IF NOT EXISTS idx_favors_claimed_by_completed 
ON favors(claimed_by, status, updated_at) 
WHERE status = 'completed';

CREATE INDEX IF NOT EXISTS idx_rides_user_id_created 
ON rides(user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_favors_user_id_created 
ON favors(user_id, created_at);

