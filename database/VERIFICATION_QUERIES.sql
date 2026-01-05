-- Database Verification Queries for Task 5.0
-- Run these in Supabase Dashboard SQL Editor
-- Document results in tasks-foundation-architecture.md

-- ============================================
-- 5.1: Verification Query - Check Table Counts
-- ============================================
SELECT 
    'profiles' as table_name, COUNT(*) as row_count FROM profiles
UNION ALL
SELECT 'invite_codes', COUNT(*) FROM invite_codes
UNION ALL
SELECT 'rides', COUNT(*) FROM rides
UNION ALL
SELECT 'ride_participants', COUNT(*) FROM ride_participants
UNION ALL
SELECT 'favors', COUNT(*) FROM favors
UNION ALL
SELECT 'favor_participants', COUNT(*) FROM favor_participants
UNION ALL
SELECT 'request_qa', COUNT(*) FROM request_qa
UNION ALL
SELECT 'conversations', COUNT(*) FROM conversations
UNION ALL
SELECT 'conversation_participants', COUNT(*) FROM conversation_participants
UNION ALL
SELECT 'messages', COUNT(*) FROM messages
UNION ALL
SELECT 'notifications', COUNT(*) FROM notifications
UNION ALL
SELECT 'push_tokens', COUNT(*) FROM push_tokens
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews
UNION ALL
SELECT 'town_hall_posts', COUNT(*) FROM town_hall_posts;

-- Expected: All tables should have rows (at least seed data)
-- Document actual counts in task file

-- ============================================
-- 5.2: SEC-DB-001: Test query profiles as unauthenticated
-- ============================================
-- Run this WITHOUT being authenticated (use anon key or no auth)
-- Expected: Should return 0 rows or error about RLS

SELECT * FROM profiles LIMIT 1;

-- If this returns data, RLS is NOT working correctly!
-- Expected result: ERROR or 0 rows

-- ============================================
-- 5.3: SEC-DB-002: Test query profiles as unapproved user (eve)
-- ============================================
-- First, get eve's user ID:
SELECT id, email, approved FROM profiles WHERE email = 'eve@test.com';

-- Then, using eve's auth token (you'll need to authenticate as eve@test.com):
-- Run: SELECT * FROM profiles;
-- Expected: Should return ONLY eve's profile (1 row)

-- Note: To test this properly, you need to:
-- 1. Get auth token for eve@test.com (password: TestPassword123!)
-- 2. Use that token in API request or Supabase client
-- 3. Query profiles table
-- 4. Verify only eve's profile is returned

-- ============================================
-- 5.4: SEC-DB-003: Test query profiles as approved user (bob)
-- ============================================
-- Using bob's auth token (bob@test.com, password: TestPassword123!):
-- Run: SELECT * FROM profiles WHERE approved = true;
-- Expected: Should return all approved profiles (alice, bob, carol, dave - 4 rows)
-- Should NOT return eve's profile (unapproved)

-- ============================================
-- 5.5: SEC-DB-004: Test update another user's profile
-- ============================================
-- As bob@test.com, try to update alice's profile:
-- UPDATE profiles SET name = 'Hacked' WHERE email = 'alice@test.com';
-- Expected: ERROR - RLS should block this

-- ============================================
-- 5.6: SEC-DB-005: Test set own is_admin=true as non-admin
-- ============================================
-- As bob@test.com (non-admin), try:
-- UPDATE profiles SET is_admin = true WHERE id = auth.uid();
-- Expected: ERROR - Trigger should block this

-- ============================================
-- 5.7: SEC-DB-006: Test admin (alice) approve user
-- ============================================
-- As alice@test.com (admin), approve eve:
-- UPDATE profiles SET approved = true WHERE email = 'eve@test.com';
-- Expected: SUCCESS - Should update 1 row

-- Verify:
SELECT email, approved FROM profiles WHERE email = 'eve@test.com';
-- Should show approved = true

-- ============================================
-- 5.8: SEC-DB-007: Test non-admin approve user
-- ============================================
-- As bob@test.com (non-admin), try to approve eve:
-- UPDATE profiles SET approved = true WHERE email = 'eve@test.com';
-- Expected: ERROR or 0 rows updated - RLS should block

-- ============================================
-- 5.9: SEC-DB-008: Test query messages not in conversation
-- ============================================
-- First, get a conversation ID that bob is NOT part of:
-- SELECT c.id FROM conversations c
-- WHERE c.id NOT IN (
--   SELECT cp.conversation_id 
--   FROM conversation_participants cp 
--   WHERE cp.user_id = (SELECT id FROM profiles WHERE email = 'bob@test.com')
-- )
-- LIMIT 1;

-- Then as bob, try to query messages from that conversation:
-- SELECT * FROM messages WHERE conversation_id = '[conversation_id_from_above]';
-- Expected: ERROR or 0 rows - RLS should block

-- ============================================
-- 5.10: SEC-DB-009: Test insert ride with different user_id
-- ============================================
-- As bob@test.com, try to insert a ride for alice:
-- INSERT INTO rides (user_id, type, date, time, pickup, destination, seats, status)
-- VALUES (
--   (SELECT id FROM profiles WHERE email = 'alice@test.com'),
--   'one_way',
--   CURRENT_DATE + INTERVAL '1 day',
--   '10:00:00',
--   'Location A',
--   'Location B',
--   2,
--   'open'
-- );
-- Expected: ERROR - RLS should block inserting rides for other users

-- ============================================
-- 5.11: PERF-DB-001: Query open rides - verify <100ms
-- ============================================
-- Run with EXPLAIN ANALYZE to see execution time:
EXPLAIN ANALYZE
SELECT * FROM rides 
WHERE status = 'open' 
  AND date >= CURRENT_DATE
ORDER BY created_at DESC
LIMIT 20;

-- Check the "Execution Time" in the output
-- Expected: < 100ms
-- If slower, check that indexes exist on (status, date, created_at)

-- ============================================
-- 5.12: PERF-DB-002: Query leaderboard - verify <200ms
-- ============================================
-- Test the leaderboard view/function:
EXPLAIN ANALYZE
SELECT * FROM leaderboard_stats
ORDER BY fulfilled_count DESC
LIMIT 50;

-- Or if using function:
EXPLAIN ANALYZE
SELECT * FROM get_leaderboard('all_time', 50);

-- Check execution time
-- Expected: < 200ms

-- ============================================
-- 5.13: PERF-DB-003: Query conversation messages - verify <100ms
-- ============================================
-- Test querying messages for a conversation:
EXPLAIN ANALYZE
SELECT m.*, p.name as from_name
FROM messages m
JOIN profiles p ON m.from_id = p.id
WHERE m.conversation_id = (
  SELECT id FROM conversations LIMIT 1
)
ORDER BY m.created_at ASC
LIMIT 50;

-- Check execution time
-- Expected: < 100ms
-- If slower, check indexes on (conversation_id, created_at)

-- ============================================
-- 5.14: EDGE-001: Test send-push-notification function
-- ============================================
-- This requires the Edge Function to be deployed
-- Test via Supabase Dashboard → Edge Functions → send-push-notification → Invoke
-- Or via API:
-- POST https://[project-ref].supabase.co/functions/v1/send-push-notification
-- Headers: { "Authorization": "Bearer [anon-key]" }
-- Body: { "token": "test-token", "title": "Test", "body": "Test message" }

-- Expected: Function executes (may fail if APNs not configured, but should not error on function itself)

-- ============================================
-- 5.15: EDGE-002: Test cleanup-tokens function
-- ============================================
-- Test via Supabase Dashboard → Edge Functions → cleanup-tokens → Invoke
-- Or via API:
-- POST https://[project-ref].supabase.co/functions/v1/cleanup-tokens
-- Headers: { "Authorization": "Bearer [anon-key]" }

-- Expected: Function executes and calls cleanup_stale_push_tokens() database function

-- ============================================
-- 5.16: Test auto-profile trigger
-- ============================================
-- Create a new auth user via Supabase Dashboard → Authentication → Users → Add User
-- Email: test-trigger@test.com
-- Password: TestPassword123!

-- Then check if profile was auto-created:
SELECT * FROM profiles WHERE email = 'test-trigger@test.com';

-- Expected: Profile should exist with:
-- - id matching auth.users.id
-- - email = 'test-trigger@test.com'
-- - approved = false
-- - is_admin = false
-- - created_at should be recent

-- ============================================
-- 5.17: Verify Alice is admin
-- ============================================
SELECT is_admin, approved, email, name 
FROM profiles 
WHERE email = 'alice@test.com';

-- Expected:
-- is_admin = true
-- approved = true

-- ============================================
-- 5.18: Fix Alice if not admin
-- ============================================
-- Only run if 5.17 shows is_admin = false or approved = false:
UPDATE profiles 
SET is_admin = true, approved = true 
WHERE email = 'alice@test.com';

-- Verify fix:
SELECT is_admin, approved FROM profiles WHERE email = 'alice@test.com';

-- ============================================
-- Performance Index Verification
-- ============================================
-- Verify critical indexes exist:
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('profiles', 'rides', 'favors', 'messages', 'conversations')
ORDER BY tablename, indexname;

-- Expected: Should see indexes on:
-- - profiles: id (primary key), email, approved, is_admin
-- - rides: id (primary key), user_id, status, date, created_at
-- - favors: id (primary key), user_id, status, date, created_at
-- - messages: id (primary key), conversation_id, from_id, created_at
-- - conversations: id (primary key), created_at

-- ============================================
-- RLS Policy Verification
-- ============================================
-- Verify RLS is enabled on all tables:
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'profiles', 'invite_codes', 'rides', 'ride_participants',
    'favors', 'favor_participants', 'request_qa', 'conversations',
    'conversation_participants', 'messages', 'notifications',
    'push_tokens', 'reviews', 'town_hall_posts'
  )
ORDER BY tablename;

-- Expected: All tables should show rowsecurity = true

-- Verify policies exist:
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- Expected: Should see multiple policies per table (SELECT, INSERT, UPDATE, DELETE)

