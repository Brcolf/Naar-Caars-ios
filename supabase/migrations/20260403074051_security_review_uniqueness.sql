-- 20260403074051_security_review_uniqueness.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Add uniqueness constraints for reviews.
-- Live confirmed: only PK index exists. One duplicate found (reviewer 53d71687
-- with 2 reviews for ride 2b232d3d). Clean up first, then add constraint.
-- Audit ref: HIGH-6.

-- Remove existing duplicates (keep the earliest review by created_at)
DELETE FROM reviews r1
USING reviews r2
WHERE r1.ride_id IS NOT NULL
  AND r1.ride_id = r2.ride_id
  AND r1.reviewer_id = r2.reviewer_id
  AND r1.created_at > r2.created_at;

DELETE FROM reviews r1
USING reviews r2
WHERE r1.favor_id IS NOT NULL
  AND r1.favor_id = r2.favor_id
  AND r1.reviewer_id = r2.reviewer_id
  AND r1.created_at > r2.created_at;

-- Add partial unique indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_unique_ride_reviewer
ON reviews (reviewer_id, ride_id) WHERE ride_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_unique_favor_reviewer
ON reviews (reviewer_id, favor_id) WHERE favor_id IS NOT NULL;
