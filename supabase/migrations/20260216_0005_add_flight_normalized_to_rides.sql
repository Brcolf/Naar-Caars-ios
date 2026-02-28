-- Add flight_normalized to rides (parsed from notes after post; open-data only).
ALTER TABLE public.rides
ADD COLUMN IF NOT EXISTS flight_normalized TEXT;

COMMENT ON COLUMN public.rides.flight_normalized IS 'First parsed flight code from notes (e.g. DL123, SWA1234), saved in background after ride creation';
