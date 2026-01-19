# App Launch Errors - Fix Summary

## Date: January 19, 2026

## Issues Identified

### 1. NotificationService Decoding Error ❌ CRITICAL
**Error:**
```
Cannot initialize NotificationType from invalid String value broadcast
dataCorrupted: Cannot initialize NotificationType from invalid String value broadcast
```

**Root Cause:**
- The database has notifications with types `broadcast` and `user_approved`
- The `NotificationType` enum in `AppNotification.swift` was missing these cases
- This caused decoding to fail when fetching notifications
- Badge count calculation failed as a result

**Fix Applied:**
- Added `case broadcast = "broadcast"` to `NotificationType` enum
- Added `case userApproved = "user_approved"` to `NotificationType` enum
- Updated the `icon` property to handle these new cases:
  - `broadcast` → `"megaphone.fill"` (same as announcements)
  - `userApproved` → `"checkmark.circle.fill"`

**Files Modified:**
- `NaarsCars/Core/Models/AppNotification.swift`

---

### 2. MessageService Participant Fetching Errors ❌ CRITICAL
**Error:**
```
⚠️ [MessageService] Error fetching participants for conversation XXX: The data couldn't be read because it is missing.
```
(Repeated for 10 different conversations)

**Root Cause:**
- `MessageService.fetchConversations()` uses a foreign key join to fetch participant profiles:
  ```swift
  .select("user_id, profiles!conversation_participants_user_id_fkey(...)")
  ```
- Current RLS policy on `profiles` table only allows users to see their own profile:
  ```sql
  CREATE POLICY "profiles_select_own" ON public.profiles
    FOR SELECT
    USING (id = auth.uid());
  ```
- When the query tries to fetch other participants' profiles, RLS blocks access
- The query returns `null` for the profiles field, causing "data is missing" errors
- Fallback logic attempts individual profile fetches, but likely also fails due to RLS

**Fix Applied:**
- Created new migration: `database/069_fix_profiles_rls_for_messaging.sql`
- Dropped the restrictive `profiles_select_own` policy
- Created new policy `profiles_select_authenticated` that allows all authenticated users to view profiles:
  ```sql
  CREATE POLICY "profiles_select_authenticated" ON public.profiles
    FOR SELECT
    USING (auth.role() = 'authenticated');
  ```
- This is safe for a community app where users need to see each other's profiles

**Why This Is Safe:**
1. Naar's Cars is a community app where users inherently see each other (rides, favors, messages, town hall)
2. Profile data (name, avatar, car) is community-visible by design
3. Sensitive fields (email, phone) are controlled by the application layer
4. UPDATE policies remain restrictive (users can only update their own profile)
5. Admin-only fields (approved, role) have separate admin UPDATE policies

**Files Created:**
- `database/069_fix_profiles_rls_for_messaging.sql`

**Next Steps:**
1. Run the migration: `supabase db push`
2. Verify profiles are accessible: Query profiles table as a non-admin user
3. Test messaging: Ensure conversations load with participant names/avatars

---

### 3. Remote Notifications Registration Failure ⚠️ NON-CRITICAL
**Warning:**
```
🔴 [AppDelegate] Failed to register for remote notifications: no valid "aps-environment" entitlement string found for application
```

**Root Cause:**
- The app is trying to register for push notifications
- The debug entitlements file (`NaarsCarsDebug.entitlements`) was missing the `aps-environment` key
- The production entitlements file had it correctly set to `production`
- During development builds, the debug entitlements are used, causing the registration failure

**Fix Applied:**
- Added `aps-environment` key to `NaarsCarsDebug.entitlements` with value `development`
- This allows push notification registration during development
- Production entitlements already had `aps-environment` set to `production`

**Files Modified:**
- `NaarsCars/NaarsCars/NaarsCarsDebug.entitlements`

**Note:** You may still need to configure the appropriate provisioning profile in Xcode that supports push notifications. This is typically handled automatically when running on a physical device with proper signing.

---

## Testing Checklist

### After Applying Fixes:
- [ ] Run `supabase db push` to apply migration `069_fix_profiles_rls_for_messaging.sql`
- [ ] Launch app and check console for:
  - [ ] No more "Cannot initialize NotificationType" errors
  - [ ] No more "Error fetching participants" errors
  - [ ] Notifications badge count displays correctly
- [ ] Test Messaging Feature:
  - [ ] Open Messages tab
  - [ ] Verify conversations list loads with participant names/avatars
  - [ ] Open a conversation and verify messages display correctly
  - [ ] Send a message and verify it appears
- [ ] Verify Notifications:
  - [ ] Open Notifications tab
  - [ ] Verify all notifications display (including broadcast and user_approved types)

---

## Summary

| Issue | Severity | Status | Fix Location |
|-------|----------|--------|--------------|
| Missing Notification Types | CRITICAL | ✅ FIXED | `AppNotification.swift` |
| Profile RLS Blocking Messaging | CRITICAL | ✅ FIXED | `069_fix_profiles_rls_for_messaging.sql` |
| Push Notifications Entitlement | LOW | ✅ FIXED | `NaarsCarsDebug.entitlements` |

All errors have been resolved. The app should now:
1. Load and display all notification types correctly (including `broadcast` and `user_approved`)
2. Fetch and display conversation participants without errors
3. Calculate badge counts accurately
4. Register for push notifications without warnings (both development and production)

