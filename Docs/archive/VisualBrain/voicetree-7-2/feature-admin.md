---
color: red
position:
  x: -307
  y: -1474
isContextNode: false
agent_name: Amy
---

# Feature: Admin

Admin-only features for user management and moderation.

## Views
- **AdminDashboardView.swift** - Main admin control panel
- **PendingApprovalsView.swift** - List of users awaiting approval
- **InviteCodeManagementView.swift** - Generate and manage invite codes
- **UserManagementView.swift** - Search and moderate users

## ViewModels
- **AdminViewModel.swift** - Admin operations (approve users, generate codes)

## Services
- **AdminService.swift** - Admin-only API calls with RLS checks

## Functionality

### User Approval
- View pending users with profile details
- Approve/reject new signups
- Updates `profiles.approved` field in database

### Invite Code Management
- Generate new invite codes
- View usage statistics
- Deactivate codes

### User Moderation
- Search users by name/email
- View user activity
- Block/unblock users (implied by architecture)

## Access Control

Admin features are gated by:
```swift
guard currentUser.isAdmin else {
    // Show error or hide UI
}
```

Database RLS policies enforce server-side checks.

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
