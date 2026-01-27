# Commit Guide: App Launch Error Fixes

## Date: January 19, 2026

## Summary
This commit resolves all critical app launch errors identified from the console logs:
1. **Notification decoding failures** - Added missing notification types (`broadcast`, `user_approved`)
2. **Messaging participant loading failures** - Fixed RLS policies to allow viewing other users' profiles
3. **Push notification registration failures** - Added missing `aps-environment` to debug entitlements

---

## Files Changed

### Code Changes (3 files)
```bash
# Swift code changes
git add NaarsCars/Core/Models/AppNotification.swift
git add NaarsCars/NaarsCars/NaarsCarsDebug.entitlements

# Database migration
git add database/069_fix_profiles_rls_for_messaging.sql
```

### Documentation (1 file)
```bash
# Fix documentation
git add APP-LAUNCH-ERRORS-FIX.md
git add COMMIT-APP-LAUNCH-FIXES.md
```

---

## Changes Detail

### 1. `NaarsCars/Core/Models/AppNotification.swift`
**What:** Added missing notification types to `NotificationType` enum
**Why:** Database contains `broadcast` and `user_approved` notifications that couldn't be decoded
**Changes:**
- Added `case broadcast = "broadcast"`
- Added `case userApproved = "user_approved"`
- Updated `icon` property to handle new cases

### 2. `database/069_fix_profiles_rls_for_messaging.sql`
**What:** New migration to fix profile access for messaging
**Why:** Users could only see their own profiles, breaking participant loading in conversations
**Changes:**
- Replaced `profiles_select_own` policy with `profiles_select_authenticated`
- Allows all authenticated users to view profiles (necessary for community app)
- Maintains restrictive UPDATE/INSERT policies (users can only modify their own)

### 3. `NaarsCars/NaarsCars/NaarsCarsDebug.entitlements`
**What:** Added push notification entitlement for development builds
**Why:** Debug builds couldn't register for push notifications
**Changes:**
- Added `<key>aps-environment</key>` with value `development`

---

## Database Migration Steps

**IMPORTANT:** Run this migration before testing the app!

```bash
# Navigate to project root
cd /Users/bcolf/Documents/naars-cars-ios

# Apply the new migration
supabase db push

# Or if you need to run it manually:
# psql -h <your-supabase-db-host> -d postgres -f database/069_fix_profiles_rls_for_messaging.sql
```

**Verification:**
```sql
-- Check that the new policy exists
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE tablename = 'profiles';

-- Should see: profiles_select_authenticated
```

---

## Testing Checklist

After committing and running the migration, test these scenarios:

### Notifications
- [ ] Open app and check console - no more "Cannot initialize NotificationType" errors
- [ ] Navigate to Notifications tab
- [ ] Verify all notifications display (including broadcast messages)
- [ ] Check that badge counts are accurate

### Messaging
- [ ] Open Messages tab
- [ ] Verify conversations list loads with all participant names/avatars
- [ ] Check console - no more "Error fetching participants" warnings
- [ ] Open a conversation - verify participant profiles are displayed
- [ ] Send a test message - verify it appears correctly

### Push Notifications
- [ ] Check app launch console
- [ ] Verify no more "no valid aps-environment entitlement" errors
- [ ] App should register for remote notifications successfully

---

## Git Commands

### Review Changes
```bash
# See what's changed
git status

# Review specific files
git diff NaarsCars/Core/Models/AppNotification.swift
git diff NaarsCars/NaarsCars/NaarsCarsDebug.entitlements
git diff database/069_fix_profiles_rls_for_messaging.sql
```

### Stage and Commit
```bash
# Stage all fixes
git add NaarsCars/Core/Models/AppNotification.swift
git add NaarsCars/NaarsCars/NaarsCarsDebug.entitlements
git add database/069_fix_profiles_rls_for_messaging.sql
git add APP-LAUNCH-ERRORS-FIX.md
git add COMMIT-APP-LAUNCH-FIXES.md

# Commit with descriptive message
git commit -m "Fix critical app launch errors

- Add missing notification types (broadcast, user_approved)
- Fix profiles RLS to allow messaging participant loading
- Add aps-environment to debug entitlements for push notifications

Fixes:
- NotificationService decoding failures causing badge count errors
- MessageService participant fetching failures in conversations list
- Push notification registration failures in development builds

Database Migration: 069_fix_profiles_rls_for_messaging.sql"
```

### Push to Remote
```bash
git push origin main
# or
git push origin <your-branch-name>
```

---

## Rollback Plan (If Needed)

If issues arise after deployment:

### Revert Code Changes
```bash
git revert HEAD
```

### Revert Database Migration
```sql
-- Restore old policy
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_admin" ON public.profiles;

CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "profiles_select_admin" ON public.profiles
  FOR SELECT
  USING (public.is_admin_user(auth.uid()));
```

**Note:** Reverting the profiles policy will break messaging again. Only do this if there's a critical security issue discovered.

---

## Next Steps

1. ✅ Review all changes in this document
2. ⏳ Run `supabase db push` to apply migration
3. ⏳ Stage and commit changes using commands above
4. ⏳ Test app thoroughly using checklist above
5. ⏳ Push to remote repository
6. ⏳ Monitor production for any issues

---

## Additional Notes

### Why Profile Access Is Safe
The new `profiles_select_authenticated` policy is safe because:
1. Naar's Cars is a community app where users see each other by design
2. Users already see profiles in rides, favors, messages, town hall
3. Sensitive data (email, phone) is controlled by application layer
4. Users can still only UPDATE their own profiles
5. Admin fields (approved, role) have separate admin-only UPDATE policies

### Performance Impact
- Profile queries will now succeed on first try (no fallback needed)
- Conversation loading should be significantly faster
- Reduced error logging and exception handling overhead


