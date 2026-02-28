-- ============================================================================
-- 109_add_flight_normalized_to_rides.sql
-- ============================================================================
--
-- Add flight_normalized column to rides table (parsed from notes after post).
--
-- ============================================================================

ALTER TABLE rides
ADD COLUMN IF NOT EXISTS flight_normalized TEXT;

COMMENT ON COLUMN rides.flight_normalized IS 'First parsed flight code from notes (e.g. DL123, SWA1234), saved in background after ride creation';
