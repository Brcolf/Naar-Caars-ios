# PRD: Admin Panel

## Document Information
- **Feature Name**: Admin Panel
- **Phase**: 4 (Administration)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`
- **Estimated Effort**: 0.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

The Admin Panel allows designated admins to manage the community: approving new users, sending broadcasts, and viewing member information.

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| View pending approvals | List of unapproved users |
| Approve users | User status changes |
| View all members | Complete member list |
| Toggle admin status | Promote/demote admins |
| Send broadcasts | Notifications sent |

---

## 3. Functional Requirements

### 3.1 Access Control

**Requirement ADMIN-FR-001**: Admin panel ONLY accessible to users with `is_admin = true`.

**Requirement ADMIN-FR-002**: Non-admins see no link to admin panel.

### 3.2 Admin Panel View

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   ðŸ›¡ï¸ Admin Panel                    â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   Stats                             â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”      â”‚
â”‚   â”‚   3    â”‚   25   â”‚   12   â”‚      â”‚
â”‚   â”‚Pending â”‚Members â”‚ Active â”‚      â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”˜      â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   ðŸ“¢ Send Announcement              â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Title                       â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Message...                  â”‚   â”‚
â”‚   â”‚                             â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   â˜‘ï¸ Pin to notifications (7 days)  â”‚
â”‚   [Send Announcement]               â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   â³ Pending Approvals              â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar] New User           â”‚   â”‚
â”‚   â”‚ newuser@email.com           â”‚   â”‚
â”‚   â”‚ Invited by: John S.         â”‚   â”‚
â”‚   â”‚            [Approve]        â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ [Avatar] Another User       â”‚   â”‚
â”‚   â”‚ another@email.com           â”‚   â”‚
â”‚   â”‚ Invited by: Jane D. (SMS)   â”‚   â”‚
â”‚   â”‚            [Approve]        â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   ðŸ‘¥ All Members                    â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ [Avatar] Bob M.      [Admin]â”‚   â”‚
â”‚   â”‚ bob@email.com               â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ [Avatar] Jane D.            â”‚   â”‚
â”‚   â”‚ jane@email.com   [Make Adminâ”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### 3.3 User Approval

**Flow:**
1. Admin sees pending user
2. Reviews name, email, who invited them
3. Taps "Approve"
4. Confirmation dialog
5. User's `approved` set to `true`
6. User notified they're approved
7. User can now access the app

### 3.4 Toggle Admin Status

- Admins can promote other users to admin
- Admins can demote other admins (except themselves)
- Confirmation required

### 3.5 Broadcast Announcements

**Options:**
- **Push only**: Send push notification to all users with notifications enabled
- **Pin to notifications**: Also adds to everyone's notification feed, pinned for 7 days

**Payload:**
```swift
struct BroadcastRequest {
    let title: String
    let message: String
    let pinToNotifications: Bool
}
```

---

## 4. Non-Goals

- User deletion
- Viewing user activity logs
- Request moderation
- Invite code management (in profile)

---

## 5. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-authentication.md`
- `prd-notifications-push.md`

---

*End of PRD: Admin Panel*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 3.1 - Access Control

**Replace existing access control with defense-in-depth:**

```markdown
### 3.1 Access Control

**Requirement ADMIN-FR-001**: Admin panel access MUST be enforced at multiple layers:

#### Layer 1: Client-Side UI (Convenience Only)

```swift
// In MainTabView or navigation
@ViewBuilder
var adminTab: some View {
    if AuthService.shared.currentProfile?.isAdmin == true {
        NavigationLink(destination: AdminPanelView()) {
            Label("Admin", systemImage: "shield")
        }
    }
}
```

**Important**: This is for UX convenience only, NOT security. A modified client could bypass this.

#### Layer 2: Server-Side RLS (Required Security)

All admin operations MUST have RLS policies verifying admin status:

```sql
-- Only admins can update other users' approved status
CREATE POLICY "admin_approve_users" ON public.profiles
  FOR UPDATE
  USING (
    auth.uid() = id  -- Users can update own profile
    OR EXISTS (      -- OR user is admin
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND is_admin = true
    )
  );

-- Prevent non-admins from setting is_admin
CREATE POLICY "admin_only_set_admin" ON public.profiles
  FOR UPDATE
  USING (true)
  WITH CHECK (
    -- If is_admin is being set to true, user must be admin
    (is_admin = false) 
    OR EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND is_admin = true
    )
  );
```

#### Layer 3: Client-Side Verification (Defense in Depth)

**Requirement ADMIN-FR-001a**: Before performing any admin operation, re-verify admin status:

```swift
// Core/Services/AdminService.swift
@MainActor
final class AdminService {
    static let shared = AdminService()
    private let supabase = SupabaseService.shared.client
    
    /// Verify current user is admin before any admin operation
    /// This is defense-in-depth - RLS is the real security
    private func verifyAdminStatus() async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw AppError.unauthorized
        }
        
        // Fresh check from server, not cached
        let response = try await supabase
            .from("profiles")
            .select("is_admin")
            .eq("id", userId.uuidString)
            .single()
            .execute()
        
        struct AdminCheck: Decodable {
            let isAdmin: Bool
            enum CodingKeys: String, CodingKey {
                case isAdmin = "is_admin"
            }
        }
        
        let check = try JSONDecoder().decode(AdminCheck.self, from: response.data)
        
        guard check.isAdmin else {
            Log.security("Non-admin attempted admin operation: \(userId)")
            throw AppError.unauthorized
        }
    }
    
    // MARK: - Admin Operations
    
    func approveUser(userId: UUID) async throws {
        try await verifyAdminStatus()
        
        try await supabase
            .from("profiles")
            .update(["approved": true])
            .eq("id", userId.uuidString)
            .execute()
        
        Log.security("Admin approved user: \(userId)")
        
        // Send welcome notification
        try await NotificationService.shared.sendApprovalNotification(to: userId)
    }
    
    func rejectUser(userId: UUID) async throws {
        try await verifyAdminStatus()
        
        // Delete the pending profile
        try await supabase
            .from("profiles")
            .delete()
            .eq("id", userId.uuidString)
            .eq("approved", false) // Safety: only delete unapproved
            .execute()
        
        Log.security("Admin rejected user: \(userId)")
    }
    
    func setAdminStatus(userId: UUID, isAdmin: Bool) async throws {
        try await verifyAdminStatus()
        
        // Prevent self-demotion
        guard userId != AuthService.shared.currentUserId else {
            throw AppError.unknown("Cannot change your own admin status")
        }
        
        try await supabase
            .from("profiles")
            .update(["is_admin": isAdmin])
            .eq("id", userId.uuidString)
            .execute()
        
        Log.security("Admin set admin status for \(userId): \(isAdmin)")
    }
    
    func sendBroadcast(title: String, message: String, pinToNotifications: Bool) async throws {
        try await verifyAdminStatus()
        
        // Get all approved user IDs
        let response = try await supabase
            .from("profiles")
            .select("id")
            .eq("approved", true)
            .execute()
        
        struct UserIdOnly: Decodable { let id: UUID }
        let users = try JSONDecoder().decode([UserIdOnly].self, from: response.data)
        
        // Create notifications for all users
        let notifications = users.map { user in
            [
                "user_id": user.id.uuidString,
                "title": title,
                "message": message,
                "type": "broadcast",
                "is_pinned": pinToNotifications
            ]
        }
        
        try await supabase
            .from("notifications")
            .insert(notifications)
            .execute()
        
        Log.security("Admin sent broadcast to \(users.count) users")
        
        // Trigger push notifications via Edge Function
        // ...
    }
}
```

**Requirement ADMIN-FR-001b**: Admin operations MUST fail gracefully if authorization check fails:

```swift
func handleAdminOperation(_ operation: @escaping () async throws -> Void) async {
    do {
        try await operation()
    } catch AppError.unauthorized {
        // Generic error - don't reveal why
        showError("You don't have permission to perform this action")
        Log.security("Unauthorized admin operation attempt")
    } catch {
        showError("Operation failed. Please try again.")
    }
}
```

**Requirement ADMIN-FR-002** (existing): Non-admins see no link to admin panel.

**Requirement ADMIN-FR-002a**: If non-admin somehow navigates to admin panel:

```swift
struct AdminPanelView: View {
    @StateObject private var viewModel = AdminPanelViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if viewModel.isVerifyingAdmin {
                ProgressView("Verifying access...")
            } else if viewModel.isAdmin {
                adminContent
            } else {
                // Unauthorized - show nothing useful
                VStack {
                    Image(systemName: "lock.shield")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Access Denied")
                        .font(.headline)
                }
                .onAppear {
                    Log.security("Non-admin accessed admin panel view")
                    // Redirect after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.verifyAdminAccess()
        }
    }
}
```
```

---

## ADD: Section 6.1 - Security Logging

**Insert in Security section or create new**

```markdown
### 6.1 Security Logging

**Requirement ADMIN-SEC-001**: Log all admin operation attempts:

```swift
// All admin operations should log
Log.security("Admin operation: \(operationName) by \(userId) - \(success ? "SUCCESS" : "DENIED")")
```

**Requirement ADMIN-SEC-002**: Events to log:

| Event | Log Entry |
|-------|-----------|
| User approved | "Admin approved user: {userId}" |
| User rejected | "Admin rejected user: {userId}" |
| Admin status changed | "Admin set admin status for {userId}: {true/false}" |
| Broadcast sent | "Admin sent broadcast to {count} users" |
| Unauthorized attempt | "Non-admin attempted admin operation: {userId}" |
| Admin panel accessed by non-admin | "Non-admin accessed admin panel view" |

**Requirement ADMIN-SEC-003**: Security log review:
- Logs should be reviewed periodically
- Watch for patterns of unauthorized attempts
- Multiple failures from same user may indicate attack
```

---

## ADD: Section 6.2 - RLS Policies

**Insert after security logging**

```markdown
### 6.2 Required RLS Policies

See `SECURITY.md` for complete RLS requirements. Admin-specific policies:

```sql
-- Admin can view all profiles (including unapproved)
CREATE POLICY "admin_view_all_profiles" ON public.profiles
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
    OR auth.uid() = id
    OR approved = true
  );

-- Admin can update any profile's approved status
CREATE POLICY "admin_approve" ON public.profiles
  FOR UPDATE USING (
    auth.uid() = id
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- Admin can delete unapproved profiles (rejection)
CREATE POLICY "admin_reject" ON public.profiles
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
    AND approved = false
  );

-- Admin can insert broadcast notifications
CREATE POLICY "admin_broadcast" ON public.notifications
  FOR INSERT WITH CHECK (
    type != 'broadcast'
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
  );
```
```

---

*End of Admin Panel Addendum*
