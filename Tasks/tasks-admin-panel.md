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

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/admin-panel`

- [ ] 1.0 Implement AdminService
  - [ ] 1.1 Create AdminService.swift with singleton
  - [ ] 1.2 ⭐ Add private verifyAdmin() helper
  - [ ] 1.3 Query current user's is_admin status
  - [ ] 1.4 Throw error if not admin
  - [ ] 1.5 Implement fetchPendingUsers() returning unapproved profiles
  - [ ] 1.6 🧪 Write AdminServiceTests.testFetchPendingUsers_NotAdmin_ThrowsError
  - [ ] 1.7 🧪 Write AdminServiceTests.testFetchPendingUsers_Admin_Success
  - [ ] 1.8 Implement approveUser(userId:)
  - [ ] 1.9 Update profile approved = true
  - [ ] 1.10 Create welcome notification for user
  - [ ] 1.11 🧪 Write AdminServiceTests.testApproveUser_Success
  - [ ] 1.12 Implement rejectUser(userId:) - marks rejected, doesn't delete
  - [ ] 1.13 Implement sendBroadcast(title:, message:, pinned:)
  - [ ] 1.14 Create notification for all users
  - [ ] 1.15 Send push notification
  - [ ] 1.16 🧪 Write AdminServiceTests.testSendBroadcast_CreatesNotifications

### 🔒 CHECKPOINT: QA-ADMIN-001
> Run: `./QA/Scripts/checkpoint.sh admin-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: AdminService tests pass, admin verification works
> Must pass before continuing

- [ ] 2.0 Build Admin Panel View
  - [ ] 2.1 Create AdminPanelView.swift
  - [ ] 2.2 ⭐ Verify admin status on appear
  - [ ] 2.3 Add NavigationLink to Pending Users
  - [ ] 2.4 Add NavigationLink to Send Broadcast
  - [ ] 2.5 Add NavigationLink to User Management
  - [ ] 2.6 Show stats: total users, pending, etc.

- [ ] 3.0 Build Pending Users View
  - [ ] 3.1 Create PendingUsersView.swift
  - [ ] 3.2 List unapproved users
  - [ ] 3.3 Show user info: name, email, invited by
  - [ ] 3.4 Add "Approve" and "Reject" buttons
  - [ ] 3.5 Show confirmation before action
  - [ ] 3.6 Update list after action

- [ ] 4.0 Implement PendingUsersViewModel
  - [ ] 4.1 Create PendingUsersViewModel.swift
  - [ ] 4.2 Implement loadPendingUsers()
  - [ ] 4.3 Implement approveUser() and rejectUser()
  - [ ] 4.4 🧪 Write PendingUsersViewModelTests.testApproveUser_RemovesFromList

- [ ] 5.0 Build Broadcast View
  - [ ] 5.1 Create BroadcastView.swift
  - [ ] 5.2 Add TextField for title
  - [ ] 5.3 Add TextEditor for message
  - [ ] 5.4 Add Toggle for "Pin to notifications"
  - [ ] 5.5 Add "Send Broadcast" button
  - [ ] 5.6 Show confirmation before sending
  - [ ] 5.7 Show success message after

- [ ] 6.0 Implement BroadcastViewModel
  - [ ] 6.1 Create BroadcastViewModel.swift
  - [ ] 6.2 Implement validateAndSend()
  - [ ] 6.3 🧪 Write BroadcastViewModelTests.testSend_EmptyTitle_ReturnsError

- [ ] 7.0 Add admin access from profile
  - [ ] 7.1 In MyProfileView, check if user.isAdmin
  - [ ] 7.2 If admin, show "Admin Panel" button
  - [ ] 7.3 Navigate to AdminPanelView

- [ ] 8.0 Verify admin panel implementation
  - [ ] 8.1 Test non-admin cannot access
  - [ ] 8.2 Test pending user approval
  - [ ] 8.3 Test broadcast sending
  - [ ] 8.4 Commit: "feat: implement admin panel"

### 🔒 CHECKPOINT: QA-ADMIN-FINAL
> Run: `./QA/Scripts/checkpoint.sh admin-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_ADMIN_001, FLOW_ADMIN_002
> All admin tests must pass
