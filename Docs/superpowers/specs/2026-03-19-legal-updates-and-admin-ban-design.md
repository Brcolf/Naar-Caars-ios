# Legal Doc Updates + Admin Ban Feature — Design Spec

**Date:** 2026-03-19
**Status:** Approved

---

## Overview

Two related work items:

1. **Legal document updates** — Replace Privacy Policy, Terms of Service with new versions that remove "invite-only" language, add FAQ/Contact page, and fix stale invite-only references across docs and localization.
2. **Admin ban feature** — Allow admins to restrict a user's account from the All Members panel, routing banned users to a restricted screen where they can only view their ban reason, contact support, delete their account, or sign out.

---

## Part 1: Legal Document Updates

### File Replacements

| File | Action |
|------|--------|
| `Legal/PRIVACY_POLICY.md` | Replace with new version (removes "invite-only", says "open community") |
| `Legal/TERMS_OF_SERVICE.md` | Replace with new version (Section 4 now says "open community", "application submission") |
| `Legal/FAQ.md` | Create new file with FAQ and contact info |

### Stale Reference Fixes

| File | Line(s) | Current | Updated |
|------|---------|---------|---------|
| `CLAUDE.md` | 45 | "invite-only community platform" | "community platform" (match new legal language) |
| `CLAUDE.md` | 57 | "invite-based auth and approval flows" | "open signup with admin approval flows" |
| `README.md` | 9 | "invite-only community platform" | "community platform" |
| `README.md` | 129 | "Email/password signup with invite codes" | "Email/password signup with admin approval" |
| `Localizable.xcstrings` | key `auth_create_account_needed_body` | "you'll need an invite code from a current member" | "To get started, create an account from the welcome screen." |

---

## Part 2: Admin Ban Feature

### Terminology Convention

| Context | Term |
|---------|------|
| Database columns | `is_banned`, `ban_reason`, `banned_at`, `banned_by` |
| Swift model fields | `isBanned`, `banReason`, `bannedAt`, `bannedBy` |
| AuthState enum case | `.banned` |
| Admin UI labels | "Restrict User" / "Remove Restriction" |
| Admin service methods | `banUser()` / `unbanUser()` |
| User-facing copy | "restricted" — "Your account has been restricted" |
| Localization key prefix | `banned_` (internal naming), string values say "restricted" |

### Database Migration

Add four columns to `profiles` table:

```sql
ALTER TABLE public.profiles
  ADD COLUMN is_banned BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN ban_reason TEXT,
  ADD COLUMN banned_at TIMESTAMPTZ,
  ADD COLUMN banned_by UUID REFERENCES public.profiles(id);
```

No RLS policy changes in v1 (see Enforcement Scope below).

### Profile Model Update

Add to `Profile.swift`:

```swift
let isBanned: Bool
let banReason: String?
let bannedAt: Date?
let bannedBy: UUID?
```

CodingKeys: `is_banned`, `ban_reason`, `banned_at`, `banned_by`.

**Decoding:** All four fields must use `decodeIfPresent` with defaults (`false` for `isBanned`, `nil` for the rest) in the existing custom `init(from decoder:)`. Existing cached/serialized profiles won't have these fields.

### Auth State Machine

**AuthState enum** — add `.banned` case:

```swift
enum AuthState {
    case loading
    case unauthenticated
    case needsApplication
    case pendingApproval
    case banned          // NEW
    case authenticated
}
```

**All three auth state derivation points** must use the same check order. These are:

1. `AppLaunchManager.checkAccountStatus()` — query adds `is_banned`:
   ```
   SELECT is_banned, approved, application_complete FROM profiles WHERE id = $1
   ```
2. `AppState.authState` computed property — add `isBanned` check before `approved`
3. `AuthService.checkAuthStatus()` — add `isBanned` check before `approved`

Check order (first match wins, identical in all three locations):
1. `is_banned == true` → `.banned`
2. `approved == true` → `.authenticated`
3. `!applicationComplete` → `.needsApplication`
4. else → `.pendingApproval`

**Why all three:** CLAUDE.md warns that desync between `AppState` and `AuthService` is a difficult class of bug. All three locations must agree on state derivation.

**ContentView routing** — add case:

```swift
case .ready(.banned):
    BannedAccountView()
```

**ContentView.isAuthenticated** — `.banned` is intentionally NOT included. Banned users should not trigger biometric lock or sync engine restarts.

### Banned User Experience (BannedAccountView)

Dedicated restricted screen. Follows `PendingApprovalView` pattern.

**Layout:**
- Icon: `exclamationmark.shield` (large, themed)
- Title: "Your account has been restricted" (localized key: `banned_title`)
- **Reason section**: labeled "Reason:" (localized key: `banned_reason_label`), displays `profile.banReason`
  - Fallback if nil/empty: "No reason provided. Contact support for details." (localized key: `banned_reason_fallback`)
- Body: brief text about community guidelines (localized key: `banned_body`)
- Three actions:
  1. **Contact Support** — `mailto:naarscars@gmail.com` (localized key: `banned_contact_support`)
  2. **Delete Account** — triggers existing account deletion flow (localized key: `banned_delete_account`)
  3. **Sign Out** — returns to welcome screen (localized key: `banned_sign_out`)

**Data source:** On appear, fetch current profile to get `banReason`. Follows the same pattern as `PendingApprovalView`'s status polling.

**File:** `NaarsCars/Features/Authentication/Views/BannedAccountView.swift`

### Admin Member Detail View (MemberDetailView)

New view navigated to from member rows in `UserManagementView`. Consolidates admin actions that were previously scattered.

**Layout:**
- Member info header: avatar, name, email, join date
- **Admin Actions section:**
  1. **Toggle Admin** — moved here from member row swipe action. Confirmation alert. Self-action prevented (admin cannot remove their own admin status).
  2. **Restrict User / Remove Restriction** — ban/unban toggle:
     - **Ban flow:** Taps "Restrict User" → sheet with required "Reason for restriction" text field (min 1 char trimmed, multi-line) → "Restrict" confirm button (disabled until reason non-empty) → calls `adminService.banUser(userId:reason:)`
     - **Unban flow:** Taps "Remove Restriction" → confirmation alert → calls `adminService.unbanUser(userId:)`
     - Self-action prevented (admin cannot ban themselves)
- Visual indicator if user is currently banned (e.g., "Restricted" badge)

**Files:**
- `NaarsCars/Features/Admin/Views/MemberDetailView.swift` (new)
- `NaarsCars/Features/Admin/Views/UserManagementView.swift` (update: navigate to detail instead of swipe actions)
- `NaarsCars/Features/Admin/ViewModels/UserManagementViewModel.swift` (update: add ban/unban methods)

### Admin Service

Add to `AdminService.swift`:

```swift
func banUser(userId: UUID, reason: String) async throws {
    try await verifyAdminStatus()
    guard userId != currentUserId else { throw AppError.invalidOperation("Cannot restrict your own account") }
    // Update profiles: is_banned=true, ban_reason=reason, banned_at=now, banned_by=currentUserId
    Log.security("Admin \(currentUserId) banned user \(userId): \(reason)")
    // Send push notification (best-effort)
}

func unbanUser(userId: UUID) async throws {
    try await verifyAdminStatus()
    // Update profiles: is_banned=false, ban_reason=nil, banned_at=nil, banned_by=nil
    Log.security("Admin \(currentUserId) unbanned user \(userId)")
}
```

Follows existing pattern: `verifyAdminStatus()` → prevent self-action → update profile → audit log.

**Note:** `AdminService` currently has no protocol in `Core/Protocols/`. This is a pre-existing deviation from CLAUDE.md architecture rule 4-5. Adding `AdminServiceProtocol` is deferred to a follow-up — not part of this change set. `UserManagementViewModel` already references `AdminService.shared` directly.

### Push Notification on Ban

- **On ban:** Send push notification to the banned user: "Your Naar's Cars account has been restricted. Open the app for details."
- **Best-effort only.** If the user's push token is expired or notifications disabled, they see the restricted state on next app open. No retry logic.
- **Suppression rule:** Once `is_banned = true`, the user should no longer receive standard app notifications (messages, ride updates, etc.). Implementation: the `send-notification` edge function checks `profile.is_banned` before sending — if banned, skip. This is a one-line guard addition.
- **Notification type:** Raw value: `"account_restricted"`. Add to all three registry locations: Swift `AppNotification` enum, `NotificationTypeRegistry.allTypes`, and edge function `notificationTypes.ts`. Run `scripts/validate-notification-types.sh` after.
- **No deep link payload.** The `account_restricted` push notification carries no deep link data. Tapping it opens the app, where the auth state check routes to `BannedAccountView`. No `NavigationIntent` case or `DeepLinkParser` update is needed.
- **Note:** There is a pre-existing discrepancy where `content_reported` exists in the `NotificationType` enum but is missing from `NotificationTypeRegistry.allTypes`. Do not address this in this change set.

### v1 Enforcement Strategy

Enforcement is **client-side routing only** for v1:

- **Primary gate:** Auth state routing. `is_banned` checked at launch and on app foreground. Banned users route to `BannedAccountView` and never reach `MainTabView`. No code path exists for them to call messaging, ride, favor, town hall, or reaction services.
- **No new RLS policies.** Existing RLS remains as-is (most write policies already require `approved = true`, which provides some baseline protection).
- **No service-level guards** for v1 — the user never reaches screens that call these services.
- **Future enhancement (v2):** Add `AND NOT is_banned` to write-path RLS policies on `rides`, `favors`, `messages`, `town_hall_posts`, `reviews` as defense-in-depth.

### Mid-Session Ban Handling

Lightweight approach:

- **On app foreground** (`scenePhase` change to `.active`): Add a lightweight account status re-check to the existing `onChange(of: scenePhase)` handler in `ContentView`. This is **new behavior** — no such foreground re-check exists today. The `PendingApprovalView` does its own polling internally, but the scene-phase handler only restarts sync engines. Since `checkAccountStatus()` is `private` on `AppLaunchManager`, add a new public method `recheckBanStatus()` that calls `checkAccountStatus()` internally and updates `launchManager.state` to `.banned` if needed. `ContentView`'s scenePhase handler calls this new method.
- **No realtime subscription** for ban status. Next foreground check catches it.
- **No API-call interception.** The user is routed away from all action screens.

### Account Deletion — Explicit Bypass Rule

**Invariant:** Account deletion must bypass banned-user restrictions and always remain available to the user.

**Where enforced:**
- **RPC (`delete_user_account`):** Must not check `is_banned`. If a future guard blocks banned-user writes, deletion must be explicitly exempted.
- **Service layer:** `AuthService.deleteAccount()` must not gate on `isBanned`.
- **UI (`BannedAccountView`):** Delete Account button is always enabled, never conditionally hidden or disabled.
- **Future RLS (v2):** If `AND NOT is_banned` guards are added to write-path policies, the `delete_user_account` RPC must remain `SECURITY DEFINER` and bypass those policies.

**Why:** App Store compliance — Apple requires account deletion to always be accessible. A banned user who wants to leave should be able to.

### Localization Keys

New keys for `Localizable.xcstrings`:

| Key | English Value |
|-----|---------------|
| `banned_title` | "Your account has been restricted" |
| `banned_body` | "Your account has been restricted due to a violation of our community guidelines. If you believe this is an error, please contact support." |
| `banned_reason_label` | "Reason" |
| `banned_reason_fallback` | "No reason provided. Contact support for details." |
| `banned_contact_support` | "Contact Support" |
| `banned_delete_account` | "Delete Account" |
| `banned_sign_out` | "Sign Out" |
| `admin_restrict_user` | "Restrict User" |
| `admin_remove_restriction` | "Remove Restriction" |
| `admin_restrict_reason_prompt` | "Reason for restriction" |
| `admin_restrict_reason_placeholder` | "Describe why this user is being restricted" |
| `admin_restrict_confirm` | "Restrict" |
| `admin_restrict_confirm_message` | "This will immediately restrict this user's access to the app. They will be notified." |
| `admin_remove_restriction_confirm` | "Are you sure you want to remove the restriction on this user?" |
| `admin_user_restricted_badge` | "Restricted" |
| `admin_cannot_restrict_self` | "You cannot restrict your own account" |
| `banned_push_notification` | "Your Naar's Cars account has been restricted. Open the app for details." |

### Precondition: Only Approved Users Can Be Banned

The admin "All Members" panel only shows approved users (`fetchAllMembers()` queries `approved = true`). Therefore, only approved users can be banned through this UI. Banning a user who is still in `pendingApproval` or `needsApplication` state is not a supported flow — admins should reject those users instead. `PendingApprovalView`'s polling logic does not need ban awareness.

### Unbanning Behavior

Unbanning sets `is_banned = false` and clears `ban_reason`, `banned_at`, `banned_by`. It does **not** modify the `approved` flag. If a user was `approved = true` before being banned, unbanning returns them to `.authenticated` state. The `approved` field is independent of ban state.

### Banned Users in All Members List

Banned users with `approved = true` continue to appear in the All Members list (since `fetchAllMembers()` queries `approved = true`). The `MemberDetailView` shows a "Restricted" badge for banned users and offers "Remove Restriction" instead of "Restrict User". This gives admins visibility into who is banned and the ability to unban.

### Sync Engine Lifecycle for Banned Users

Sync engines are **not started** for banned users. `performDeferredLoading()` only runs for `.authenticated` state. `BannedAccountView` uses the standard `AuthService.signOut()` path — the same one used everywhere else. Sync engine teardown is safe to invoke even when engines were never started (teardown is idempotent on un-started engines). Do not create a separate sign-out path for banned users.

### Files Changed Summary

| File | Change |
|------|--------|
| `Legal/PRIVACY_POLICY.md` | Replace |
| `Legal/TERMS_OF_SERVICE.md` | Replace |
| `Legal/FAQ.md` | Create |
| `CLAUDE.md` | Fix "invite-only" refs |
| `README.md` | Fix "invite-only" refs |
| `Localizable.xcstrings` | Fix `auth_create_account_needed_body` + add banned/admin keys |
| `supabase/migrations/` | New migration: add ban columns |
| `Profile.swift` | Add 4 fields + CodingKeys + decodeIfPresent defaults |
| `AuthService.swift` | Add `.banned` to AuthState enum + update `checkAuthStatus()` |
| `AppState.swift` | Update `authState` computed property with `isBanned` check |
| `AppLaunchManager.swift` | Update `checkAccountStatus()` to query and check `is_banned` |
| `ContentView.swift` | Add `.banned` routing case + foreground re-check in scenePhase handler |
| `BannedAccountView.swift` | Create (new file) |
| `MemberDetailView.swift` | Create (new file) |
| `UserManagementView.swift` | Update: navigate to detail view instead of swipe actions |
| `UserManagementViewModel.swift` | Add ban/unban methods |
| `AdminService.swift` | Add `banUser()` / `unbanUser()` |
| `NotificationTypeRegistry.swift` | Add `account_restricted` type |
| Edge function (`send-notification` or similar) | Add banned-user suppression check |
| Notification type registry (Swift + TS) | Add `account_restricted` type to all locations |

### Critical Invariants

| System | Invariant |
|--------|-----------|
| Ban check order | `is_banned` checked BEFORE `approved` in auth state resolution |
| Auth state sync | All three derivation points (AppLaunchManager, AppState, AuthService) use identical check order |
| Account deletion | Must bypass all banned-user write restrictions; always available |
| Terminology | Backend = "banned"; user-facing = "restricted" |
| Ban reason | Required at time of ban; displayed to banned user |
| Push on ban | Best-effort; no retry |
| Notification suppression | Banned users do not receive standard app notifications |
| Self-action prevention | Admin cannot ban themselves |
| Enforcement (v1) | Client-side routing only; RLS deferred to v2 |
