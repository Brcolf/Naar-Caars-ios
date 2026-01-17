-- ============================================================================
-- 058_add_estimated_cost_to_rides.sql
-- ============================================================================
-- 
-- Add estimated_cost column to rides table
-- This column stores the calculated ride share cost estimate in USD
--
-- ============================================================================

-- Add estimated_cost column to rides table
ALTER TABLE rides 
ADD COLUMN IF NOT EXISTS estimated_cost NUMERIC(10,2);

-- Add comment to column
COMMENT ON COLUMN rides.estimated_cost IS 'Estimated ride share cost in USD, calculated after ride creation';

-- ============================================================================
-- Verification
-- ============================================================================
-- Verify column was added
-- SELECT column_name, data_type, numeric_precision, numeric_scale
-- FROM information_schema.columns
-- WHERE table_name = 'rides' AND column_name = 'estimated_cost';

