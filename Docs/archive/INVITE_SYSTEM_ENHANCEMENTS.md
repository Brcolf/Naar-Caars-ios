# Invite System Enhancements - Implementation Guide

## Overview
This document outlines the enhancements needed for the invite system based on user requirements.

## Database Changes Required

Run migration: `database/044_enhance_invite_codes.sql`

This adds:
- `invite_statement` (TEXT) - Statement explaining who they're inviting and why
- `is_bulk` (BOOLEAN) - Whether it's a bulk invite code
- `expires_at` (TIMESTAMPTZ) - Expiration for bulk codes (48 hours)
- `bulk_code_id` (UUID) - Links individual signups to bulk code

## Key Changes Summary

### 1. One Code at a Time
- Users can only have one active invite code
- Profile shows only current active code (not history)
- New code replaces old active code

### 2. Invitation Workflow
- Popup asks "Who are you inviting and why?"
- Statement stored in `invite_statement` field
- Required before generating code

### 3. Code in Deep Link
- Share message includes deep link with embedded code
- Format: `https://naarscars.com/signup?code=NC7X9K2ABQ`
- Code automatically populated in signup form

### 4. Admin Approval Enhancement
- Click into approval card to see:
  - Who invited the new user
  - The invitation statement
- Enhanced detail view

### 5. Admin Bulk Invites
- Admins can generate bulk codes (multiple uses)
- No questions prompt for bulk invites
- Can be sent to multiple people/group chats
- Bulk codes expire after 48 hours
- Individual signups from bulk codes still track which admin invited them

### 6. Email Notification
- Send welcome email when user is approved
- Email service needed (Supabase Edge Function or third-party)

### 7. Auto-Remove from Queue
- Approval card removed from queue after approval
- Already implemented in PendingUsersViewModel

## Implementation Status

✅ Database migration created
✅ InviteCode model updated with new fields
✅ InviteService updated for single code and bulk invites
✅ AuthService validateInviteCode updated for expiration checks
⏳ Signup process needs update for bulk code handling
⏳ Invitation workflow popup needs creation
⏳ Profile view needs update to show only current code
⏳ Admin approval view needs enhancement
⏳ Share message needs deep link
⏳ Email notification service needs creation

## Next Steps

1. Create InvitationWorkflowView (popup)
2. Update MyProfileView to show only current code
3. Update share message with deep link
4. Enhance PendingUsersView with detail view
5. Create email notification service
6. Update signup process for bulk codes


