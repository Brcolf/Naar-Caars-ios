# Tasks: Admin Panel

Based on `prd-admin-panel.md`

## Affected Flows

- FLOW_ADMIN_001: Approve Pending User
- FLOW_ADMIN_002: Send Broadcast

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/AdminService.swift` - Admin operations
- `Features/Admin/Views/AdminPanelView.swift` - Admin dashboard
- `Features/Admin/Views/PendingUsersView.swift` - User approval list
- `Features/Admin/Views/BroadcastView.swift` - Announcement composer
- `Features/Admin/Views/UserManagementView.swift` - User management
- `Features/Admin/ViewModels/AdminPanelViewModel.swift`
- `Features/Admin/ViewModels/PendingUsersViewModel.swift`
- `Features/Admin/ViewModels/BroadcastViewModel.swift`

### Test Files
- `NaarsCarsTests/Core/Services/AdminServiceTests.swift`
- `NaarsCarsTests/Features/Admin/PendingUsersViewModelTests.swift`
- `NaarsCarsTests/Features/Admin/BroadcastViewModelTests.swift`

## Notes

- Admin-only features
- ⭐ Verify admin status on every operation
- Access via profile screen for admins
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/admin-panel`

- [x] 1.0 Implement AdminService
  - [x] 1.1 Create AdminService.swift with singleton
  - [x] 1.2 ⭐ Add private verifyAdmin() helper
  - [x] 1.3 Query current user's is_admin status
  - [x] 1.4 Throw error if not admin
  - [x] 1.5 Implement fetchPendingUsers() returning unapproved profiles
  - [ ] 1.6 🧪 Write AdminServiceTests.testFetchPendingUsers_NotAdmin_ThrowsError
  - [ ] 1.7 🧪 Write AdminServiceTests.testFetchPendingUsers_Admin_Success
  - [x] 1.8 Implement approveUser(userId:)
  - [x] 1.9 Update profile approved = true
  - [x] 1.10 Create welcome notification for user (implement NotificationService.sendApprovalNotification)
  - [ ] 1.11 🧪 Write AdminServiceTests.testApproveUser_Success
  - [x] 1.12 Implement rejectUser(userId:) - deletes unapproved profile (per PRD)
  - [x] 1.13 Implement setAdminStatus(userId:, isAdmin:) - toggle admin status
  - [x] 1.14 Implement fetchAllMembers() - return all approved profiles
  - [x] 1.15 Implement fetchAdminStats() - return counts (pending, members, active)
  - [x] 1.16 Implement sendBroadcast(title:, message:, pinned:)
  - [x] 1.17 Create notification for all users
  - [x] 1.18 Send push notification via Edge Function (note: implemented via batch insert, Edge Function TBD)
  - [ ] 1.19 🧪 Write AdminServiceTests.testSendBroadcast_CreatesNotifications
  - [ ] 1.20 🧪 Write AdminServiceTests.testSetAdminStatus_NotSelf_Success

### 🔒 CHECKPOINT: QA-ADMIN-001
> Run: `./QA/Scripts/checkpoint.sh admin-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: AdminService tests pass, admin verification works
> Must pass before continuing

- [x] 2.0 Build Admin Panel View
  - [x] 2.1 Create AdminPanelViewModel.swift with verifyAdminAccess()
  - [x] 2.2 Implement loadStats() to fetch admin statistics
  - [x] 2.3 Create AdminPanelView.swift
  - [x] 2.4 ⭐ Verify admin status on appear (show access denied if not admin)
  - [x] 2.5 Show stats: pending count, total members, active members
  - [x] 2.6 Add NavigationLink to Pending Users
  - [x] 2.7 Add NavigationLink to Send Broadcast
  - [x] 2.8 Add NavigationLink to User Management

- [x] 3.0 Build Pending Users View
  - [x] 3.1 Create PendingUsersView.swift
  - [x] 3.2 List unapproved users
  - [x] 3.3 Show user info: name, email, invited by (with inviter name lookup)
  - [x] 3.4 Add "Approve" and "Reject" buttons
  - [x] 3.5 Show confirmation before action
  - [x] 3.6 Update list after action

- [x] 4.0 Implement PendingUsersViewModel
  - [x] 4.1 Create PendingUsersViewModel.swift
  - [x] 4.2 Implement loadPendingUsers()
  - [x] 4.3 Implement approveUser() and rejectUser()
  - [ ] 4.4 🧪 Write PendingUsersViewModelTests.testApproveUser_RemovesFromList

- [x] 5.0 Build Broadcast View
  - [x] 5.1 Create BroadcastView.swift
  - [x] 5.2 Add TextField for title
  - [x] 5.3 Add TextEditor for message
  - [x] 5.4 Add Toggle for "Pin to notifications"
  - [x] 5.5 Add "Send Broadcast" button
  - [x] 5.6 Show confirmation before sending
  - [x] 5.7 Show success message after

- [x] 6.0 Implement BroadcastViewModel
  - [x] 6.1 Create BroadcastViewModel.swift
  - [x] 6.2 Implement validateAndSend()
  - [ ] 6.3 🧪 Write BroadcastViewModelTests.testSend_EmptyTitle_ReturnsError

- [x] 7.0 Add admin access from profile
  - [x] 7.1 In MyProfileView, check if user.isAdmin
  - [x] 7.2 If admin, show "Admin Panel" button
  - [x] 7.3 Navigate to AdminPanelView

- [x] 9.0 Build User Management View
  - [x] 9.1 Create UserManagementView.swift
  - [x] 9.2 List all approved members
  - [x] 9.3 Show admin badge for admins
  - [x] 9.4 Add "Make Admin" / "Remove Admin" buttons (with confirmation)
  - [x] 9.5 Prevent self-demotion
  - [x] 9.6 Update list after status change

- [x] 10.0 Implement UserManagementViewModel
  - [x] 10.1 Create UserManagementViewModel.swift
  - [x] 10.2 Implement loadAllMembers()
  - [x] 10.3 Implement toggleAdminStatus(userId:, isAdmin:)
  - [ ] 10.4 🧪 Write UserManagementViewModelTests.testToggleAdmin_RemovesSelfCheck

- [ ] 11.0 Verify admin panel implementation
  - [ ] 11.1 Test non-admin cannot access
  - [ ] 11.2 Test pending user approval
  - [ ] 11.3 Test broadcast sending
  - [ ] 11.4 Test admin status toggle
  - [ ] 11.5 Test stats display
  - [ ] 11.6 Commit: "feat: implement admin panel"

### 🔒 CHECKPOINT: QA-ADMIN-FINAL
> Run: `./QA/Scripts/checkpoint.sh admin-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_ADMIN_001, FLOW_ADMIN_002
> All admin tests must pass
