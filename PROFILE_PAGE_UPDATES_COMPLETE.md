# Profile Page Updates - Complete Implementation

## ✅ All Changes Implemented

### 1. Sign-Out Button Location ✅
- **Location**: Directly under user's email in header section
- **Style**: Red text button, subheadline font
- **Functionality**: Shows confirmation alert, then signs out

### 2. Admin Panel Link Location ✅
- **Location**: Directly below stats section (rating/reviews/fulfilled)
- **Visibility**: Only shown for admin users
- **Navigation**: Uses NavigationLink to AdminPanelView

### 3. Invite Codes Section ✅
- **Removed**: All status messages (active/inactive code messages)
- **Button Text**: Changed from "Generate Invite Code" to "Invite a Neighbor"
- **Button Icon**: Changed from `plus.circle.fill` to `person.badge.plus`
- **Workflow**: Users must click button and go through InvitationWorkflowView to see/share code
- **Code Display**: Code only shown in InvitationWorkflowView after generation (not on profile page)

### 4. Reviews Section ✅
- **Default Display**: Shows last 5 reviews
- **Expand/Collapse**: "Show All" / "Show Less" button when >5 reviews
- **Button Location**: In header next to "Reviews" title
- **Animation**: Smooth expand/collapse animation

### 5. Delete Account Section ✅
- **Location**: Below reviews section
- **Button**: Red "Delete Account" button with trash icon
- **Two-Step Confirmation**:
  1. First alert: "This action cannot be undone. You will lose all information..."
  2. Second alert: "Are you absolutely sure? This will permanently delete..."
- **Loading State**: Shows progress indicator during deletion
- **After Deletion**: Signs out and redirects to login page

### 6. Database Function for Account Deletion ✅
- **File**: `database/046_create_delete_account_function.sql`
- **Function**: `delete_user_account(p_user_id UUID)`
- **Deletes**:
  - Push tokens
  - Notifications
  - Reviews (given and received)
  - Town hall posts
  - Invite codes
  - Messages
  - Conversation participants
  - Conversations
  - Rides (cascades to ride_participants)
  - Favors (cascades to favor_participants)
  - Request Q&A
  - Profile
- **Note**: Auth user deletion requires Admin API (not in function)

## 🔧 Fixes Applied

### 1. Sign-Out Redirect Issue ✅
- **Problem**: Sign-out not redirecting to login page
- **Solution**:
  - Added `.onChange(of: launchManager.state)` to ContentView
  - Added `.onReceive` for "userDidSignOut" notification
  - Explicitly calls `performCriticalLaunch()` in MyProfileView after sign out
  - AppLaunchManager immediately sets state to `.ready(.unauthenticated)` on notification
- **Files Modified**:
  - `NaarsCars/App/ContentView.swift`
  - `NaarsCars/App/AppLaunchManager.swift`
  - `NaarsCars/Features/Profile/Views/MyProfileView.swift`

### 2. Admin Panel Auto-Dismiss Issue ✅
- **Problem**: Admin panel auto-dismissing if nothing clicked immediately
- **Solution**:
  - Removed nested NavigationStack from AdminPanelView (already inside NavigationStack from MainTabView)
  - Added `hasVerified` flag to AdminPanelViewModel to prevent re-verification
  - Removed auto-dismiss after 2 seconds
  - Added "Back to Profile" button for non-admin users
  - `.task` only verifies once (guarded by `hasVerified` flag)
- **Files Modified**:
  - `NaarsCars/Features/Admin/Views/AdminPanelView.swift`
  - `NaarsCars/Features/Admin/ViewModels/AdminPanelViewModel.swift`

## 📋 Files Modified

### Views
1. `NaarsCars/Features/Profile/Views/MyProfileView.swift`
   - Header section: Added sign-out button under email
   - Invite codes section: Removed status messages, changed button text to "Invite a Neighbor"
   - Reviews section: Added expand/collapse (last 5 default)
   - Added delete account section below reviews
   - Reordered sections (admin panel below stats)

2. `NaarsCars/Features/Profile/Views/InvitationWorkflowView.swift`
   - Updated to show generated code with copy/share after generation
   - No longer dismisses immediately after code generation
   - Shows success screen with code display

3. `NaarsCars/Features/Admin/Views/AdminPanelView.swift`
   - Removed nested NavigationStack
   - Removed auto-dismiss after 2 seconds
   - Added "Back to Profile" button for non-admin users

### ViewModels
1. `NaarsCars/Features/Admin/ViewModels/AdminPanelViewModel.swift`
   - Added `hasVerified` flag to prevent re-verification

### Services
1. `NaarsCars/Core/Services/ProfileService.swift`
   - Added `deleteAccount(userId:)` method
   - Uses database RPC function with Task.detached for MainActor isolation

### App
1. `NaarsCars/App/ContentView.swift`
   - Added `.onChange(of: launchManager.state)` to react to state changes
   - Added `.onReceive` for "userDidSignOut" notification

2. `NaarsCars/App/AppLaunchManager.swift`
   - Added logging to sign-out notification handler

### Database
1. `database/046_create_delete_account_function.sql` (NEW)
   - Creates `delete_user_account` function for cascade deletion

## 🚀 Next Steps

1. **Run Database Migration**: 
   - Execute `database/046_create_delete_account_function.sql` in Supabase Dashboard → SQL Editor

2. **Test Sign-Out**:
   - Verify sign-out button appears under email
   - Click sign-out and confirm it redirects to login page
   - Check that session is cleared

3. **Test Admin Panel**:
   - Navigate to admin panel from profile
   - Verify it doesn't auto-dismiss
   - Click on different sections and verify navigation works
   - Navigate back and verify panel persists

4. **Test Invite Codes**:
   - Click "Invite a Neighbor" button
   - Verify workflow appears
   - Complete workflow and verify code is shown with copy/share options

5. **Test Reviews**:
   - Verify only last 5 reviews show by default
   - Click "Show All" and verify all reviews appear
   - Click "Show Less" and verify it collapses to 5

6. **Test Delete Account**:
   - Click "Delete Account" button
   - Verify two-step confirmation appears
   - After deletion, verify redirect to login page
   - Verify account data is deleted from database

## ⚠️ Important Notes

### Account Deletion
- **Permanent**: Cannot be undone
- **Data Deleted**: All user data is permanently removed
- **Auth User**: The auth.users entry must be deleted separately via Admin API (requires service role key)
- **For Production**: Consider implementing:
  - Soft-delete option (deactivate instead of delete)
  - Grace period before permanent deletion (e.g., 30 days)
  - Account recovery option

### Sign-Out Flow
- **Redirect**: Should automatically redirect to login via ContentView state observation
- **Session Clearing**: Supabase auth.signOut() clears the session
- **State Management**: AppLaunchManager listens for sign-out notification and sets state immediately

### Admin Panel
- **Navigation**: Removed nested NavigationStack to prevent navigation issues
- **Verification**: Only verifies once using `hasVerified` flag
- **Persistence**: Panel should persist when navigating to sub-sections

## 🔍 Troubleshooting

### Sign-Out Not Redirecting
1. Check console for "🔄 [ContentView] Launch state changed" log
2. Check console for "userDidSignOut" notification being posted
3. Verify `launchManager.state` changes to `.ready(.unauthenticated)`
4. If still not working, check if LoginView needs NavigationStack (already has it)

### Admin Panel Auto-Dismissing
1. Verify `hasVerified` flag is preventing re-verification
2. Check console for "Non-admin accessed admin panel view" log
3. Verify navigation stack is correct (no nested NavigationStack)

### Account Deletion Failing
1. Verify database function exists: `delete_user_account`
2. Check RLS policies allow user to delete their own account
3. Verify function has SECURITY DEFINER
4. Check Edge Function logs if using Edge Function for auth user deletion

