## Naar's Cars — Business + Usability Guide (Full User Manual)

### 1) Product Overview
Naar’s Cars is an invite-only community platform that enables neighbors to request rides and favors, coordinate via messaging, and participate in a local Town Hall. It prioritizes community trust, approvals, and admin moderation.

**Primary user groups**
- Pending users: signed up, awaiting approval.
- Approved members: can post requests, message others, and participate in community.
- Admins: approve users, broadcast announcements, manage user access.

---

### 2) Global Navigation & UI Principles
**Main tabs**
- Requests
- Messages
- Community (Town Hall)
- Profile

**Common UI behaviors**
- Bell button (top right in Requests) opens in-app notifications.
- Tab badges show unseen activity.
- Pull-to-refresh in key lists.
- Context menus for address copy/open in Maps.

---

### 3) Onboarding & Authentication
**Signup (invite-only)**
- Choose signup method.
- Enter invite code.
- Complete profile details (name, email, password).
- Submit for approval.

**Pending approval**
- User sees Pending Approval screen.
- Access granted after admin approval.

**Login**
- Email + password.
- Session persists.
- Optional biometric unlock (Face ID/Touch ID).

**Password reset**
- Request reset link by email.

**Error recovery**
- Invalid invite code -> re-enter.
- Not approved -> remain in pending state.

---

### 4) Requests (Rides & Favors)
**Requests Dashboard**
- Filters: Open Requests, My Requests, Claimed by Me.
- Empty states are contextual.
- Create new ride/favor via plus menu.

**Ride flow**
- Create ride: date, time, pickup, destination, seats, notes, gift.
- Ride card: poster, status, time, pickup/destination, seats.
- Ride detail: Q&A, participants, claim/unclaim, complete, review prompts.
- Maps: open pickup/destination in Maps via long-press or detail actions.

**Favor flow**
- Create favor: title, description, location, duration, date/time, requirements, gift.
- Favor card: poster, status, location, duration, time.
- Favor detail: Q&A, participants, claim/unclaim, complete, review prompts.

**Claiming and completion**
- Claim sheet confirms action and requires phone if missing.
- Completion flow triggers review prompt.

---

### 5) Messaging
**Conversations list**
- Shows DMs and group chats.
- Unread counts shown per conversation.

**Conversation detail**
- Text, photo, audio, and location messages.
- Replies and reactions.
- Typing indicators.

**Group management**
- Add participants.
- Update group image.
- Leave conversation.

**Media handling**
- Photos and audio are compressed before upload.

---

### 6) Notifications & Badges
**Bell (in-app notifications)**
- Non-message notifications are grouped.
- “Mark all read” clears bell notifications.

**Message badges**
- Derived from unread messages per conversation.

**Deep links**
- Notifications navigate to ride/favor detail, conversation, or Town Hall post.

---

### 7) Community (Town Hall)
**Town Hall feed**
- Posts with author, timestamp, reactions.
- Tap to open comments.

**Create post**
- Title + body.

**Comments and reactions**
- Add comments and react to posts.

---

### 8) Profile & Settings
**My Profile**
- Shows avatar, name, email, car, phone (if saved), stats, reviews.

**Edit Profile**
- Update name, phone, car, and avatar.
- Phone disclosure shown the first time a phone number is added.

**Settings**
- Notification preferences.
- Community guidelines acceptance.
- Language settings (if enabled).
- Account deletion.

**Permissions**
- Photo access required for avatar changes.
- Location permission required for map/location features.

---

### 9) Admin Tools
**Admin Panel**
- Pending approvals queue.
- Approve/reject users.
- Broadcast announcements.
- User management tools.

---

### 10) Error Handling & Recovery
- Network errors show retry options.
- Permission errors are surfaced in context.
- Media upload errors show failure and allow retry.
- Badge refresh on foreground/refresh.

---

### 11) Data Visibility & Privacy
- Phone numbers are visible to community members for coordination (explicit disclosure).
- Profiles are visible to approved users.
- Admins can view pending users.
- Location data is stored with requests for mapping.

---

### 12) Loading/Empty States
- Requests: skeleton loading and contextual empty states.
- Messaging: placeholder until conversations load.
- Town Hall: empty state encourages first post.
- Notifications: empty bell state when no notifications.


