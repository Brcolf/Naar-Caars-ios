# Xcode File Addition Guide - Invite System

## New Files to Add to Xcode

The following **4 new files** need to be added to your Xcode project:

### 1. EmailService.swift
**Location in Project**: `NaarsCars/Core/Services/EmailService.swift`
**File System Path**: `/Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs/NaarsCars/Core/Services/EmailService.swift`

**How to Add**:
1. In Xcode, navigate to `NaarsCars` → `Core` → `Services` folder
2. Right-click on `Services` folder → "Add Files to 'NaarsCars'..."
3. Navigate to `NaarsCars/Core/Services/EmailService.swift`
4. ✅ Check "Copy items if needed" (if not already in project directory)
5. ✅ Check "Create groups" (not folder references)
6. ✅ Ensure "NaarsCars" target is selected
7. Click "Add"

---

### 2. InvitationWorkflowView.swift
**Location in Project**: `NaarsCars/Features/Profile/Views/InvitationWorkflowView.swift`
**File System Path**: `/Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs/NaarsCars/Features/Profile/Views/InvitationWorkflowView.swift`

**How to Add**:
1. In Xcode, navigate to `NaarsCars` → `Features` → `Profile` → `Views` folder
2. Right-click on `Views` folder → "Add Files to 'NaarsCars'..."
3. Navigate to `NaarsCars/Features/Profile/Views/InvitationWorkflowView.swift`
4. ✅ Check "Copy items if needed" (if not already in project directory)
5. ✅ Check "Create groups" (not folder references)
6. ✅ Ensure "NaarsCars" target is selected
7. Click "Add"

---

### 3. AdminInviteView.swift
**Location in Project**: `NaarsCars/Features/Admin/Views/AdminInviteView.swift`
**File System Path**: `/Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs/NaarsCars/Features/Admin/Views/AdminInviteView.swift`

**How to Add**:
1. In Xcode, navigate to `NaarsCars` → `Features` → `Admin` → `Views` folder
2. Right-click on `Views` folder → "Add Files to 'NaarsCars'..."
3. Navigate to `NaarsCars/Features/Admin/Views/AdminInviteView.swift`
4. ✅ Check "Copy items if needed" (if not already in project directory)
5. ✅ Check "Create groups" (not folder references)
6. ✅ Ensure "NaarsCars" target is selected
7. Click "Add"

---

### 4. PendingUserDetailView.swift
**Location in Project**: `NaarsCars/Features/Admin/Views/PendingUserDetailView.swift`
**File System Path**: `/Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs/NaarsCars/Features/Admin/Views/PendingUserDetailView.swift`

**How to Add**:
1. In Xcode, navigate to `NaarsCars` → `Features` → `Admin` → `Views` folder
2. Right-click on `Views` folder → "Add Files to 'NaarsCars'..."
3. Navigate to `NaarsCars/Features/Admin/Views/PendingUserDetailView.swift`
4. ✅ Check "Copy items if needed" (if not already in project directory)
5. ✅ Check "Create groups" (not folder references)
6. ✅ Ensure "NaarsCars" target is selected
7. Click "Add"

---

## Alternative: Drag & Drop Method

You can also drag and drop files directly:

1. Open Finder and navigate to the file location
2. In Xcode, navigate to the target folder in the Project Navigator
3. Drag the file from Finder into the Xcode folder
4. In the dialog that appears:
   - ✅ Check "Copy items if needed"
   - ✅ Check "Create groups"
   - ✅ Ensure "NaarsCars" target is selected
5. Click "Finish"

---

## Files Already in Xcode (Modified, Not New)

These files were **modified** but already exist in Xcode, so no action needed:

- ✅ `NaarsCars/Core/Models/InviteCode.swift` (modified)
- ✅ `NaarsCars/Core/Services/InviteService.swift` (modified)
- ✅ `NaarsCars/Core/Services/AuthService.swift` (modified)
- ✅ `NaarsCars/Core/Services/AdminService.swift` (modified)
- ✅ `NaarsCars/Features/Profile/Views/MyProfileView.swift` (modified)
- ✅ `NaarsCars/Features/Profile/ViewModels/MyProfileViewModel.swift` (modified)
- ✅ `NaarsCars/Features/Admin/Views/AdminPanelView.swift` (modified)
- ✅ `NaarsCars/Features/Admin/Views/PendingUsersView.swift` (modified)
- ✅ `NaarsCars/Features/Admin/ViewModels/PendingUsersViewModel.swift` (modified)
- ✅ `NaarsCars/Features/Authentication/Views/SignupInviteCodeView.swift` (modified)
- ✅ `NaarsCars/App/AppDelegate.swift` (modified)

---

## Quick Verification Checklist

After adding files, verify:

1. ✅ All 4 new files appear in Project Navigator
2. ✅ Files are in correct folders (Services, Profile/Views, Admin/Views)
3. ✅ Build succeeds (⌘B) - no "file not found" errors
4. ✅ No red file icons in Project Navigator
5. ✅ Target membership shows "NaarsCars" checked for all new files

---

## Project Structure After Adding Files

```
NaarsCars/
├── Core/
│   ├── Services/
│   │   ├── EmailService.swift          ← NEW
│   │   ├── InviteService.swift         (modified)
│   │   ├── AuthService.swift           (modified)
│   │   └── AdminService.swift          (modified)
│   └── Models/
│       └── InviteCode.swift            (modified)
├── Features/
│   ├── Profile/
│   │   ├── Views/
│   │   │   ├── InvitationWorkflowView.swift  ← NEW
│   │   │   └── MyProfileView.swift           (modified)
│   │   └── ViewModels/
│   │       └── MyProfileViewModel.swift      (modified)
│   ├── Admin/
│   │   ├── Views/
│   │   │   ├── AdminInviteView.swift         ← NEW
│   │   │   ├── PendingUserDetailView.swift   ← NEW
│   │   │   ├── AdminPanelView.swift          (modified)
│   │   │   └── PendingUsersView.swift        (modified)
│   │   └── ViewModels/
│   │       └── PendingUsersViewModel.swift    (modified)
│   └── Authentication/
│       └── Views/
│           └── SignupInviteCodeView.swift    (modified)
└── App/
    └── AppDelegate.swift                      (modified)
```

---

## Troubleshooting

### File shows red in Project Navigator
- The file path is broken. Right-click → "Delete" (Remove Reference only), then re-add the file.

### Build errors about missing files
- Check target membership: Select file → File Inspector → Target Membership → ✅ NaarsCars

### Files appear in wrong folder
- Drag files to correct location in Project Navigator (Xcode will update references automatically)

---

## Database Migration

**Don't forget**: Run the database migration in Supabase:
- `database/044_enhance_invite_codes.sql`

This adds the new columns to the `invite_codes` table.


