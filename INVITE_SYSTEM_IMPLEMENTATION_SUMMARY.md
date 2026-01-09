# Invite System Implementation Summary

## Overview
This document summarizes the implementation of the enhanced invite system for Naar's Cars, based on `PRDs/prd-invite-system.md` and `Tasks/tasks-invite-system.md`.

## Completed Features

### 1. Database Schema Enhancements
**File**: `database/044_enhance_invite_codes.sql`

Added the following columns to `invite_codes` table:
- `invite_statement TEXT` - Statement provided by inviter about who they're inviting and why
- `is_bulk BOOLEAN NOT NULL DEFAULT FALSE` - Flag indicating if this is a bulk (multi-use) code
- `expires_at TIMESTAMPTZ` - Expiration timestamp for bulk codes (48 hours from creation)
- `bulk_code_id UUID REFERENCES invite_codes(id)` - Reference to parent bulk code for tracking

**Indexes Created**:
- `idx_invite_codes_created_by_is_bulk` - For efficient querying of user's codes
- `idx_invite_codes_expires_at` - For efficient expiration checks

### 2. InviteCode Model Updates
**File**: `NaarsCars/Core/Models/InviteCode.swift`

- Added new fields: `inviteStatement`, `isBulk`, `expiresAt`, `bulkCodeId`
- Added computed properties:
  - `isExpired` - Checks if code has passed its expiration date
  - `isActive` - Checks if code is both unused and not expired
- Updated `CodingKeys` to map to database column names

### 3. InviteService Refactoring
**File**: `NaarsCars/Core/Services/InviteService.swift`

**New Methods**:
- `fetchCurrentInviteCode(userId:)` - Fetches the single active (unused, not expired) invite code for a user, enriched with invitee name if used
- `generateInviteCode(userId:inviteStatement:)` - Generates a single-use invite code with an invitation statement. Includes uniqueness checks and client-side rate limiting (10 seconds between generations)
- `generateBulkInviteCode(userId:)` - Generates a multi-use invite code for admins, expiring in 48 hours. Includes admin verification and uniqueness checks
- `markCodeAsUsed(codeId:usedBy:usedAt:bulkCodeId:)` - Helper function to mark an invite code as used, handling both single and bulk codes
- `getInviteStats(userId:)` - Returns `InviteStats` (codes created, used, available)

**Rate Limiting**:
- Client-side: 10 seconds between code generations
- Server-side: 5 codes per day per user (enforced via database function)

### 4. AuthService Integration
**File**: `NaarsCars/Core/Services/AuthService.swift`

**Updated Methods**:
- `signUp` - Now uses `InviteService.shared.markCodeAsUsed` to mark the invite code as used, passing `validatedInviteCode.id`, `userId`, `Date()`, and `validatedInviteCode.bulkCodeId`
- `validateInviteCode` - Now checks `isExpired` for the `InviteCode` and throws `AppError.invalidInviteCode` if expired

### 5. Profile View Updates
**File**: `NaarsCars/Features/Profile/Views/MyProfileView.swift`

**Changes**:
- `inviteCodesSection`:
  - Displays `InviteStats` (Created, Used, Available)
  - "Generate" button now presents `InvitationWorkflowView` as a sheet
  - Only displays the `currentInviteCode` if available (not old codes)
- `InviteCodeRow`:
  - Now takes `InviteCodeWithInvitee` and displays `inviteeName` and `usedAt.dateString`
  - Copy and Share buttons are now explicit `Button`s instead of `swipeActions`
  - The share message now includes a deep link: `https://naarscars.com/signup?code=CODE`

**File**: `NaarsCars/Features/Profile/ViewModels/MyProfileViewModel.swift`

**Changes**:
- Uses `InviteService.shared` instead of `ProfileService.shared` for invite code operations
- `loadProfile`: Now fetches `inviteStats` and `inviteCodes` (only the current active one)
- `generateInviteCode`: Now calls `inviteService.generateInviteCode(userId: userId, inviteStatement: statement)` and updates `currentInviteCode` and `inviteStats`
- `generateBulkInviteCode`: New method for admins to generate bulk codes
- `currentInviteCode`: New published property to hold the single active invite code
- `showInvitationWorkflow`: New published property to control the presentation of `InvitationWorkflowView`

### 6. Invitation Workflow View
**File**: `NaarsCars/Features/Profile/Views/InvitationWorkflowView.swift`

**New Component**:
- Collects "Who are you inviting?" and "Why?" statements (up to 500 characters)
- Includes a "Generate Code" button that calls `MyProfileViewModel.generateInviteCode`
- Displays the generated code and provides copy/share options
- Includes a "Bulk Invite" option for admins, which presents `AdminBulkInviteView`

### 7. Admin Panel Enhancements
**File**: `NaarsCars/Features/Admin/Views/AdminPanelView.swift`

**Changes**:
- Added navigation link to `AdminInviteView` for generating invite codes

**File**: `NaarsCars/Features/Admin/Views/AdminInviteView.swift`

**New Component**:
- View for admins to generate regular or bulk invite codes
- Two options:
  1. **Regular Invite**: Opens `InvitationWorkflowView` (requires statement)
  2. **Bulk Invite**: Opens `BulkInviteSheet` (no statement required, expires in 48 hours)
- Displays generated code with copy/share functionality
- Share messages include deep links with embedded codes

**File**: `NaarsCars/Features/Admin/Views/PendingUserDetailView.swift`

**New Component**:
- Displays detailed information about a pending user:
  - User's name and email
  - Inviter's name (who invited them)
  - Invitation statement ("Who are you inviting and why?")
- Provides "Approve" and "Reject" buttons

**File**: `NaarsCars/Features/Admin/Views/PendingUsersView.swift`

**Changes**:
- `PendingUserRow` is now a `NavigationLink` to `PendingUserDetailView`
- Removed direct approve/reject actions from the row

**File**: `NaarsCars/Features/Admin/ViewModels/PendingUsersViewModel.swift`

**Changes**:
- Added `loadInviterProfiles` method to fetch inviter names
- Added `inviterProfiles` dictionary to store inviter profile data
- Updated `loadPendingUsers` to also load inviter profiles

### 8. Email Notification Service
**File**: `NaarsCars/Core/Services/EmailService.swift`

**New Service**:
- `sendWelcomeEmail(to:name:)` - Sends a welcome email to a newly approved user
- Currently logs the email (placeholder for actual email service integration)

**File**: `NaarsCars/Core/Services/AdminService.swift`

**Changes**:
- `approveUser`: Now sends a welcome email using `EmailService.shared.sendWelcomeEmail`
- `rejectUser`: Now deletes the user's profile and associated auth user

### 9. Deep Link Support
**File**: `NaarsCars/Features/Authentication/Views/SignupInviteCodeView.swift`

**Changes**:
- Added `onOpenURL` modifier to handle deep links: `https://naarscars.com/signup?code=CODE`
- Automatically extracts code from URL query parameters
- Pre-populates the invite code field and validates automatically

**File**: `NaarsCars/App/AppDelegate.swift`

**Changes**:
- Added `application(_:open:options:)` method to handle URL schemes
- Added `handleURL(_:)` private method to process deep links
- Posts notification for signup view to handle invite code deep links

### 10. Share Functionality
**File**: `NaarsCars/Features/Profile/Views/MyProfileView.swift`

**ShareSheet Component**:
- `ShareSheet` struct using `UIActivityViewController` for sharing invite codes
- Share messages include:
  - Deep link: `https://naarscars.com/signup?code=CODE`
  - App Store link (placeholder)
  - Code text for manual entry

## User Flows

### Regular Invite Flow
1. User navigates to Profile → Invite Codes section
2. Taps "Generate" button
3. `InvitationWorkflowView` appears asking "Who are you inviting and why?"
4. User enters statement (up to 500 characters)
5. Taps "Generate Invite Code"
6. Code is generated and displayed
7. User can copy or share the code
8. Share message includes deep link: `https://naarscars.com/signup?code=CODE`
9. New user receives SMS/text with link
10. New user taps link → App opens → Code is pre-populated → Signup proceeds

### Bulk Invite Flow (Admin Only)
1. Admin navigates to Admin Panel → Generate Invite Code
2. Taps "Bulk Invite" option
3. `BulkInviteSheet` appears
4. Admin taps "Generate Bulk Code"
5. Code is generated (expires in 48 hours, multi-use)
6. Admin can copy or share the code
7. Share message includes deep link and expiration notice
8. Multiple users can use the same code within 48 hours

### Signup Flow with Deep Link
1. New user receives SMS/text with deep link: `https://naarscars.com/signup?code=CODE`
2. User taps link
3. App opens (or is installed from App Store link)
4. `SignupInviteCodeView` appears with code pre-populated
5. Code is automatically validated
6. User proceeds to `SignupDetailsView`
7. After signup, user is shown `PendingApprovalView`
8. Admin reviews pending user in Admin Panel → Pending Approvals
9. Admin taps on user card → `PendingUserDetailView` shows:
   - User's name and email
   - Inviter's name
   - Invitation statement
10. Admin approves → Welcome email is sent → User can log in
11. Admin rejects → User's account is deleted

## Technical Details

### Rate Limiting
- **Client-side**: 10 seconds between code generations (prevents accidental spam)
- **Server-side**: 5 codes per day per user (enforced via database function)

### Code Expiration
- **Regular codes**: No expiration (single-use only)
- **Bulk codes**: 48 hours from creation

### Deep Link Format
```
https://naarscars.com/signup?code=CODE
```

### Share Message Format
```
Join me on Naar's Cars! 🚗

Sign up here: https://naarscars.com/signup?code=CODE

Or download the app and enter code: CODE
https://apps.apple.com/app/naars-cars
```

For bulk invites, additional text:
```
This code can be used by multiple people and expires in 48 hours.
```

## Database Functions

### Rate Limiting Function
```sql
CREATE OR REPLACE FUNCTION check_invite_code_rate_limit(user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  codes_today INTEGER;
BEGIN
  SELECT COUNT(*) INTO codes_today
  FROM invite_codes
  WHERE created_by = user_id
    AND DATE(created_at) = CURRENT_DATE;
  
  RETURN codes_today < 5;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Testing Checklist

- [ ] Generate regular invite code with statement
- [ ] Generate bulk invite code (admin only)
- [ ] Share invite code via SMS/text
- [ ] Open app via deep link with embedded code
- [ ] Code is pre-populated in signup view
- [ ] Signup flow completes successfully
- [ ] Pending user appears in admin approval queue
- [ ] Admin can view inviter name and statement
- [ ] Admin approves user → Welcome email sent
- [ ] Admin rejects user → Account deleted
- [ ] Bulk code expires after 48 hours
- [ ] Multiple users can use same bulk code within 48 hours
- [ ] Old codes are not displayed in profile view (only current active code)
- [ ] Rate limiting prevents excessive code generation

## Future Enhancements

1. **SMS Integration**: Automatically send SMS with invite code (requires Twilio or similar service)
2. **Email Service**: Integrate actual email service (SendGrid, AWS SES, etc.) for welcome emails
3. **Analytics**: Track invite code usage, conversion rates, etc.
4. **Custom Deep Links**: Support custom URL schemes (e.g., `naarscars://signup?code=CODE`)
5. **Invite Code History**: Show history of all generated codes (not just current active one)

## Files Modified/Created

### Database
- `database/044_enhance_invite_codes.sql`

### Models
- `NaarsCars/Core/Models/InviteCode.swift`

### Services
- `NaarsCars/Core/Services/InviteService.swift`
- `NaarsCars/Core/Services/AuthService.swift`
- `NaarsCars/Core/Services/AdminService.swift`
- `NaarsCars/Core/Services/EmailService.swift` (new)

### Views
- `NaarsCars/Features/Profile/Views/MyProfileView.swift`
- `NaarsCars/Features/Profile/Views/InvitationWorkflowView.swift` (new)
- `NaarsCars/Features/Admin/Views/AdminPanelView.swift`
- `NaarsCars/Features/Admin/Views/AdminInviteView.swift` (new)
- `NaarsCars/Features/Admin/Views/PendingUserDetailView.swift` (new)
- `NaarsCars/Features/Admin/Views/PendingUsersView.swift`
- `NaarsCars/Features/Authentication/Views/SignupInviteCodeView.swift`

### ViewModels
- `NaarsCars/Features/Profile/ViewModels/MyProfileViewModel.swift`
- `NaarsCars/Features/Admin/ViewModels/PendingUsersViewModel.swift`

### App
- `NaarsCars/App/AppDelegate.swift`

## Notes

- Deep link handling requires URL scheme configuration in `Info.plist` (not yet implemented)
- Email service is currently a placeholder (logs only)
- SMS sending is not yet implemented (requires third-party service)
- App Store link is a placeholder and should be updated when app is published

