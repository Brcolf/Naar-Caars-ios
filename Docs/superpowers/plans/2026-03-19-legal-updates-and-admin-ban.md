# Legal Doc Updates + Admin Ban Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace legal documents to remove invite-only language, fix stale references across docs/strings, and add admin ban functionality that restricts users to a delete-account-only screen.

**Architecture:** New `is_banned` boolean on `profiles` table gates the auth state machine. A new `.banned` AuthState case routes to `BannedAccountView`. Admin ban/unban actions are added to `AdminService` and exposed through a new `MemberDetailView` navigated from the existing All Members list.

**Tech Stack:** SwiftUI, Supabase (Postgres + Edge Functions), MVVM, localized strings via `.xcstrings`

**Spec:** `docs/superpowers/specs/2026-03-19-legal-updates-and-admin-ban-design.md`

---

## Task 1: Replace Legal Documents

**Files:**
- Replace: `Legal/PRIVACY_POLICY.md`
- Replace: `Legal/TERMS_OF_SERVICE.md`
- Create: `Legal/FAQ.md`

- [ ] **Step 1: Replace Privacy Policy**

Replace the full contents of `Legal/PRIVACY_POLICY.md` with the new version provided by the user. The new version removes "invite-only" language and says "open community app" in Section 3.

- [ ] **Step 2: Replace Terms of Service**

Replace the full contents of `Legal/TERMS_OF_SERVICE.md` with the new version provided by the user. Section 4 now says "open community" and "application submission" instead of "invite-only access."

- [ ] **Step 3: Create FAQ page**

Create `Legal/FAQ.md` with the FAQ and contact info content provided by the user. Key entry: "How do I get an invite?" answer explains open signup with admin approval.

- [ ] **Step 4: Commit**

```bash
git add Legal/PRIVACY_POLICY.md Legal/TERMS_OF_SERVICE.md Legal/FAQ.md
git commit -m "docs(legal): replace privacy policy, terms, and add FAQ — remove invite-only language"
```

---

## Task 2: Fix Stale Invite-Only References

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

- [ ] **Step 1: Update CLAUDE.md line 45**

Change:
```
**Naar's Cars** is an invite-only community platform
```
To:
```
**Naar's Cars** is a community platform
```

- [ ] **Step 2: Update CLAUDE.md line 57**

Change:
```
invite-based auth and approval flows
```
To:
```
open signup with admin approval flows
```

- [ ] **Step 3: Update README.md line 9**

Change:
```
Naar's Cars is an invite-only community platform for neighbors to help each other with rides and favors.
```
To:
```
Naar's Cars is a community platform for neighbors to help each other with rides and favors.
```

- [ ] **Step 4: Update README.md line 129**

Change:
```
Email/password signup with invite codes
```
To:
```
Email/password signup with admin approval
```

- [ ] **Step 5: Update Localizable.xcstrings key `auth_create_account_needed_body`**

In `NaarsCars/Resources/Localizable.xcstrings`, find the key `auth_create_account_needed_body` and change its English value from:
```
Looks like you're new here! To get started, you'll need an invite code from a current member.
```
To:
```
Looks like you're new here! To get started, create an account from the welcome screen.
```

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md README.md NaarsCars/Resources/Localizable.xcstrings
git commit -m "docs: remove invite-only language from CLAUDE.md, README, and NoAccountFound string"
```

---

## Task 3: Database Migration — Add Ban Columns

**Files:**
- Create: new migration via Supabase MCP `apply_migration`

- [ ] **Step 1: Apply migration**

Use the Supabase MCP `apply_migration` tool with name `add_ban_columns_to_profiles` and the following SQL:

```sql
-- Add ban-related columns to profiles table
-- Part of admin ban feature (v1 — client-side enforcement only, no RLS changes)

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_banned BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ban_reason TEXT,
  ADD COLUMN IF NOT EXISTS banned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS banned_by UUID REFERENCES public.profiles(id);

COMMENT ON COLUMN public.profiles.is_banned IS 'Whether this user account is banned/restricted';
COMMENT ON COLUMN public.profiles.ban_reason IS 'Admin-provided reason for the ban (displayed to user)';
COMMENT ON COLUMN public.profiles.banned_at IS 'Timestamp when the ban was applied';
COMMENT ON COLUMN public.profiles.banned_by IS 'Admin user ID who applied the ban';
```

- [ ] **Step 2: Verify migration applied**

Use the Supabase MCP `execute_sql` tool to verify:
```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'profiles' AND column_name IN ('is_banned', 'ban_reason', 'banned_at', 'banned_by');
```

Expected: 4 rows returned with correct types.

---

## Task 4: Update Profile Model

**Files:**
- Modify: `NaarsCars/Core/Models/Profile.swift`

- [ ] **Step 1: Add ban fields to struct properties**

After line 19 (`let approved: Bool`), add:

```swift
    let isBanned: Bool
    let banReason: String?
    let bannedAt: Date?
    let bannedBy: UUID?
```

- [ ] **Step 2: Add CodingKeys**

After `case approved` (line 73), add:

```swift
        case isBanned = "is_banned"
        case banReason = "ban_reason"
        case bannedAt = "banned_at"
        case bannedBy = "banned_by"
```

- [ ] **Step 3: Add to memberwise init**

After `approved: Bool = false,` parameter (line 103), add parameters:

```swift
        isBanned: Bool = false,
        banReason: String? = nil,
        bannedAt: Date? = nil,
        bannedBy: UUID? = nil,
```

After `self.approved = approved` assignment (line 129), add:

```swift
        self.isBanned = isBanned
        self.banReason = banReason
        self.bannedAt = bannedAt
        self.bannedBy = bannedBy
```

- [ ] **Step 4: Add to custom decoder init**

After `approved = try container.decodeIfPresent(Bool.self, forKey: .approved) ?? false` (line 158), add:

```swift
        isBanned = try container.decodeIfPresent(Bool.self, forKey: .isBanned) ?? false
        banReason = try container.decodeIfPresent(String.self, forKey: .banReason)
        bannedAt = try container.decodeIfPresent(Date.self, forKey: .bannedAt)
        bannedBy = try container.decodeIfPresent(UUID.self, forKey: .bannedBy)
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. Fix any test fixture compile errors by adding `isBanned: false` to Profile init calls in test files if needed.

- [ ] **Step 6: Commit**

```bash
git add NaarsCars/Core/Models/Profile.swift
git commit -m "feat(model): add isBanned, banReason, bannedAt, bannedBy fields to Profile"
```

---

## Task 5: Update Auth State Machine (All Three Derivation Points)

**Files:**
- Modify: `NaarsCars/Core/Services/AuthService.swift`
- Modify: `NaarsCars/App/AppState.swift`
- Modify: `NaarsCars/App/AppLaunchManager.swift`

**CRITICAL:** All three locations must use the identical check order: `is_banned` → `approved` → `applicationComplete`.

- [ ] **Step 1: Add `.banned` case to AuthState enum**

In `AuthService.swift`, find the `AuthState` enum (search for `enum AuthState`). Add the `.banned` case before `.authenticated`:

```swift
    case banned
```

- [ ] **Step 2: Update AuthService.checkAuthStatus()**

In `AuthService.swift` method `checkAuthStatus()`, find the block (around line 72-79):

```swift
                if profile.approved {
                    return .authenticated
                } else if !profile.applicationComplete {
                    return .needsApplication
                } else {
                    return .pendingApproval
                }
```

Replace with:

```swift
                if profile.isBanned {
                    return .banned
                } else if profile.approved {
                    return .authenticated
                } else if !profile.applicationComplete {
                    return .needsApplication
                } else {
                    return .pendingApproval
                }
```

- [ ] **Step 3: Update AppState.authState computed property**

In `AppState.swift`, find the `authState` computed property (line 51-67). Replace the body after `guard let user = currentUser else { return .unauthenticated }`:

```swift
        if user.isBanned {
            return .banned
        } else if user.approved {
            return .authenticated
        } else if !user.applicationComplete {
            return .needsApplication
        } else {
            return .pendingApproval
        }
```

- [ ] **Step 4: Update AppLaunchManager.checkAccountStatus()**

In `AppLaunchManager.swift`, update the private `ProfileStatus` struct (around line 200) to add `isBanned`:

```swift
            struct ProfileStatus: Codable {
                let isBanned: Bool
                let approved: Bool
                let applicationComplete: Bool

                enum CodingKeys: String, CodingKey {
                    case isBanned = "is_banned"
                    case approved
                    case applicationComplete = "application_complete"
                }
            }
```

Update the select query (around line 214) to include `is_banned`:

```swift
                .select("is_banned, approved, application_complete")
```

Update the return logic (around line 228-234):

```swift
            if response.isBanned {
                return .banned
            } else if response.approved {
                return .authenticated
            } else if !response.applicationComplete {
                return .needsApplication
            } else {
                return .pendingApproval
            }
```

- [ ] **Step 5: Add recheckBanStatus() public method to AppLaunchManager**

After the `checkApprovalStatusOnly()` method (around line 190), add:

```swift
    /// Lightweight ban re-check for use on app foreground.
    /// If user is now banned, transitions state to .banned.
    func recheckBanStatus() async {
        guard case .ready(.authenticated) = state else { return }
        do {
            let session = try await supabase.auth.session
            guard let userId = UUID(uuidString: session.user.id.uuidString) else { return }
            let status = await checkAccountStatus(userId: userId)
            if status == .banned {
                state = .ready(.banned)
            }
        } catch {
            AppLogger.warning("launch", "Ban re-check failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 6: Build to verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. There may be switch exhaustiveness warnings — those are fixed in the next task.

- [ ] **Step 7: Commit**

```bash
git add NaarsCars/Core/Services/AuthService.swift NaarsCars/App/AppState.swift NaarsCars/App/AppLaunchManager.swift
git commit -m "feat(auth): add .banned AuthState case and update all three derivation points"
```

---

## Task 6: Update ContentView Routing + Foreground Re-check

**Files:**
- Modify: `NaarsCars/App/ContentView.swift`

- [ ] **Step 1: Add .banned routing case**

In `ContentView.swift`, inside the `switch authState` block (around line 35-54), add a case before `.authenticated`:

```swift
                    case .banned:
                        BannedAccountView()
```

This will cause a compile error until `BannedAccountView` exists (Task 8). If building incrementally, add a placeholder:
```swift
                    case .banned:
                        Text("Account restricted") // placeholder until BannedAccountView is created
```

- [ ] **Step 2: Add foreground ban re-check to scenePhase handler**

In the `.onChange(of: scenePhase)` handler (around line 104-110), add the ban re-check. The block should become:

```swift
        .onChange(of: scenePhase) { oldPhase, newPhase in
            AppLogger.info("lock", "scenePhase: \(oldPhase) → \(newPhase), lockState=\(lockManager.state)")
            if newPhase == .active, isAuthenticated {
                Task { await AuthService.shared.restartRealtimeSyncEngines() }
                Task { await launchManager.recheckBanStatus() }
            }
            lockManager.handleScenePhase(newPhase, isAuthenticated: isAuthenticated)
        }
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/App/ContentView.swift
git commit -m "feat(routing): add .banned case to ContentView + foreground ban re-check"
```

---

## Task 7: Add Localization Keys for Ban Feature

**Files:**
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add all banned/admin restriction localization keys**

Add the following keys to `Localizable.xcstrings` with `extractionState: "manual"` and English translations. Add them in alphabetical order within the file's existing JSON structure:

| Key | English Value |
|-----|---------------|
| `admin_actions_header` | `Admin Actions` |
| `admin_cannot_restrict_self` | `You cannot restrict your own account` |
| `admin_remove_restriction` | `Remove Restriction` |
| `admin_remove_restriction_confirm` | `Are you sure you want to remove the restriction on this user?` |
| `admin_restrict_confirm` | `Restrict` |
| `admin_restrict_confirm_message` | `This will immediately restrict this user's access to the app. They will be notified.` |
| `admin_restrict_reason_placeholder` | `Describe why this user is being restricted` |
| `admin_restrict_reason_prompt` | `Reason for restriction` |
| `admin_restrict_user` | `Restrict User` |
| `admin_user_restricted_badge` | `Restricted` |
| `admin_view_profile` | `View Profile` |
| `banned_body` | `Your account has been restricted due to a violation of our community guidelines. If you believe this is an error, please contact support.` |
| `banned_contact_support` | `Contact Support` |
| `banned_delete_account` | `Delete Account` |
| `banned_reason_fallback` | `No reason provided. Contact support for details.` |
| `banned_reason_label` | `Reason` |
| `banned_sign_out` | `Sign Out` |
| `banned_push_notification` | `Your Naar's Cars account has been restricted. Open the app for details.` |
| `banned_title` | `Your account has been restricted` |

Each entry follows this JSON structure pattern:
```json
    "banned_title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Your account has been restricted"
          }
        }
      }
    },
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat(l10n): add localization keys for ban/restriction feature"
```

---

## Task 8: Create BannedAccountView

**Files:**
- Create: `NaarsCars/Features/Authentication/Views/BannedAccountView.swift`

- [ ] **Step 1: Create BannedAccountView**

Create `NaarsCars/Features/Authentication/Views/BannedAccountView.swift`:

```swift
//
//  BannedAccountView.swift
//  NaarsCars
//
//  Restricted screen shown to banned users — delete account, contact support, or sign out
//

import SwiftUI

/// View displayed when a user's account has been restricted by an admin.
/// Users can only contact support, delete their account, or sign out.
struct BannedAccountView: View {
    @StateObject private var launchManager = AppLaunchManager.shared
    @State private var banReason: String?
    @State private var isLoadingReason = true
    @State private var isSigningOut = false
    @State private var isDeletingAccount = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteSuccess = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 64))
                .foregroundColor(.naarsError)

            // Title
            Text("banned_title".localized)
                .font(.naarsTitle2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Reason section
            VStack(spacing: 8) {
                Text("banned_reason_label".localized)
                    .font(.naarsHeadline)
                    .foregroundColor(.secondary)

                if isLoadingReason {
                    ProgressView()
                } else {
                    Text(banReason?.isEmpty == false ? banReason! : "banned_reason_fallback".localized)
                        .font(.naarsBody)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 32)

            // Body
            Text("banned_body".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                // Contact Support
                Button(action: {
                    if let url = URL(string: "mailto:naarscars@gmail.com") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("banned_contact_support".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.naarsPrimary)
                        .cornerRadius(12)
                }
                .accessibilityIdentifier("banned.contactSupport")

                // Delete Account
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    HStack {
                        if isDeletingAccount {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text("banned_delete_account".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.naarsError)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.naarsBackgroundSecondary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                }
                .disabled(isDeletingAccount)
                .accessibilityIdentifier("banned.deleteAccount")

                // Sign Out
                Button(action: {
                    signOut()
                }) {
                    HStack {
                        if isSigningOut {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text("banned_sign_out".localized)
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(isSigningOut)
                .accessibilityIdentifier("banned.signOut")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task {
            await loadBanReason()
        }
        .alert("profile_delete_account".localized, isPresented: $showDeleteConfirmation) {
            Button("common_cancel".localized, role: .cancel) {}
            Button("profile_delete_account_confirm".localized, role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("profile_delete_account_message".localized)
        }
        .alert("profile_account_deleted".localized, isPresented: $showDeleteSuccess) {
            Button("common_ok".localized) {
                signOut()
            }
        } message: {
            Text("profile_account_deleted_message".localized)
        }
        .alert("common_error".localized, isPresented: $showDeleteError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "common_error_occurred".localized)
        }
        .trackScreen("BannedAccount")
    }

    // MARK: - Data Loading

    private func loadBanReason() async {
        isLoadingReason = true
        do {
            let profile: Profile = try await SupabaseService.shared.client
                .from("profiles")
                .select("ban_reason")
                .eq("id", value: AuthService.shared.currentUserId?.uuidString ?? "")
                .single()
                .execute()
                .value
            banReason = profile.banReason
        } catch {
            AppLogger.warning("auth", "Failed to load ban reason: \(error.localizedDescription)")
            banReason = nil
        }
        isLoadingReason = false
    }

    // MARK: - Actions

    private func deleteAccount() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        isDeletingAccount = true
        do {
            try await ProfileService.shared.deleteAccount(userId: userId)
            isDeletingAccount = false
            showDeleteSuccess = true
        } catch {
            isDeletingAccount = false
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
        }
    }

    private func signOut() {
        Task {
            isSigningOut = true
            do {
                try await AuthService.shared.signOut()
                await launchManager.performCriticalLaunch()
            } catch {
                AppLogger.warning("auth", "Error signing out: \(error.localizedDescription)")
                launchManager.state = .ready(.unauthenticated)
            }
            isSigningOut = false
        }
    }
}

#Preview {
    BannedAccountView()
}
```

- [ ] **Step 2: Remove placeholder from ContentView if used**

If Task 6 Step 1 used a `Text("Account restricted")` placeholder, replace it now with `BannedAccountView()`.

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/Features/Authentication/Views/BannedAccountView.swift
git commit -m "feat(auth): add BannedAccountView — restricted screen with delete, support, sign out"
```

---

## Task 9: Add Ban/Unban Methods to AdminService

**Files:**
- Modify: `NaarsCars/Core/Services/AdminService.swift`

- [ ] **Step 1: Add banUser method**

Add after the `setAdminStatus` method (around line 390), before the `// MARK: - Broadcast` section:

```swift
    /// Ban/restrict a user account
    /// - Parameters:
    ///   - userId: ID of user to ban
    ///   - reason: Required reason for the ban (displayed to the user)
    /// - Throws: AppError if not admin, attempting self-ban, or operation fails
    func banUser(userId: UUID, reason: String) async throws {
        try await verifyAdminStatus()

        guard userId != authService.currentUserId else {
            throw AppError.unknown("Cannot restrict your own account")
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw AppError.unknown("A reason is required to restrict a user")
        }

        guard let adminId = authService.currentUserId else {
            throw AppError.unauthorized
        }

        let updates: [String: AnyCodable] = [
            "is_banned": AnyCodable(true),
            "ban_reason": AnyCodable(trimmedReason),
            "banned_at": AnyCodable(ISO8601DateFormatter().string(from: Date())),
            "banned_by": AnyCodable(adminId.uuidString),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]

        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId.uuidString)
            .execute()

        Log.security("Admin \(adminId) banned user \(userId): \(trimmedReason)")
        AppLogger.info("admin", "Banned user \(userId)")

        // Send push notification (best-effort via notification_queue → send-notification edge function)
        // If notification_queue doesn't exist or uses a different schema, inspect the existing
        // notification send pattern at implementation time and adapt accordingly.
        let bannedUserIdString = userId.uuidString
        Task.detached {
            do {
                let client = await SupabaseService.shared.client
                try await client
                    .from("notifications")
                    .insert([
                        "user_id": AnyCodable(bannedUserIdString),
                        "type": AnyCodable("account_restricted"),
                        "title": AnyCodable("Naar's Cars"),
                        "body": AnyCodable("Your Naar's Cars account has been restricted. Open the app for details."),
                    ])
                    .execute()
            } catch {
                // Best-effort — user will see restricted state on next app open
                await AppLogger.warning("admin", "Failed to queue ban notification: \(error.localizedDescription)")
            }
        }
    }

    /// Unban/remove restriction from a user account
    /// - Parameter userId: ID of user to unban
    /// - Throws: AppError if not admin or operation fails
    func unbanUser(userId: UUID) async throws {
        try await verifyAdminStatus()

        let updates: [String: AnyCodable] = [
            "is_banned": AnyCodable(false),
            "ban_reason": AnyCodable(NSNull()),
            "banned_at": AnyCodable(NSNull()),
            "banned_by": AnyCodable(NSNull()),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]

        try await supabase
            .from("profiles")
            .update(updates)
            .eq("id", value: userId.uuidString)
            .execute()

        Log.security("Admin \(authService.currentUserId?.uuidString ?? "unknown") unbanned user \(userId)")
        AppLogger.info("admin", "Unbanned user \(userId)")
    }
```

**Note on push notification:** The ban notification is inserted into the `notifications` table (or `notification_queue` — check which table the existing notification pipeline uses at implementation time by grepping for how `send_broadcast_notifications` or other notification RPCs insert records). The `send-notification` edge function processes queued notifications. The push is best-effort — failure does not fail the ban operation. The user sees the restricted state on next app open regardless.

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Core/Services/AdminService.swift
git commit -m "feat(admin): add banUser() and unbanUser() methods to AdminService"
```

---

## Task 10: Add Ban/Unban to UserManagementViewModel

**Files:**
- Modify: `NaarsCars/Features/Admin/ViewModels/UserManagementViewModel.swift`

- [ ] **Step 1: Add ban/unban methods**

Add after the `canChangeAdminStatus` method (around line 78):

```swift
    /// Ban a user with a required reason
    func banUser(userId: UUID, reason: String) async {
        error = nil

        guard userId != authService.currentUserId else {
            error = AppError.unknown("admin_cannot_restrict_self".localized)
            return
        }

        do {
            try await adminService.banUser(userId: userId, reason: reason)
            HapticManager.success()
            await loadAllMembers()
            AppLogger.info("admin", "Successfully banned user \(userId)")
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error banning user: \(error.localizedDescription)")
        }
    }

    /// Remove ban/restriction from a user
    func unbanUser(userId: UUID) async {
        error = nil

        do {
            try await adminService.unbanUser(userId: userId)
            HapticManager.success()
            await loadAllMembers()
            AppLogger.info("admin", "Successfully unbanned user \(userId)")
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error unbanning user: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/Features/Admin/ViewModels/UserManagementViewModel.swift
git commit -m "feat(admin): add ban/unban methods to UserManagementViewModel"
```

---

## Task 11: Create MemberDetailView + Update UserManagementView Navigation

**Files:**
- Create: `NaarsCars/Features/Admin/Views/MemberDetailView.swift`
- Modify: `NaarsCars/Features/Admin/Views/UserManagementView.swift`

- [ ] **Step 1: Create MemberDetailView**

Create `NaarsCars/Features/Admin/Views/MemberDetailView.swift`:

```swift
//
//  MemberDetailView.swift
//  NaarsCars
//
//  Admin detail view for a member — toggle admin, restrict/unrestrict
//

import SwiftUI

/// Admin detail view for managing a single member.
/// Consolidates admin actions: toggle admin status, ban/unban.
struct MemberDetailView: View {
    let member: Profile
    @ObservedObject var viewModel: UserManagementViewModel

    @State private var showAdminConfirmation = false
    @State private var showBanSheet = false
    @State private var showUnbanConfirmation = false
    @State private var banReason = ""
    @State private var toastMessage: String?

    private var isSelf: Bool {
        member.id == AuthService.shared.currentUserId
    }

    var body: some View {
        List {
            // Member info header
            Section {
                HStack(spacing: 16) {
                    AvatarView(
                        imageUrl: member.avatarUrl,
                        name: member.name,
                        size: 64,
                        userId: member.id
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(member.name)
                                .font(.naarsTitle3)
                                .fontWeight(.semibold)

                            if member.isAdmin {
                                Text("admin_badge".localized)
                                    .font(.naarsCaption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.naarsPrimary)
                                    .cornerRadius(6)
                            }

                            if member.isBanned {
                                Text("admin_user_restricted_badge".localized)
                                    .font(.naarsCaption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.naarsError)
                                    .cornerRadius(6)
                            }
                        }

                        Text(member.email)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)

                        Text("Joined \(member.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Admin actions
            if !isSelf {
                Section("admin_actions_header".localized) {
                    // Toggle Admin
                    Button(action: {
                        showAdminConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: member.isAdmin ? "person.badge.minus" : "person.badge.shield.checkmark")
                                .foregroundColor(member.isAdmin ? .naarsError : .naarsPrimary)
                            Text(member.isAdmin ? "admin_remove_admin".localized : "admin_make_admin".localized)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }

                    // Ban / Unban
                    if member.isBanned {
                        Button(action: {
                            showUnbanConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "checkmark.shield")
                                    .foregroundColor(.green)
                                Text("admin_remove_restriction".localized)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    } else {
                        Button(action: {
                            banReason = ""
                            showBanSheet = true
                        }) {
                            HStack {
                                Image(systemName: "exclamationmark.shield")
                                    .foregroundColor(.naarsError)
                                Text("admin_restrict_user".localized)
                                    .foregroundColor(.naarsError)
                                Spacer()
                            }
                        }
                    }
                }
            }

            // View public profile link
            Section {
                NavigationLink(destination: PublicProfileView(userId: member.id)) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text("admin_view_profile".localized)
                    }
                }
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        // Admin toggle confirmation
        .alert(
            member.isAdmin ? "admin_remove_admin".localized : "admin_make_admin".localized,
            isPresented: $showAdminConfirmation
        ) {
            Button("common_cancel".localized, role: .cancel) {}
            Button(
                member.isAdmin ? "admin_remove_admin".localized : "admin_make_admin".localized,
                role: member.isAdmin ? .destructive : .none
            ) {
                Task {
                    await viewModel.toggleAdminStatus(userId: member.id, isAdmin: !member.isAdmin)
                    if viewModel.error == nil {
                        toastMessage = "toast_admin_status_updated".localized
                    }
                }
            }
        } message: {
            Text(member.isAdmin ? "admin_remove_admin_confirmation".localized : "admin_make_admin_confirmation".localized)
        }
        // Unban confirmation
        .alert("admin_remove_restriction".localized, isPresented: $showUnbanConfirmation) {
            Button("common_cancel".localized, role: .cancel) {}
            Button("admin_remove_restriction".localized) {
                Task {
                    await viewModel.unbanUser(userId: member.id)
                    if viewModel.error == nil {
                        toastMessage = "admin_remove_restriction".localized
                    }
                }
            }
        } message: {
            Text("admin_remove_restriction_confirm".localized)
        }
        // Ban reason sheet
        .sheet(isPresented: $showBanSheet) {
            NavigationStack {
                Form {
                    Section {
                        Text("admin_restrict_confirm_message".localized)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }

                    Section("admin_restrict_reason_prompt".localized) {
                        TextField(
                            "admin_restrict_reason_placeholder".localized,
                            text: $banReason,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                    }
                }
                .navigationTitle("admin_restrict_user".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common_cancel".localized) {
                            showBanSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("admin_restrict_confirm".localized) {
                            showBanSheet = false
                            Task {
                                await viewModel.banUser(userId: member.id, reason: banReason)
                                if viewModel.error == nil {
                                    toastMessage = "admin_restrict_user".localized
                                }
                            }
                        }
                        .disabled(banReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .toast(message: $toastMessage)
    }
}
```

- [ ] **Step 2: Update UserManagementView to navigate to MemberDetailView**

In `UserManagementView.swift`, replace the `NavigationLink` destination and remove the `MemberRow` toggle admin callback. The list `ForEach` block (around line 32-45) should become:

```swift
                    List {
                        ForEach(viewModel.members) { member in
                            NavigationLink(destination: MemberDetailView(member: member, viewModel: viewModel)) {
                                MemberRow(member: member)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .listStyle(.plain)
```

Remove the admin toggle confirmation alert (lines 58-85) since admin toggling is now in `MemberDetailView`.

Update `MemberRow` to remove `canChangeAdmin` and `onToggleAdmin` — simplify it to just show info + badges:

```swift
/// Row component for member
private struct MemberRow: View {
    let member: Profile

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                imageUrl: member.avatarUrl,
                name: member.name,
                size: 44,
                userId: member.id
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name)
                        .font(.naarsHeadline)

                    if member.isAdmin {
                        Text("admin_badge".localized)
                            .font(.naarsCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.naarsPrimary)
                            .cornerRadius(8)
                    }

                    if member.isBanned {
                        Text("admin_user_restricted_badge".localized)
                            .font(.naarsCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.naarsError)
                            .cornerRadius(8)
                    }
                }

                Text(member.email)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}
```

Also remove the now-unused `@State` properties at the top: `userToToggle`, `targetAdminStatus`, `showingToggleConfirmation`.

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/Features/Admin/Views/MemberDetailView.swift NaarsCars/Features/Admin/Views/UserManagementView.swift
git commit -m "feat(admin): add MemberDetailView with ban/unban, simplify UserManagementView"
```

---

## Task 12: Update Notification Type Registry

**Files:**
- Modify: `NaarsCars/Core/Models/AppNotification.swift`
- Modify: `NaarsCars/Core/Models/NotificationTypeRegistry.swift`
- Modify: `supabase/functions/_shared/notificationTypes.ts`

- [ ] **Step 1: Add to NotificationType enum**

In `AppNotification.swift`, after `case userRejected = "user_rejected"` (line 63), add:

```swift
    // Account restriction
    case accountRestricted = "account_restricted"
```

- [ ] **Step 2: Add to NotificationTypeRegistry**

In `NotificationTypeRegistry.swift`, add `"account_restricted"` to the `allTypes` set, after `"user_rejected"`:

```swift
        "account_restricted",
```

- [ ] **Step 3: Add to notificationTypes.ts**

In `supabase/functions/_shared/notificationTypes.ts`, add after the `USER_REJECTED` line (line 30):

```typescript
  ACCOUNT_RESTRICTED: 'account_restricted',
```

- [ ] **Step 4: Run validation script**

```bash
scripts/validate-notification-types.sh
```

Expected: Script passes (or reports only pre-existing `content_reported` discrepancy which is not part of this change set).

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add NaarsCars/Core/Models/AppNotification.swift NaarsCars/Core/Models/NotificationTypeRegistry.swift supabase/functions/_shared/notificationTypes.ts
git commit -m "feat(notifications): add account_restricted notification type to all registries"
```

---

## Task 13: Add Banned-User Suppression to Edge Function

**Files:**
- Modify: `supabase/functions/send-notification/index.ts`

- [ ] **Step 1: Add banned-user check**

In `send-notification/index.ts`, find the section where the function looks up the recipient's profile or device token before sending. Add a guard that checks `is_banned`:

After fetching the recipient's profile/token, before sending the push, add:

```typescript
    // Skip notifications for banned users (except account_restricted which is the ban notification itself)
    if (notification.notification_type !== NOTIFICATION_TYPES.ACCOUNT_RESTRICTED) {
      const { data: recipientProfile } = await supabaseClient
        .from('profiles')
        .select('is_banned')
        .eq('id', notification.recipient_user_id)
        .single()

      if (recipientProfile?.is_banned) {
        console.log(`Skipping notification for banned user: ${notification.recipient_user_id}`)
        continue // or return, depending on the loop structure
      }
    }
```

**Note:** The exact insertion point depends on the function's structure. Read the full `index.ts` at implementation time to find where the recipient lookup happens and add this check there. The key invariant is: banned users get no notifications except the `account_restricted` ban notification itself.

- [ ] **Step 2: Deploy edge function**

Use the Supabase MCP `deploy_edge_function` tool to deploy the updated `send-notification` function.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/send-notification/index.ts
git commit -m "feat(edge): suppress notifications for banned users in send-notification"
```

---

## Task 14: Final Build Verification

- [ ] **Step 1: Full clean build**

```bash
scripts/CLEAR-XCODE-CACHE.sh
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED with no errors.

- [ ] **Step 2: Run tests**

```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

Fix any test failures caused by the new `isBanned` field in Profile init calls in test fixtures. Add `isBanned: false` to any failing test fixtures.

- [ ] **Step 3: Verify notification type sync**

```bash
scripts/validate-notification-types.sh
```

- [ ] **Step 4: Commit any test fixes**

```bash
git add -A
git commit -m "fix(tests): update test fixtures for new Profile ban fields"
```
