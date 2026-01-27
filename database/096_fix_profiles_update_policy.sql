-- Migration: Ensure profile update policy allows users to update their own profile

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_update_own ON profiles;

CREATE POLICY profiles_update_own
ON profiles
FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);


