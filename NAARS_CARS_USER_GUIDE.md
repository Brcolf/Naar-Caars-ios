# Naar's Cars - Complete Business & Usability Guide

**Version:** 1.0  
**Last Updated:** January 23, 2026  
**Platform:** iOS 17.0+

---

## Table of Contents

1. [What is Naar's Cars?](#1-what-is-naars-cars)
2. [Who is Naar's Cars For?](#2-who-is-naars-cars-for)
3. [Getting Started](#3-getting-started)
4. [Main Navigation](#4-main-navigation)
5. [Requests Tab - Complete Guide](#5-requests-tab---complete-guide)
6. [Messages Tab - Complete Guide](#6-messages-tab---complete-guide)
7. [Community Tab - Complete Guide](#7-community-tab---complete-guide)
8. [Profile Tab - Complete Guide](#8-profile-tab---complete-guide)
9. [Notifications System](#9-notifications-system)
10. [Admin Features](#10-admin-features)
11. [Error Handling & Recovery](#11-error-handling--recovery)
12. [Timing & Expectations](#12-timing--expectations)
13. [Data & Privacy](#13-data--privacy)
14. [Permissions Required](#14-permissions-required)
15. [Glossary](#15-glossary)

---

## 1. What is Naar's Cars?

Naar's Cars is an **invite-only community platform** designed for neighbors to help each other with rides and favors. Think of it as a private, trusted network where community members can:

- 🚗 **Request rides** to appointments, airports, or events
- 🤝 **Ask for favors** like picking up packages or helping with errands
- ✋ **Offer help** by claiming and fulfilling requests
- 🏘️ **Build community** through Town Hall discussions and recognition

### Core Philosophy

Naar's Cars operates on the principle of **neighbor helping neighbor**. Unlike commercial ride-sharing services:

- **No money changes hands** (though gift offerings are welcome)
- **Trust is earned** through invite-only membership
- **Community comes first** - every member is vetted and approved
- **Help is mutual** - givers today may be receivers tomorrow

### Technology Stack

- **Frontend:** Native iOS app built with SwiftUI
- **Backend:** Supabase (PostgreSQL database with real-time capabilities)
- **Authentication:** Email/password, Apple Sign-In, Biometric (Face ID/Touch ID)

---

## 2. Who is Naar's Cars For?

### Primary Users

| User Type | Description |
|-----------|-------------|
| **Neighbors** | Residents in a defined community (Seattle area focus) |
| **Transportation Seekers** | People without reliable transportation who need occasional rides |
| **Community Helpers** | Members willing to assist others with rides and errands |
| **Seniors** | Older adults who benefit from neighbor assistance |
| **Mobility-Challenged** | Those with transportation limitations |

### User Roles

#### 1. Regular Member
- Create ride and favor requests
- Claim and fulfill requests from others
- Participate in messaging
- Post and interact in Town Hall
- View leaderboards
- Invite new members

#### 2. Admin
- All regular member capabilities
- Approve or reject new member applications
- Send broadcast announcements
- Access admin panel for user management

---

## 3. Getting Started

### Step 1: Obtaining an Invite Code

Naar's Cars is **invite-only** to maintain community trust and safety.

**How to get an invite code:**
- Request from an existing community member
- Contact a community admin
- Attend a community event where bulk codes are distributed

**Invite Code Format:**
- 8 alphanumeric characters (e.g., `NAAR1234`)
- Case-insensitive
- Single-use (one code per person) unless it's a bulk event code

### Step 2: Creating Your Account

1. **Download the App**
   - TestFlight (beta testing)
   - App Store (when publicly released)

2. **Tap "Sign Up"**

3. **Enter Your Invite Code**
   - Code is validated in real-time
   - Invalid/used codes show an error message

4. **Provide Account Information**
   | Field | Required | Notes |
   |-------|----------|-------|
   | Email | ✅ Yes | Used for login and notifications |
   | Password | ✅ Yes | Minimum 8 characters |
   | Name | ✅ Yes | Your display name in the community |
   | Car Description | ❌ No | Add later if you'll offer rides |

5. **Wait for Approval**
   - Your application goes to admin queue
   - Typical approval time: 24-48 hours
   - You'll receive a push notification when approved

### Step 3: First Login

After approval:

1. **Sign In** with email/password or Apple Sign-In

2. **Accept Community Guidelines**
   - One-time acknowledgment required
   - Covers expected behavior and community standards
   - Cannot proceed without acceptance

3. **Enable Push Notifications** (Recommended)
   - Prompted after first login
   - Can be enabled later in Settings

4. **Set Up Biometric Login** (Optional)
   - Face ID or Touch ID
   - Configure in Profile → Settings

### Account States

| State | What You See | What You Can Do |
|-------|--------------|-----------------|
| **Pending Approval** | Waiting screen with status | Nothing - wait for admin review |
| **Approved** | Full app interface | Complete access to all features |
| **Rejected** | Error message | Contact admin or re-apply with new invite |

---

## 4. Main Navigation

The app uses a **4-tab navigation** structure at the bottom of the screen:

```
┌──────────────────────────────────────────────────┐
│                                                  │
│              [Current Screen Content]            │
│                                                  │
├──────────────────────────────────────────────────┤
│  🚗 Requests  │  💬 Messages  │  👥 Community  │  👤 Profile  │
└──────────────────────────────────────────────────┘
```

### Tab Overview

| Tab | Icon | Badge Shows | Purpose |
|-----|------|-------------|---------|
| **Requests** | 🚗 | Unread request activity | Browse, create, manage rides & favors |
| **Messages** | 💬 | Unread messages | Direct and group conversations |
| **Community** | 👥 | Unread Town Hall activity | Forum discussions, leaderboards |
| **Profile** | 👤 | Pending approvals (admin) | Your profile, settings, invite codes |

### Navigation Elements

- **Bell Icon** 🔔 - Access notifications (top-right on most screens)
- **Plus Button** ➕ - Create new content (context-dependent)
- **Back Arrow** ← - Return to previous screen
- **Pull Down** - Refresh current content

---

## 5. Requests Tab - Complete Guide

### 5.1 Requests Dashboard

The Requests Dashboard is your central hub for all ride and favor activity.

#### Filter Tiles

Three filter options appear at the top:

| Filter | Shows | Use When |
|--------|-------|----------|
| **Open Requests** | All available requests | Looking to help someone |
| **My Requests** | Requests you've posted | Managing your own needs |
| **Claimed by Me** | Requests you've committed to | Tracking your commitments |

#### Request Card Anatomy

Each request card displays:

```
┌─────────────────────────────────────────┐
│ 🚗 Ride                    ● OPEN       │
│─────────────────────────────────────────│
│ 123 Main St → SeaTac Airport            │
│ Jan 25, 2026 • 8:00 AM                  │
│─────────────────────────────────────────│
│ 👤 John Doe                    🔵       │
└─────────────────────────────────────────┘
```

- **Type Badge** - 🚗 Ride or 🤝 Favor
- **Status Badge** - Open, Claimed, Confirmed, Completed
- **Route/Title** - Pickup → Destination (rides) or Task title (favors)
- **Date/Time** - When the request is needed
- **Poster Avatar** - Who needs help
- **Blue Dot** 🔵 - Unread activity indicator

### 5.2 Creating a Ride Request

**Access:** Requests Tab → + Button → "Create Ride"

#### Required Fields

| Field | Input Type | Description |
|-------|------------|-------------|
| **Pickup** | Address autocomplete | Where to be picked up |
| **Destination** | Address autocomplete | Where to go |
| **Date** | Date picker | When the ride is needed |
| **Time** | Time picker | Specific time needed |
| **Seats** | Number stepper (1-6) | How many people need rides |

#### Optional Fields

| Field | Input Type | Description |
|-------|------------|-------------|
| **Notes** | Text field | Special instructions (wheelchair, luggage, etc.) |
| **Gift/Compensation** | Text field | What you're offering in thanks |

#### Address Autocomplete

As you type an address:
- Suggestions appear from Apple Maps
- Recent locations shown at top
- Tap suggestion to select
- Full address auto-fills

#### After Creating

- Ride appears in "Open Requests"
- Notification sent to community members
- You can edit or delete until someone claims it

### 5.3 Creating a Favor Request

**Access:** Requests Tab → + Button → "Create Favor"

#### Required Fields

| Field | Input Type | Description |
|-------|------------|-------------|
| **Title** | Text field | Brief description of the favor |
| **Location** | Address autocomplete | Where the favor is needed |
| **Date** | Date picker | When it's needed |
| **Description** | Text area | Full details of the request |

#### Optional Fields

| Field | Input Type | Description |
|-------|------------|-------------|
| **Gift/Compensation** | Text field | What you're offering in thanks |

### 5.4 Ride Detail View

Tap any ride card to see full details.

#### Sections

1. **Header Section**
   - Status badge (color-coded)
   - Poster information with avatar
   - "Requested by [Name]" subtitle

2. **Route Card**
   - Visual pickup → destination flow
   - Hold address to copy to clipboard
   - Estimated rideshare cost (if calculated)

3. **Map Section**
   - Interactive route preview
   - Tap to open in Apple Maps or Google Maps

4. **Time & Seats Info**
   - Date
   - Time
   - Number of seats requested

5. **Participants Section** (if any)
   - Additional people involved
   - Horizontal scrollable avatars

6. **Claimer Section** (if claimed)
   - Who claimed the ride
   - Their car description

7. **Notes & Gift**
   - Special instructions
   - Compensation offered

8. **Q&A Section**
   - Public questions about the request
   - Answers from the requester

9. **Action Buttons**
   - Varies based on your role and status

### 5.5 Favor Detail View

Similar structure to Ride Detail with:
- Single location instead of route
- Task description instead of map
- Same Q&A and action system

### 5.6 Claiming a Request

**Prerequisites:**
- Must have phone number in profile
- Push notifications encouraged (prompted if not enabled)

**Steps:**

1. Open request details
2. Tap **"Claim This Request"** button
3. Review confirmation sheet
4. Tap **"Confirm"**

**What Happens:**
- Status changes to "Claimed"
- Conversation auto-created with requester
- Notification sent to requester
- Request removed from "Open" filter

### 5.7 Request Status Flow

```
       ┌──────┐
       │ OPEN │
       └──┬───┘
          │ Claim
          ▼
     ┌─────────┐
     │ CLAIMED │
     └────┬────┘
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
┌─────────┐  ┌──────┐
│CONFIRMED│  │OPEN  │ (if unclaimed)
└────┬────┘  └──────┘
     │
     │ Mark Complete
     ▼
┌───────────┐
│ COMPLETED │
└───────────┘
```

### 5.8 Completing a Request

**Who Can Complete:** The request poster (not the claimer)

**Steps:**
1. Open your claimed request
2. Tap **"Mark Complete"**
3. Confirm completion
4. Review prompt appears

**After Completion:**
- Status changes to "Completed"
- Both parties prompted to leave reviews
- Request moves to "Past Requests"

---

## 6. Messages Tab - Complete Guide

### 6.1 Conversations List

**Layout:**
```
┌─────────────────────────────────────┐
│ 🔍 Search messages                   │
├─────────────────────────────────────┤
│ 📌 PINNED                           │
│ ┌─────────────────────────────────┐ │
│ │ 👥 Airport Run Group        (3) │ │
│ │ Thanks for the ride!         2m │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ ALL MESSAGES                        │
│ ┌─────────────────────────────────┐ │
│ │ 👤 John Doe                     │ │
│ │ On my way!                  15m │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

#### Conversation Row Elements

- **Avatar(s)** - Profile pictures of participants
- **Title** - Group name or participant names
- **Last Message Preview** - Truncated recent message
- **Time** - When last message was sent
- **Unread Badge** - Number of unread messages

#### Actions

| Action | Gesture | Result |
|--------|---------|--------|
| Open conversation | Tap | Navigate to chat |
| Pin/Unpin | Swipe right | Move to/from pinned section |
| Delete | Swipe left | Remove conversation |
| Search | Type in search bar | Filter by name/content |
| New message | Tap compose button | Start new conversation |

### 6.2 Starting a New Conversation

1. Tap the **compose button** (top right)
2. **Search for users** by name
3. **Select one or more participants**
4. Tap **"Create"** or start typing

**Note:** Direct messages (DMs) between two people are automatically reused if you've chatted before.

### 6.3 Conversation Detail (Chat View)

#### Message Types

| Type | Appearance | How to Send |
|------|------------|-------------|
| **Text** | Standard chat bubble | Type and send |
| **Photo** | Image preview in bubble | Tap 📷, select photo |
| **Audio** | Waveform with play button | Hold 🎤 to record |
| **Location** | Map preview | Tap 📍, share location |
| **System** | Centered gray text | Auto-generated (joins/leaves) |

#### Message Interactions

| Interaction | Gesture | Options |
|-------------|---------|---------|
| Reply | Swipe right on message | Opens reply context |
| React | Long press on message | 👍 👎 ❤️ 😂 ‼️ |
| Copy | Long press → Copy | Copies text to clipboard |
| View details | Long press → Details | See read receipts |

#### Reply Feature

When replying to a message:
```
┌─────────────────────────────────────┐
│ ↩️ Replying to John:                │
│ "What time should I arrive?"        │
├─────────────────────────────────────┤
│ [Your message here...]          📤 │
└─────────────────────────────────────┘
```

#### Typing Indicators

When someone is typing:
```
John is typing...
```

Multiple people:
```
John and Sarah are typing...
```

#### Read Receipts

- ✓ = Message sent
- ✓✓ = Message delivered
- ✓✓ (blue) = Message read

### 6.4 Group Conversations

#### Creating a Group

1. Start new conversation
2. Select multiple participants
3. Optionally set a group name
4. Create

#### Managing Groups

**Available Actions:**
- **Edit group name** - Tap group name at top
- **Add participants** - Tap + in group info
- **Leave group** - Tap "Leave Conversation" in settings
- **Remove someone** - Long press their name (if you have permission)

#### Group Photo

- Tap group avatar to change
- Select from photos or take new picture

### 6.5 In-App Message Toast

When you receive a message while using the app:

```
┌─────────────────────────────────────┐
│ 👤 John Doe                         │
│ "On my way to pick you up!"         │
└─────────────────────────────────────┘
```

- Appears at top of screen
- Tap to go directly to conversation
- Auto-dismisses after a few seconds

---

## 7. Community Tab - Complete Guide

### 7.1 Tab Structure

The Community tab has two sections accessible via a segmented control:

```
┌─────────────────────────────────────┐
│    [Town Hall]  |  [Leaderboard]    │
├─────────────────────────────────────┤
│                                     │
│         [Selected Section]          │
│                                     │
└─────────────────────────────────────┘
```

### 7.2 Town Hall

Town Hall is the community forum for discussions, announcements, and social interaction.

#### Post Types

| Type | Created By | Purpose |
|------|------------|---------|
| **Discussion** | Any member | General community topics |
| **Question** | Any member | Ask the community |
| **Announcement** | Admins only | Important notices (can be pinned) |
| **Review Link** | Auto-generated | Celebrates completed requests |

#### Creating a Post

1. Tap **+ New Post** button
2. Write your post content
3. Tap **Post**

#### Post Interactions

| Action | How | Effect |
|--------|-----|--------|
| React | Tap reaction buttons | 👍 ❤️ etc. |
| Comment | Tap comment icon | Add to discussion |
| Share | Tap share icon | Share within app |

#### Post Anatomy

```
┌─────────────────────────────────────┐
│ 👤 Jane Smith              📌 2h ago│
│─────────────────────────────────────│
│ Great community event yesterday!    │
│ Thanks to everyone who came out.    │
│─────────────────────────────────────│
│ 👍 12  ❤️ 5  💬 3 comments          │
└─────────────────────────────────────┘
```

### 7.3 Leaderboard

Leaderboard recognizes the most active community helpers.

#### Time Periods

| Period | Shows |
|--------|-------|
| **All Time** | Lifetime contributions |
| **This Year** | Current year only |
| **This Month** | Current month only |

#### Ranking Factors

- Number of rides fulfilled
- Number of favors completed
- Total contributions

#### Leaderboard Display

```
┌─────────────────────────────────────┐
│ 🏆 ALL TIME LEADERS                 │
├─────────────────────────────────────┤
│ 1. 🥇 John Doe        42 fulfilled  │
│ 2. 🥈 Jane Smith      38 fulfilled  │
│ 3. 🥉 Bob Johnson     35 fulfilled  │
│ 4.    Alice Brown     28 fulfilled  │
│ 5.    Charlie Lee     25 fulfilled  │
└─────────────────────────────────────┘
```

---

## 8. Profile Tab - Complete Guide

### 8.1 My Profile View

Your profile hub displays:

#### Header Section
- Your profile photo (tap to view larger)
- Your name
- Edit and Settings buttons

#### Stats Section

```
┌───────────┬───────────┬───────────┐
│   ⭐ 4.8  │  12 reviews │ 28 helped │
│  Rating   │  Received   │ Fulfilled │
└───────────┴───────────┴───────────┘
```

#### Admin Panel Link
*(Only visible to admin users)*

Blue button linking to admin features.

#### Notifications Section
Quick access to bell notifications.

#### Invite Codes Section
Generate and share invite codes.

#### Reviews Section
Reviews you've received from others.

#### Past Requests Section
Your completed rides and favors.

#### Delete Account Section
Account deletion option (bottom of page).

### 8.2 Edit Profile

**Access:** Profile Tab → Edit button

#### Editable Fields

| Field | Type | Notes |
|-------|------|-------|
| **Profile Photo** | Image picker | Tap "Change Photo" |
| **Name** | Text field | Your display name |
| **Phone Number** | Phone input | Format: (XXX) XXX-XXXX |
| **Car Description** | Text area | Make, model, color, etc. |

#### Phone Number Visibility Warning

When adding/changing phone number:
```
┌─────────────────────────────────────┐
│ ⚠️ Phone Number Visibility          │
│                                     │
│ Your phone number will be visible   │
│ to other Naar's Cars members to     │
│ coordinate rides and favors.        │
│                                     │
│ [Cancel]          [Yes, Save Number]│
└─────────────────────────────────────┘
```

### 8.3 Settings

**Access:** Profile Tab → ⚙️ (gear icon)

#### Available Settings

| Setting | Options | Description |
|---------|---------|-------------|
| **Push Notifications** | Per-type toggles | Control what alerts you receive |
| **Biometric Login** | On/Off | Enable Face ID/Touch ID |
| **App Version** | Display only | Current build information |
| **Sign Out** | Button | Log out of account |

#### Notification Preferences

| Notification Type | Default | Description |
|-------------------|---------|-------------|
| Ride Updates | On | Status changes for your rides |
| Messages | On | New message alerts |
| Announcements | On | Admin broadcasts |
| New Requests | Off | When new requests are posted |
| Q&A Activity | On | Questions on your requests |
| Review Reminders | On | Prompts to leave reviews |
| Town Hall | On | Comments on your posts |

### 8.4 Invite Codes

#### Generating Codes

1. Scroll to "Invite Codes" section
2. Tap **"Generate New Code"**
3. New 8-character code appears
4. Share via text, email, etc.

#### Code Types

| Type | Duration | Usage |
|------|----------|-------|
| **Standard** | Never expires | Single use |
| **Bulk** | 48 hours | Multiple uses (event codes) |

#### Code Statuses

| Status | Meaning |
|--------|---------|
| **Active** | Available for someone to use |
| **Used** | Already redeemed by someone |
| **Expired** | Bulk code past 48-hour window |

#### Viewing Who Used Your Code

Each used code shows:
- Name of person who used it
- When they used it
- Their approval status

### 8.5 Reviews

#### Received Reviews

Reviews others have left about you:
- Star rating (1-5)
- Written feedback
- Reviewer's name
- Date received

#### Leaving Reviews

After completing a request:
1. Review prompt appears automatically
2. Select star rating (1-5)
3. Optionally add written feedback
4. Submit or skip

### 8.6 Past Requests

View your completed request history:
- Filter by rides/favors
- See completion dates
- View who helped you / who you helped

### 8.7 Account Deletion

**Steps:**
1. Scroll to bottom of Profile
2. Tap **"Delete Account"**
3. Read warning about data deletion
4. Confirm deletion

**What Gets Deleted:**
- Your profile and personal data
- Your messages
- Your requests
- Your invite codes

**What Remains (Anonymized):**
- Reviews you left for others
- Your messages in group chats (attributed to "Deleted User")

---

## 9. Notifications System

### 9.1 Notification Bell

The bell icon (🔔) appears in the top-right corner of main screens.

**Badge Number:** Shows total unread notification count

**Tap Action:** Opens notifications list

### 9.2 Notifications List

#### Notification Groups

Notifications are grouped by source for easier scanning:

| Group Type | Example |
|------------|---------|
| **Request** | All activity for one ride/favor |
| **Town Hall** | All activity on one post |
| **Announcement** | Individual announcements |
| **Admin** | Approval-related items |

#### Notification Types

| Type | Icon | Trigger |
|------|------|---------|
| New Ride | 🚗 | Someone posted a ride |
| Ride Claimed | ✅ | Someone claimed your ride |
| Ride Completed | 🏁 | Ride marked complete |
| New Favor | 🤝 | Someone posted a favor |
| New Message | 💬 | Direct message received |
| Q&A Activity | ❓ | Question on your request |
| Review Request | ⭐ | Prompt to leave review |
| Town Hall | 📣 | Activity on your post |
| Announcement | 📢 | Admin broadcast |
| User Approved | ✅ | (Admin) New member ready |

### 9.3 Notification Actions

| Action | How | Result |
|--------|-----|--------|
| View details | Tap notification | Navigate to source |
| Mark as read | Tap or view | Removes from unread count |
| Mark all read | Tap button | Clears all unread |
| Refresh | Pull down | Fetch latest |

### 9.4 Push Notifications

When the app is closed or in background, push notifications appear on your device.

#### Enabling Push Notifications

1. iOS prompts on first claim attempt
2. Or go to iOS Settings → Naar's Cars → Notifications

#### Push Notification Content

```
┌─────────────────────────────────────┐
│ Naar's Cars                    now  │
│ John claimed your ride request!     │
│ Jan 25 • SeaTac Airport            │
└─────────────────────────────────────┘
```

Tap to open app directly to relevant screen.

---

## 10. Admin Features

*This section applies only to users with admin privileges.*

### 10.1 Admin Panel Access

**Location:** Profile Tab → "Admin Panel" button

### 10.2 Pending Users

View and manage new member applications.

#### User Application Card

```
┌─────────────────────────────────────┐
│ 👤 New Applicant Name               │
│ Email: applicant@email.com          │
│ Invited by: John Doe                │
│ Applied: Jan 20, 2026               │
├─────────────────────────────────────┤
│ [Reject]              [✅ Approve]  │
└─────────────────────────────────────┘
```

#### Approval Flow

1. Review applicant information
2. Consider who invited them
3. Tap **Approve** or **Reject**
4. User is notified of decision

### 10.3 User Management

View all community members:
- Search by name
- View profile details
- See activity statistics

### 10.4 Broadcast Announcements

Send messages to all community members.

#### Creating a Broadcast

1. Tap **"New Announcement"**
2. Write your message
3. Toggle **"Pin"** to keep at top of feeds
4. Tap **"Send to All"**

#### Broadcast Visibility

- Appears in all users' notifications
- Shows in Town Hall (if pinned)
- Push notification sent to everyone

---

## 11. Error Handling & Recovery

### 11.1 Common Errors

| Error Message | Meaning | How to Fix |
|---------------|---------|------------|
| "Network Error" | No internet | Check WiFi/cellular, retry |
| "Session Expired" | Login timed out | Sign in again |
| "Rate Limited" | Too many requests | Wait 30 seconds, retry |
| "Permission Denied" | Not authorized | Verify you're signed in |
| "Invalid Invite Code" | Code wrong/used/expired | Get new code |
| "Profile Update Failed" | Save error | Try again, contact support |

### 11.2 Troubleshooting Steps

#### App Won't Load
1. Force quit app (swipe up from app switcher)
2. Reopen app
3. If persists, delete and reinstall

#### Can't Sign In
1. Verify email and password
2. Try "Forgot Password" link
3. Check for typos
4. Contact admin if account locked

#### Notifications Not Working
1. Check iOS Settings → Notifications → Naar's Cars
2. Ensure notifications enabled in app settings
3. Sign out and back in
4. Reinstall app if needed

#### Messages Not Sending
1. Check internet connection
2. Wait and retry
3. Try sending from different screen
4. Check if conversation still exists

#### Photos Not Loading
1. Check internet connection
2. Pull to refresh
3. Clear app cache (reinstall if needed)

### 11.3 Reporting Issues

If you encounter persistent problems:
1. Note the exact error message
2. Note what you were doing when it occurred
3. Contact an admin through the app
4. Or email support (if available)

---

## 12. Timing & Expectations

### 12.1 Loading States

| Element | Loading Indicator |
|---------|-------------------|
| Lists | Skeleton placeholder cards |
| Details | "Loading..." message |
| Actions | Button becomes disabled |
| Images | Placeholder shimmer |

### 12.2 Refresh Behaviors

| Action | How | When to Use |
|--------|-----|-------------|
| Pull-to-refresh | Pull down on list | Force latest data |
| Auto-refresh | Happens automatically | On tab switch |
| Realtime updates | Instant | Messages, status changes |

### 12.3 Expected Timelines

| Action | Typical Duration |
|--------|------------------|
| Account approval | 24-48 hours |
| Message delivery | Instant |
| Push notification | 1-5 seconds |
| Image upload | 2-10 seconds |
| Profile save | 1-3 seconds |

### 12.4 Empty States

Each screen shows helpful guidance when empty:

| Screen | Empty Message | Action |
|--------|---------------|--------|
| Open Requests | "No requests available" | Create one |
| My Requests | "You haven't posted any requests" | Create one |
| Messages | "No conversations yet" | Start one |
| Notifications | "All caught up!" | None needed |

---

## 13. Data & Privacy

### 13.1 Data Visibility

#### Visible to All Community Members

| Data | Where Shown |
|------|-------------|
| Your name | Everywhere |
| Profile photo | Everywhere |
| Phone number | Profile, claim cards |
| Car description | Profile, claim cards |
| Reviews received | Your profile |
| Town Hall posts | Town Hall |
| Leaderboard rank | Leaderboard |

#### Private (Only You)

| Data | Notes |
|------|-------|
| Email address | Used for login only |
| Password | Encrypted, never displayed |
| Notification settings | Your preferences |
| Blocked users list | Private |

### 13.2 Data Collection

Naar's Cars collects:
- Account information (email, name, phone)
- Usage data (requests created, messages sent)
- Location data (only when sharing location in messages)
- Device tokens (for push notifications)

### 13.3 Data Retention

- Active account data: Retained while account active
- Deleted account: Data removed within 30 days
- Anonymized reviews: Kept indefinitely

### 13.4 Data Sharing

Your data is:
- ✅ Shared with community members (as described above)
- ✅ Processed by Supabase (backend provider)
- ❌ NOT sold to third parties
- ❌ NOT used for advertising

---

## 14. Permissions Required

### 14.1 iOS Permissions

| Permission | Why Needed | When Requested |
|------------|------------|----------------|
| **Notifications** | Push alerts | After first claim |
| **Photos** | Profile photo, message images | When selecting photo |
| **Camera** | Take new photos | When choosing camera |
| **Location** | Share location in messages | When sharing location |
| **Face ID/Touch ID** | Biometric login | When enabling in settings |

### 14.2 Managing Permissions

To change permissions:
1. Open iOS **Settings**
2. Scroll to **Naar's Cars**
3. Toggle permissions as desired

### 14.3 What Happens Without Permissions

| Permission Denied | Impact |
|-------------------|--------|
| Notifications | No push alerts (must check app manually) |
| Photos | Can't upload images |
| Camera | Can't take photos (can still select existing) |
| Location | Can't share location in messages |
| Biometric | Must use password to login |

---

## 15. Glossary

| Term | Definition |
|------|------------|
| **Claim** | Commit to fulfilling someone's request |
| **Unclaim** | Cancel your commitment to a request |
| **Fulfill** | Successfully complete a claimed request |
| **Poster** | Person who created a request |
| **Claimer** | Person who claimed a request |
| **DM** | Direct Message (1-on-1 conversation) |
| **Group** | Conversation with 3+ participants |
| **Town Hall** | Community discussion forum |
| **Broadcast** | Admin announcement to all users |
| **Bulk Code** | Event invite code usable by multiple people |
| **RLS** | Row-Level Security (database protection) |
| **Realtime** | Instant updates without refreshing |
| **Deep Link** | Direct link to specific app content |
| **Badge** | Notification count indicator |
| **Toast** | Temporary popup message |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Jan 23, 2026 | Initial comprehensive guide |

---

## Support

For additional help:
- Contact a community admin through the app
- Post in Town Hall for community assistance
- Check for in-app announcements about known issues

---

*This guide reflects the Naar's Cars iOS app as of January 2026. Features may change with future updates.*

