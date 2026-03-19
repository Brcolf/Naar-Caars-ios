# Task 5.0: Database Verification Guide

This guide helps you complete Task 5.0 - Database verification with security and performance tests.

## Prerequisites

- Supabase project created and configured
- All database schema executed (Tasks 0.0-4.0)
- Test users created (alice, bob, carol, dave, eve)
- Seed data loaded

## Quick Start

1. Open Supabase Dashboard → SQL Editor
2. Use the queries in `database/VERIFICATION_QUERIES.sql`
3. Document results in `Tasks/tasks-foundation-architecture.md`
4. Mark each test as complete when verified

## Test Execution Order

### Step 1: Basic Verification (5.1)
Run the table count query to verify all tables have data.

### Step 2: Security Tests (5.2-5.10)
These test Row Level Security (RLS) policies. Most require authenticating as different users.

**How to authenticate as a user:**
1. Go to Supabase Dashboard → Authentication → Users
2. Find the user (e.g., eve@test.com)
3. Click "..." → "Generate JWT token"
4. Copy the token
5. In SQL Editor, set the auth context (see below)

**Setting auth context in SQL:**
```sql
-- For testing RLS, you need to use the REST API or Supabase client
-- SQL Editor runs as service_role by default (bypasses RLS)
-- To test RLS properly, use the REST API or Supabase client with user tokens
```

**Alternative: Test via REST API**
```bash
# Get auth token for user
curl -X POST 'https://[project-ref].supabase.co/auth/v1/token?grant_type=password' \
  -H "apikey: [anon-key]" \
  -H "Content-Type: application/json" \
  -d '{"email":"eve@test.com","password":"TestPassword123!"}'

# Use token to query profiles (should only return eve's profile)
curl 'https://[project-ref].supabase.co/rest/v1/profiles?select=*' \
  -H "apikey: [anon-key]" \
  -H "Authorization: Bearer [token-from-above]"
```

### Step 3: Performance Tests (5.11-5.13)
Run `EXPLAIN ANALYZE` queries and check execution time.

### Step 4: Edge Function Tests (5.14-5.15)
Only if Edge Functions are deployed. Can be deferred.

### Step 5: Trigger Tests (5.16)
Create a new auth user and verify profile is auto-created.

### Step 6: Admin Verification (5.17-5.18)
Verify Alice is admin, fix if needed.

## Detailed Test Instructions

### SEC-DB-001: Unauthenticated Query
**Expected:** Should return 0 rows or error

**Test:**
```sql
-- Run without authentication (using anon key only)
SELECT * FROM profiles LIMIT 1;
```

**Result:** Should be blocked by RLS (0 rows or error)

### SEC-DB-002: Unapproved User Query
**Expected:** Only own profile returned

**Test:**
1. Authenticate as eve@test.com
2. Query: `SELECT * FROM profiles;`
3. Should return only eve's profile (1 row)

### SEC-DB-003: Approved User Query
**Expected:** All approved profiles returned

**Test:**
1. Authenticate as bob@test.com
2. Query: `SELECT * FROM profiles WHERE approved = true;`
3. Should return alice, bob, carol, dave (4 rows)
4. Should NOT return eve (unapproved)

### SEC-DB-004: Update Another User's Profile
**Expected:** Blocked by RLS

**Test:**
1. Authenticate as bob@test.com
2. Try: `UPDATE profiles SET name = 'Hacked' WHERE email = 'alice@test.com';`
3. Should fail with RLS error or update 0 rows

### SEC-DB-005: Set is_admin as Non-Admin
**Expected:** Blocked by trigger

**Test:**
1. Authenticate as bob@test.com
2. Try: `UPDATE profiles SET is_admin = true WHERE id = auth.uid();`
3. Should fail - trigger should prevent non-admins from setting is_admin

### SEC-DB-006: Admin Approve User
**Expected:** Succeeds

**Test:**
1. Authenticate as alice@test.com
2. Run: `UPDATE profiles SET approved = true WHERE email = 'eve@test.com';`
3. Should succeed (1 row updated)
4. Verify: `SELECT approved FROM profiles WHERE email = 'eve@test.com';` should be true

### SEC-DB-007: Non-Admin Approve User
**Expected:** Blocked by RLS

**Test:**
1. Authenticate as bob@test.com
2. Try: `UPDATE profiles SET approved = true WHERE email = 'eve@test.com';`
3. Should fail or update 0 rows

### SEC-DB-008: Query Messages Not in Conversation
**Expected:** Blocked by RLS

**Test:**
1. Get a conversation ID that bob is NOT part of
2. Authenticate as bob@test.com
3. Query: `SELECT * FROM messages WHERE conversation_id = '[conversation_id]';`
4. Should return 0 rows or error

### SEC-DB-009: Insert Ride with Different user_id
**Expected:** Blocked by RLS

**Test:**
1. Authenticate as bob@test.com
2. Try to insert ride for alice:
```sql
INSERT INTO rides (user_id, type, date, time, pickup, destination, seats, status)
VALUES (
  (SELECT id FROM profiles WHERE email = 'alice@test.com'),
  'one_way',
  CURRENT_DATE + INTERVAL '1 day',
  '10:00:00',
  'Location A',
  'Location B',
  2,
  'open'
);
```
3. Should fail - RLS should prevent inserting rides for other users

### PERF-DB-001: Query Open Rides
**Expected:** <100ms

**Test:**
```sql
EXPLAIN ANALYZE
SELECT * FROM rides 
WHERE status = 'open' 
  AND date >= CURRENT_DATE
ORDER BY created_at DESC
LIMIT 20;
```

**Check:** Look for "Execution Time: X.XXX ms" in output
**Target:** < 100ms

### PERF-DB-002: Query Leaderboard
**Expected:** <200ms

**Test:**
```sql
EXPLAIN ANALYZE
SELECT * FROM leaderboard_stats
ORDER BY fulfilled_count DESC
LIMIT 50;
```

**Check:** Execution time
**Target:** < 200ms

### PERF-DB-003: Query Conversation Messages
**Expected:** <100ms

**Test:**
```sql
EXPLAIN ANALYZE
SELECT m.*, p.name as from_name
FROM messages m
JOIN profiles p ON m.from_id = p.id
WHERE m.conversation_id = (
  SELECT id FROM conversations LIMIT 1
)
ORDER BY m.created_at ASC
LIMIT 50;
```

**Check:** Execution time
**Target:** < 100ms

### EDGE-001: Test Push Notification Function
**Note:** Only if Edge Functions are deployed

**Test:**
1. Go to Supabase Dashboard → Edge Functions
2. Click "send-push-notification" → "Invoke"
3. Body: `{"token":"test-token","title":"Test","body":"Test message"}`
4. Should execute (may fail if APNs not configured, but function should run)

### EDGE-002: Test Cleanup Tokens Function
**Note:** Only if Edge Functions are deployed

**Test:**
1. Go to Supabase Dashboard → Edge Functions
2. Click "cleanup-tokens" → "Invoke"
3. Should execute and call `cleanup_stale_push_tokens()` function

### 5.16: Test Auto-Profile Trigger
**Expected:** Profile auto-created when auth user created

**Test:**
1. Go to Supabase Dashboard → Authentication → Users
2. Click "Add User" → "Create New User"
3. Email: `test-trigger@test.com`
4. Password: `TestPassword123!`
5. Click "Create User"
6. Query: `SELECT * FROM profiles WHERE email = 'test-trigger@test.com';`
7. Should return 1 row with profile matching auth user

### 5.17-5.18: Verify Alice is Admin
**Test:**
```sql
SELECT is_admin, approved, email, name 
FROM profiles 
WHERE email = 'alice@test.com';
```

**Expected:**
- `is_admin = true`
- `approved = true`

**If not admin, fix:**
```sql
UPDATE profiles 
SET is_admin = true, approved = true 
WHERE email = 'alice@test.com';
```

## Documenting Results

After each test, update `Tasks/tasks-foundation-architecture.md`:

```markdown
- [x] 5.2 🧪 SEC-DB-001: Query profiles as unauthenticated - ✅ Blocked (0 rows)
- [x] 5.3 🧪 SEC-DB-002: Query profiles as unapproved user - ✅ Only own profile (1 row)
- [x] 5.11 🧪 PERF-DB-001: Query open rides - ✅ 42ms (<100ms target)
```

## Troubleshooting

### RLS Tests Not Working
- **Issue:** Tests return data when they shouldn't
- **Solution:** Make sure you're using user tokens, not service_role key
- **Check:** Verify RLS is enabled: `SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public';`

### Performance Tests Too Slow
- **Issue:** Queries take longer than target
- **Solution:** Check indexes exist: `SELECT * FROM pg_indexes WHERE tablename = 'rides';`
- **Fix:** Create missing indexes from `003_indexes.sql`

### Trigger Not Working
- **Issue:** Profile not auto-created
- **Solution:** Check trigger exists: `SELECT * FROM pg_trigger WHERE tgname = 'handle_new_user';`
- **Fix:** Re-run `005_triggers.sql`

## Completion Checklist

- [ ] 5.1: Table counts verified
- [ ] 5.2: SEC-DB-001 passed
- [ ] 5.3: SEC-DB-002 passed
- [ ] 5.4: SEC-DB-003 passed
- [ ] 5.5: SEC-DB-004 passed
- [ ] 5.6: SEC-DB-005 passed
- [ ] 5.7: SEC-DB-006 passed
- [ ] 5.8: SEC-DB-007 passed
- [ ] 5.9: SEC-DB-008 passed
- [ ] 5.10: SEC-DB-009 passed
- [ ] 5.11: PERF-DB-001 passed (<100ms)
- [ ] 5.12: PERF-DB-002 passed (<200ms)
- [ ] 5.13: PERF-DB-003 passed (<100ms)
- [ ] 5.14: EDGE-001 tested (or deferred)
- [ ] 5.15: EDGE-002 tested (or deferred)
- [ ] 5.16: Auto-profile trigger verified
- [ ] 5.17: Alice verified as admin
- [ ] 5.18: Alice fixed if needed
- [ ] 5.19: Issues documented
- [ ] 5.20: Database setup verified ✅

## Next Steps

After completing Task 5.0:
1. Mark Task 5.0 as complete in task file
2. Proceed to run foundation checkpoints
3. Continue with remaining iOS tasks (22.12-22.15)

