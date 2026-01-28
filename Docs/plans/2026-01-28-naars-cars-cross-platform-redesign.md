# Naar's Cars — Cross-Platform Redesign

**Date:** 2026-01-28
**Status:** Design Complete — Pending Implementation
**Scope:** Full application redesign for cross-platform (iOS + Android) with multi-community architecture

---

## Table of Contents

1. [Overview](#1-overview)
2. [Tech Stack](#2-tech-stack)
3. [Navigation & UX Structure](#3-navigation--ux-structure)
4. [Database Schema](#4-database-schema)
5. [Multi-Community Architecture](#5-multi-community-architecture)
6. [Requests (Rides & Favors)](#6-requests-rides--favors)
7. [Messaging](#7-messaging)
8. [Town Hall](#8-town-hall)
9. [Community Info & Admin](#9-community-info--admin)
10. [Profile & Notifications](#10-profile--notifications)
11. [Authentication](#11-authentication)
12. [Offline Strategy](#12-offline-strategy)
13. [Security & Performance](#13-security--performance)
14. [Project Structure](#14-project-structure)

---

## 1. Overview

Naar's Cars is a multi-community platform for neighbors and friends to exchange rides, favors, and conversation. The app starts as a utility for coordinating rides and favors, and evolves into a social platform for ongoing neighbor communication and community engagement.

### Core Concepts

- **Platform** — the Naar's Cars app itself. Handles authentication, user identity, and community discovery/membership.
- **Community** — a group of people (neighborhood, campus, friend group). All content lives within a community. Communities have configurable join rules (open, invite-only, invite + approval) and admin-defined settings.
- **Member** — a user's role within a community (owner, admin, moderator, member). A user can be a member of multiple communities with different roles in each.
- **Request** — a ride or favor posted within a community. Only visible to that community's members. Has a lifecycle: created → open → claimed → in progress → completed → reviewed.
- **Conversation** — messaging scoped to a community. Created between members for request coordination or direct chat.
- **Town Hall** — a discussion forum within each community for general conversation, posts, and voting.

### Design Principles

- **Performance-first** — the app should feel as fast and responsive as a social media app. Stale-while-revalidate caching, optimistic updates, and local persistence for messaging.
- **iMessage-quality messaging** — real-time delivery, instant history loading, reactions, threaded replies, image sharing, typing indicators. Messaging is a core differentiator.
- **Multi-community from day one** — every feature is scoped to a community. Users can belong to multiple communities.
- **Offline-capable where safe** — optimistic offline writes for non-conflicting actions, online-only for conflict-prone actions like claiming.
- **Apple-first deployment** — build cross-platform from the start, but deploy to iOS App Store first. Android follows.

---

## 2. Tech Stack

| Layer | Technology | Rationale |
|---|---|---|
| Framework | React Native + Expo (managed workflow) | Single codebase for iOS + Android. Expo handles builds, OTA updates, and platform APIs. |
| Language | TypeScript (strict mode) | Type safety across the entire codebase. |
| Navigation | Expo Router (file-based routing) | File-based routes map cleanly to the two-tier navigation model. |
| State management | Zustand | Lightweight global state (auth, active community, connectivity). No boilerplate. |
| Server state / caching | TanStack Query (React Query) | Stale-while-revalidate pattern for snappy social media feel. Background refresh, optimistic updates. |
| Local persistence | WatermelonDB | SQLite-based, lazy-loading. Purpose-built for React Native offline-first. Used for messaging to achieve iMessage-like instant load. |
| Backend client | Supabase JS SDK (@supabase/supabase-js) | First-class TypeScript support. Best-supported Supabase client library. |
| Real-time | Supabase Realtime | WebSocket-based subscriptions for instant message delivery and live updates. |
| Auth | Supabase Auth | Email/password + Apple Sign In at launch. Google Sign In added with Android deployment. |
| Push notifications | expo-notifications + Supabase Edge Functions | Expo Push API handles APNs/FCM from a single API. Edge Functions trigger on database events. |
| Maps | react-native-maps | Map rendering on request detail views. |
| UI styling | NativeWind (Tailwind for RN) | Utility-first styling. Fast to build, consistent design system. |
| Animations | react-native-reanimated | Smooth, native-thread animations for messaging UX and transitions. |
| Forms | React Hook Form + Zod | Type-safe validation. No re-renders on every keystroke. |
| Image handling | expo-image | Fast caching, progressive loading. |
| Image picker | expo-image-picker + expo-image-manipulator | Camera/library access with client-side compression before upload. |
| List rendering | FlashList (Shopify) | 5-10x faster than FlatList for long lists. |
| Haptics | expo-haptics | Tactile feedback on send, reactions, and key interactions. |
| Keyboard | react-native-keyboard-controller | Smooth keyboard avoidance for messaging. |
| Biometrics | expo-local-authentication | Face ID / Touch ID for app unlock. |
| Secure storage | expo-secure-store | Encrypted storage for auth tokens. |
| Analytics & crashes | @react-native-firebase (Analytics + Crashlytics) | Crash reporting and usage analytics. |
| Builds & deploys | EAS Build + EAS Submit | Managed build pipeline for iOS (and later Android). |

---

## 3. Navigation & UX Structure

### Two-Tier Navigation Model

**Tier 1 — Platform Level (Community List)**

The home screen of the app. Shows the user's communities and provides platform-level access.

- Community cards showing name, icon, member count, and unread indicators (messages, notifications)
- Quick actions: Create Community, Join Community
- Profile avatar in header → taps to Profile & App Settings
- Notification bell in header → platform-level notifications (invites, approvals, cross-community alerts)

**Tier 2 — Inside a Community**

Entered by tapping a community card. Self-contained world for that community.

- **Persistent back affordance** — community name/icon in the top-left acts as a back button to the community list. Always visible regardless of navigation depth. Similar to Slack's workspace icon.
- **Bottom tab bar** (4 tabs):
  1. **Requests** — feed of rides and favors with filters, FAB for creation
  2. **Messages** — conversation list with unread badges
  3. **Town Hall** — discussion feed with voting
  4. **Community** — members, leaderboard, community info, admin settings (role-gated)

**Why 4 tabs:**
- Notifications are platform-level (bell icon on community list) since they span communities
- Profile is platform-level (avatar on community list) since identity spans communities
- In-community tabs focus on actions within that community

### Navigation Flow Example

```
Community List
  → Tap "Oak Street Neighbors"
    → Requests tab (default)
      → Tap a ride card → Ride Detail
        → Tap "Ask Question" → Q&A thread
          → Back button chain: Q&A → Detail → Requests
    → Community name (top-left) → back to Community List at any time
```

### Cross-Community Activity Indicators

- Community cards on the home screen show badge dots for unread messages and new requests
- Platform notification bell catches cross-community alerts
- Push notifications deep-link directly into the right community → right screen

---

## 4. Database Schema

All tables live in Supabase (PostgreSQL) with Row-Level Security enforced on every table.

### Platform-Level Tables

```sql
-- User identity (platform-level, spans communities)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  phone TEXT,
  display_name TEXT NOT NULL,
  avatar_url TEXT,
  bio TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_active_at TIMESTAMPTZ DEFAULT now()
);

-- Community definition
CREATE TABLE communities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  icon_url TEXT,
  cover_image_url TEXT,
  join_rule TEXT NOT NULL CHECK (join_rule IN ('open', 'invite_only', 'invite_and_approval')),
  created_by UUID REFERENCES users(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- User membership in communities
CREATE TABLE community_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID REFERENCES communities(id) NOT NULL,
  user_id UUID REFERENCES users(id) NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'moderator', 'member')),
  status TEXT NOT NULL CHECK (status IN ('active', 'pending_approval', 'banned')),
  joined_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(community_id, user_id)
);

-- Invite links and codes
CREATE TABLE community_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID REFERENCES communities(id) NOT NULL,
  invited_by UUID REFERENCES users(id) NOT NULL,
  invite_code TEXT UNIQUE NOT NULL,
  max_uses INT,               -- NULL = unlimited
  uses_count INT DEFAULT 0,
  expires_at TIMESTAMPTZ,     -- NULL = never expires
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Track who redeemed which invite
CREATE TABLE invite_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_id UUID REFERENCES community_invites(id) NOT NULL,
  user_id UUID REFERENCES users(id) NOT NULL,
  redeemed_at TIMESTAMPTZ DEFAULT now()
);

-- Admin-controlled community settings
CREATE TABLE community_settings (
  community_id UUID REFERENCES communities(id) PRIMARY KEY,
  features_enabled JSONB DEFAULT '{"rides": true, "favors": true, "town_hall": true, "leaderboard": true}',
  require_approval_to_post BOOLEAN DEFAULT false,
  allow_anonymous_questions BOOLEAN DEFAULT false
);
```

### Requests Domain

```sql
-- Unified requests table (rides and favors)
CREATE TABLE requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID REFERENCES communities(id) NOT NULL,
  created_by UUID REFERENCES users(id) NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('ride', 'favor')),
  status TEXT NOT NULL CHECK (status IN ('open', 'claimed', 'in_progress', 'completed', 'cancelled')),
  title TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  -- Ride-specific fields (nullable, populated when type = 'ride')
  pickup_location GEOGRAPHY(POINT),
  pickup_address TEXT,
  destination_location GEOGRAPHY(POINT),
  destination_address TEXT,
  seats_available INT,
  scheduled_at TIMESTAMPTZ,

  -- Favor-specific fields (nullable, populated when type = 'favor')
  location GEOGRAPHY(POINT),
  location_address TEXT,
  estimated_duration INTERVAL
);

-- Additional participants on a request (multi-requestor support)
CREATE TABLE request_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID REFERENCES requests(id) NOT NULL,
  user_id UUID REFERENCES users(id) NOT NULL,
  added_by UUID REFERENCES users(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(request_id, user_id)
);

-- Claims on requests
CREATE TABLE request_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID REFERENCES requests(id) NOT NULL,
  claimed_by UUID REFERENCES users(id) NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'completed', 'cancelled')),
  claimed_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ
);

-- Q&A on requests
CREATE TABLE request_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id UUID REFERENCES requests(id) NOT NULL,
  asked_by UUID REFERENCES users(id) NOT NULL,
  question_text TEXT NOT NULL,
  answer_text TEXT,
  answered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### Messaging Domain

```sql
-- Conversations scoped to a community
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID REFERENCES communities(id) NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('direct', 'group')),
  name TEXT,                    -- Optional group name
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Conversation membership
CREATE TABLE conversation_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES conversations(id) NOT NULL,
  user_id UUID REFERENCES users(id) NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'member')) DEFAULT 'member',
  last_read_at TIMESTAMPTZ,
  joined_at TIMESTAMPTZ DEFAULT now(),
  left_at TIMESTAMPTZ,         -- Soft leave, preserves history
  UNIQUE(conversation_id, user_id)
);

-- Messages
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES conversations(id) NOT NULL,
  sender_id UUID REFERENCES users(id) NOT NULL,
  content TEXT,                 -- Nullable for image-only messages
  type TEXT NOT NULL CHECK (type IN ('text', 'image', 'system', 'link')),
  media_url TEXT,
  media_thumbnail_url TEXT,
  reply_to_id UUID REFERENCES messages(id),  -- Threaded reply to specific message
  created_at TIMESTAMPTZ DEFAULT now(),
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ        -- Soft delete
);

-- Message reactions
CREATE TABLE message_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES messages(id) NOT NULL,
  user_id UUID REFERENCES users(id) NOT NULL,
  emoji TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(message_id, user_id, emoji)
);
```

### Town Hall Domain

```sql
-- Forum posts
CREATE TABLE town_hall_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID REFERENCES communities(id) NOT NULL,
  author_id UUID REFERENCES users(id) NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  pinned BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Comments (one level of threading)
CREATE TABLE town_hall_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID REFERENCES town_hall_posts(id) NOT NULL,
  author_id UUID REFERENCES users(id) NOT NULL,
  body TEXT NOT NULL,
  parent_comment_id UUID REFERENCES town_hall_comments(id),  -- One level deep threading
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Votes on posts and comments
CREATE TABLE town_hall_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) NOT NULL,
  vote_type TEXT NOT NULL CHECK (vote_type IN ('up', 'down')),
  post_id UUID REFERENCES town_hall_posts(id),
  comment_id UUID REFERENCES town_hall_comments(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  CHECK (post_id IS NOT NULL OR comment_id IS NOT NULL),
  UNIQUE(user_id, post_id),
  UNIQUE(user_id, comment_id)
);
```

### Reviews

```sql
CREATE TABLE reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID REFERENCES communities(id) NOT NULL,
  request_id UUID REFERENCES requests(id) NOT NULL,
  reviewer_id UUID REFERENCES users(id) NOT NULL,
  reviewee_id UUID REFERENCES users(id) NOT NULL,
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

Leaderboard is a database view (or materialized view) computed from reviews and completed requests per community, not a separate table.

### Notifications

```sql
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) NOT NULL,
  community_id UUID REFERENCES communities(id),  -- NULL for platform-level
  type TEXT NOT NULL,    -- 'request_claimed', 'message_received', 'review_left', etc.
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB,            -- Deep link payload
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 5. Multi-Community Architecture

### Community Model

Each community is a self-contained world. All content (requests, messages, town hall posts, reviews) is scoped to a community via `community_id` foreign keys. Users can belong to multiple communities with different roles in each.

### Join Rules

| Rule | Behavior |
|---|---|
| `open` | Anyone can join freely. Invite links join immediately. |
| `invite_only` | Must have an invite link/code. Having the link is the invite — joins immediately. |
| `invite_and_approval` | Must have an invite link, then admin must approve the join request. |

### Invite Deep Linking

```
Invite link format: https://naarscars.com/invite/[invite_code]

Existing user (app installed):
  → Link opens app → app reads invite_code
  → If logged in → join community (or submit join request if approval required)
  → If logged out → auth flow → then join community

New user (app not installed):
  → Link opens App Store listing (via universal link fallback)
  → User installs app → opens app
  → App reads deferred deep link (expo-linking)
  → Signup flow → after account creation, auto-joins community (or submits request)
```

The `invite_code` carries through the entire flow — install, signup, and into the correct community.

### Community Settings

Admins control feature availability per community via `community_settings.features_enabled`:

```json
{
  "rides": true,
  "favors": true,
  "town_hall": true,
  "leaderboard": true
}
```

Disabled features hide their corresponding UI elements (tabs, buttons, sections).

### Role Hierarchy

```
Owner (1 per community — the creator)
  └── Admin (full settings + moderation)
       └── Moderator (content moderation only)
            └── Member (standard access)
```

- **Owner** can do everything, including transferring ownership to another member (atomic swap — previous owner becomes admin).
- **Admin** can manage settings, roles (up to moderator), features, join rules, and moderate content.
- **Moderator** can pin/unpin town hall posts, remove posts and comments, and mute members temporarily.
- **Member** has standard access to all enabled features.

---

## 6. Requests (Rides & Favors)

### Request Lifecycle

```
Created → Open → Claimed → In Progress → Completed → Reviewed
                    ↓
                 Cancelled (at any point before Completed)
```

### Request Feed (Requests Tab)

Three toggle filters:

1. **Open** — requests from other community members that are unclaimed and available. Excludes requests where you are the creator or a participant. Participants are treated as requestors — open requests they are part of do not appear in this filter.
2. **My Requests** — requests you created or were added to as a participant. Badge shows status (open/claimed).
3. **Claimed** — requests you've volunteered to fulfill. Shows your active commitments.

- Pull-to-refresh + TanStack Query background refresh
- Floating action button (FAB) to create a new request
- No map view on the feed — keeps it fast and simple
- Requests past their scheduled time automatically drop off the dashboard and archive to Past Requests in the user's profile

### Creating a Request

1. Choose type (ride or favor)
2. Fill details:
   - **Ride:** pickup address, destination address, date/time, seats available, notes
   - **Favor:** title, description, location (optional), estimated duration, notes
   - Address input uses location autocomplete
3. Add participants (optional) — search/select community members to include as co-requestors
4. Submit

Form validation via Zod schemas. Offline support: request saved locally with pending indicator, syncs when online.

### Multi-Participant Requests

- Creator can add community members as participants during creation or after
- All participants are requestors — they all need the ride/favor
- Participants cannot claim a request they are involved in (server-enforced)
- When claimed, all participants receive push notifications
- "Message Participants" group chat includes claimer + creator + all participants

### Request Detail Screen

- Header: type badge, status badge, creator avatar + name
- Additional participants listed below the creator
- Details section: all request info
- **Map (rides only):** pickup and destination pins with route line. Tapping the map opens device native maps (Apple Maps / Google Maps) with directions using current location as starting point, pickup as waypoint, and destination as the endpoint.
- **Q&A section:** community members ask questions, creator answers
- **Action button** (context-dependent):
  - Open request, not involved → "Claim This Request" (online-only, server validates)
  - Your request, open → "Edit" / "Cancel"
  - Claimed, you're a participant → "Message Participants" (creates/opens group chat, auto-sends system message with deep link back to request)
  - Completed → "Leave Review"

### Claim Flow

- Tap Claim → confirmation sheet → server validates (no double-claims, not creator, not participant)
- On success: status updates to Claimed, push notification to creator + all participants
- "Message Participants" button appears for everyone involved
- **Not optimistic** — requires server confirmation. Show loading state during round-trip.

### Archival

Requests past their `scheduled_at` time (rides) or a defined expiry (favors) automatically filter out of the dashboard. They remain in the database, accessible via Profile → Past Requests with full read-only detail (history, Q&A, review).

---

## 7. Messaging

Messaging is the most critical feature. It must feel identical to iMessage in speed, reliability, and UX.

### Real-Time Architecture

```
User A sends message
  → Written to WatermelonDB (instant local render)
  → Pushed to Supabase via messageService
  → Supabase Realtime broadcasts to channel
  → User B's app receives via Realtime subscription
  → Written to User B's WatermelonDB
  → WatermelonDB observable triggers re-render (instant)
```

Both users see messages appear instantly. No polling, no refresh. Supabase Realtime uses WebSockets — persistent connection, sub-second delivery.

### Offline Behavior

Message is written to WatermelonDB with `sync_status: pending`, rendered immediately with a subtle "sending..." indicator (like iMessage's progress bar), and pushed to Supabase when connectivity returns.

### Conversation Types

- **Direct** — 1-on-1 conversation between two community members
- **Group** — 3+ participants. Optional group name. Created manually or via "Message Participants" on a claimed request.

### Message Features

#### Sending Pictures
- Tap camera/photo icon → expo-image-picker (camera or library)
- Image compressed client-side (expo-image-manipulator) before upload
- Uploaded to Supabase Storage → URL stored in `media_url`
- Thumbnail generated for fast loading in conversation list
- Full image loads on tap (pinch-to-zoom viewer)
- Progress indicator during upload

#### Sending Links
- Link detection in message text via regex
- Link preview fetched server-side (Edge Function) extracting Open Graph metadata (title, description, image)
- Preview rendered as a card below the message bubble
- Tap preview → opens browser

#### Message Reactions
- Long-press a message → reaction picker (like iMessage's tapback menu)
- Quick reactions: heart, thumbs up, thumbs down, laugh, exclamation, question mark
- Reactions render as small badges on the message bubble corner
- Multiple users can react to the same message
- Real-time — reactions appear instantly via Realtime subscription

#### Threaded Replies
- Swipe right on a message → reply mode
- Reply shows a preview of the original message above the input bar
- In conversation, replies display with a small quoted preview of the parent message above the reply bubble
- Inline in the main conversation (not a separate thread view)

#### Group Chat Management
- **Add members** — any participant can add community members
- **Remove members** — only group admin (creator) can remove others
- **Leave group** — any member can leave. Generates system message: "Alex left the conversation"
- **System messages** for all membership changes
- Members who leave retain message history up to their `left_at` timestamp but stop receiving new messages

#### Sender Names in Group Chats
- In group conversations, the sender's display name appears above the first bubble in a consecutive group from that sender
- Not repeated on every bubble in a cluster — only the first
- In direct conversations, no sender names shown
- Your own messages never show your name (they're on the right side)

#### Read Receipts
- `last_read_at` on `conversation_participants` updates when a user views the conversation
- Shows "Read" or delivery status on the last message

#### Typing Indicators
- Ephemeral, not stored in database
- Broadcast via Supabase Realtime presence channel
- "Alex is typing..." appears and disappears in real-time

### Conversation List
- Sorted by most recent message
- Shows: participant avatar(s), conversation name, last message preview, timestamp, unread badge
- Unread count = messages where `created_at > last_read_at` for that user
- Swipe actions: mute, delete (soft — hides from list)

### iMessage Look and Feel
- **Bubble colors** — sender (blue/branded) on right, receiver (gray) on left
- **Bubble grouping** — consecutive messages from same sender cluster together (tail on last bubble only)
- **Timestamps** — shown between message groups when time gap exceeds ~15 minutes, not on every message
- **Smooth animations** — new messages slide up, reactions animate in, keyboard avoidance is smooth
- **Haptic feedback** — on send, on long-press for reactions

### "Message Participants" Flow (from Claimed Request)

```
Claimed Request → tap "Message Participants"
  → App checks if group conversation already exists with these users in this community
    → Yes: open it
    → No: create group conversation, add all participants + claimer,
           auto-send system message with deep link to request:
           "[Request: Ride to Airport, Jan 30] — tap to view request"
  → User is now in a normal group chat
```

---

## 8. Town Hall

Community discussion forum for general conversation, announcements, and engagement.

### Town Hall Feed
- Chronological feed, newest first
- Pinned posts stick to the top (admin/moderator can pin)
- Each post card: author avatar + name, title, body preview (2-3 lines), vote count, comment count, timestamp
- Pull-to-refresh + background refresh
- FAB to create a new post

### Creating a Post
- Title (required)
- Body (required, supports longer text)
- No categories or tags — one flat feed per community
- Offline support: post saves locally with pending indicator, syncs when online

### Post Detail
- Full post content
- Vote controls (upvote/downvote) with net count
- One vote per user per post — tap again to remove, tap opposite to switch
- Comment thread below the post

### Comments
- Flat list with one level of threading via `parent_comment_id`
- Reply to post → top-level comment
- Reply to comment → nested reply, indented under parent
- No deeper nesting than one level
- Votes on comments (upvote/downvote, same rules as posts)
- Comments sort by vote count (highest first) to surface best replies

---

## 9. Community Info & Admin

The fourth tab inside a community.

### Community Info (All Members)

- **Community header:** name, icon, cover image, description, member count, join rule badge
- **Members list:** searchable, showing avatar, display name, role badge, star rating
- Tap a member → public profile within community context
- **Leaderboard** (if enabled): ranked by completed requests and average rating. Toggle between "all time" and "this month".
- **Invite:** generate invite link/code. Behavior follows community join rules.

### Admin Settings (Owner/Admin Only)

- **General:** edit community name, description, icon, cover image
- **Join rules:** toggle between open, invite-only, invite + approval
- **Features:** toggle rides, favors, town hall, leaderboard on/off
- **Roles:** promote/demote members. Only owner can promote to admin.
- **Moderation:** remove members, ban members (prevents rejoin), review flagged content
- **Pending approvals** (if join rule = invite + approval): approve/deny join requests
- **Transfer ownership:** owner can transfer to another member. Atomic swap — previous owner becomes admin. Confirmation dialog with warning. Server-enforced, only current owner can execute.

### Moderator Capabilities (Subset of Admin)

- Pin/unpin town hall posts
- Remove posts and comments
- Mute members temporarily
- Cannot change community settings, roles, or remove members

---

## 10. Profile & Notifications

Both live at the platform level, outside any community.

### Profile

**My Profile (top-right avatar on community list):**
- Avatar, display name, bio, email, phone
- Edit profile screen
- Avatar upload via image picker → compressed → Supabase Storage
- **My Communities:** list of communities with role in each
- **Past Requests:** archived requests across all communities, grouped by community. Read-only detail with full history.
- **My Reviews:** reviews received across all communities. Aggregate star rating.
- **App Settings:** notification preferences, biometric lock toggle, sign out, delete account

**Public Profile (tap any member in a community):**
- Avatar, display name, bio
- Star rating (from reviews in that community)
- Reviews received in that community
- Member since date
- "Message" button → opens/creates direct conversation in that community

### Notifications

Platform-level notification center — aggregates across all communities.

- **Notification list:** sorted by newest, grouped by today / earlier
- Each shows: community icon, title, body, timestamp, read/unread state
- Tap → deep links into the relevant screen within the correct community
- Mark all as read action
- Swipe to dismiss

**Notification Types:**

| Event | Recipient | Deep Link Target |
|---|---|---|
| Request claimed | Creator + participants | Request detail |
| New question on request | Creator | Request detail (Q&A) |
| Question answered | Asker | Request detail (Q&A) |
| New message | Conversation participants | Conversation |
| Request completed | All participants | Request detail |
| Review received | Reviewee | My Reviews |
| Invite accepted / member joined | Community admins | Community members |
| Join request pending | Community admins | Pending approvals |
| Town hall reply to post | Post author | Post detail |
| Town hall reply to comment | Comment author | Post detail |
| Added as participant to request | Added user | Request detail |

**Push Notification Delivery:**
- Supabase Edge Function triggered by database webhooks (on insert to relevant tables)
- Edge Function sends push via Expo Push API (handles APNs and FCM from single API)
- Notification payload includes `community_id` and target screen for deep linking
- Badge count managed on device

---

## 11. Authentication

### Auth Methods (Launch)

- Email + password
- Apple Sign In
- (Google Sign In added later with Android deployment)

### Signup Flow

```
App opens → Auth check
  → No session → Login screen
    → "Sign Up" link → Signup screen
    → OR arriving via invite deep link → Signup screen (invite_code retained)

Signup screen:
  1. Email + password OR Apple Sign In
  2. Display name
  3. Avatar (optional, can add later)
  4. Phone number (optional)
  5. Submit → account created in Supabase Auth
  6. If invite_code present → auto-join or submit join request
  7. If no invite_code → community list (empty state: "Create or join a community")
```

### Login Flow
- Email + password or Apple Sign In
- "Forgot password" → Supabase Auth password reset email
- Biometric unlock (Face ID / Touch ID) for returning users if enabled
- Uses expo-local-authentication to verify identity, restores Supabase session from expo-secure-store

### Session Management
- Tokens stored in expo-secure-store (encrypted device storage)
- Auto-refresh via Supabase SDK
- On expiry → redirect to login
- Sign out clears secure storage + WatermelonDB local data

### Delete Account
- Profile → Settings → Delete Account
- Confirmation dialog with warning
- Edge Function handles: remove from all communities, anonymize messages ("Deleted User"), delete profile data, delete auth account
- Compliant with App Store account deletion requirements

---

## 12. Offline Strategy

### Hybrid Approach

| Action | Offline Behavior |
|---|---|
| Browse requests feed | Cached via TanStack Query — shows last fetched data |
| Create request | Optimistic — saved locally, syncs when online |
| Ask question on request | Optimistic — saved locally, syncs when online |
| Post to town hall | Optimistic — saved locally, syncs when online |
| Edit profile | Optimistic — saved locally, syncs when online |
| Claim a request | **Online only** — requires server validation to prevent double-claims |
| Send message | Written to WatermelonDB immediately, syncs to Supabase when online |
| Browse message history | Fully offline — loaded from WatermelonDB |
| Vote on post/comment | Optimistic — saved locally, syncs when online |

### Implementation

- **TanStack Query** handles server state caching for feeds, requests, town hall, profiles. Stale-while-revalidate pattern shows cached data instantly while refreshing in background.
- **WatermelonDB** handles messaging persistence. SQLite-based, lazy-loading — only loads visible messages. Supports thousands of messages without memory issues.
- **Connectivity listener** detects online/offline transitions and triggers sync of pending writes.
- **Pending indicator** on optimistically rendered content ("posting...", "sending...") until sync confirms.

---

## 13. Security & Performance

### Row-Level Security (RLS)

Every table has RLS policies ensuring users only access data from communities they belong to.

```sql
-- Users can only see requests from their communities
CREATE POLICY "community_members_see_requests" ON requests
  FOR SELECT USING (
    community_id IN (
      SELECT community_id FROM community_members
      WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Only request creator can edit their request
CREATE POLICY "creator_edits_request" ON requests
  FOR UPDATE USING (created_by = auth.uid());

-- Claim validation: cannot claim your own request or one you participate in
CREATE POLICY "cannot_claim_own_request" ON request_claims
  FOR INSERT WITH CHECK (
    claimed_by = auth.uid()
    AND claimed_by != (SELECT created_by FROM requests WHERE id = request_id)
    AND claimed_by NOT IN (
      SELECT user_id FROM request_participants WHERE request_id = request_claims.request_id
    )
  );

-- Messages visible only to conversation participants
CREATE POLICY "participants_see_messages" ON messages
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid() AND left_at IS NULL
    )
  );
```

### Performance Patterns

| Concern | Solution |
|---|---|
| Feed load speed | TanStack Query stale-while-revalidate — cached data renders instantly, refreshes in background |
| Message history | WatermelonDB lazy-loading from SQLite — loads only visible messages, paginates on scroll up |
| Image loading | expo-image with built-in caching and progressive loading |
| List rendering | FlashList (Shopify) instead of FlatList — 5-10x faster for long lists |
| Real-time subscriptions | Scoped per community — subscribe to active community's channels, unsubscribe on switch |
| Background sync | Pending offline writes sync on reconnect via connectivity listener |
| API efficiency | Supabase PostgREST column selection — only fetch fields needed for each view |

### Rate Limiting

- Client-side debounce on search inputs, vote taps, message sends
- Server-side rate limiting via Edge Functions for sensitive operations (claims, account creation)

---

## 14. Project Structure

```
naars-cars/
├── app/                              # Expo Router file-based routes
│   ├── (auth)/                       # Auth screens
│   │   ├── login.tsx
│   │   ├── signup.tsx
│   │   └── forgot-password.tsx
│   ├── (app)/                        # Authenticated app shell
│   │   ├── _layout.tsx               # Platform-level layout
│   │   ├── index.tsx                 # Community list (home)
│   │   ├── profile/
│   │   │   ├── index.tsx             # My profile
│   │   │   └── edit.tsx
│   │   ├── notifications.tsx         # Platform-level notifications
│   │   ├── create-community.tsx
│   │   ├── join-community.tsx
│   │   └── community/[id]/          # Inside a community
│   │       ├── _layout.tsx           # Community layout (tabs + back)
│   │       ├── (tabs)/
│   │       │   ├── requests/
│   │       │   │   ├── index.tsx     # Request feed
│   │       │   │   ├── create.tsx    # Create request
│   │       │   │   └── [requestId].tsx
│   │       │   ├── messages/
│   │       │   │   ├── index.tsx     # Conversation list
│   │       │   │   └── [conversationId].tsx
│   │       │   ├── town-hall/
│   │       │   │   ├── index.tsx     # Post feed
│   │       │   │   ├── create.tsx
│   │       │   │   └── [postId].tsx
│   │       │   └── community-info/
│   │       │       ├── index.tsx     # Members, leaderboard, info
│   │       │       └── settings.tsx  # Admin settings
│   │       └── member/[userId].tsx   # Public profile
├── src/
│   ├── components/                   # Reusable UI components
│   │   ├── ui/                       # Primitives (Button, Card, Input, Avatar)
│   │   ├── requests/                 # Request-specific components
│   │   ├── messaging/                # Message bubble, input bar, etc.
│   │   ├── community/                # Community card, member list
│   │   └── common/                   # Empty state, loading, error
│   ├── lib/                          # Core libraries
│   │   ├── supabase.ts               # Supabase client init
│   │   ├── watermelon/               # WatermelonDB schema & models
│   │   ├── queryClient.ts            # TanStack Query config
│   │   └── notifications.ts          # Push notification setup
│   ├── stores/                       # Zustand stores
│   │   ├── authStore.ts
│   │   ├── communityStore.ts         # Active community context
│   │   └── connectivityStore.ts
│   ├── hooks/                        # Custom React hooks
│   │   ├── useRequests.ts            # TanStack Query hooks
│   │   ├── useMessages.ts
│   │   ├── useCommunity.ts
│   │   └── useRealtime.ts            # Supabase realtime subscriptions
│   ├── services/                     # API / business logic
│   │   ├── requestService.ts
│   │   ├── messageService.ts
│   │   ├── communityService.ts
│   │   ├── notificationService.ts
│   │   ├── reviewService.ts
│   │   └── syncService.ts            # WatermelonDB <-> Supabase sync
│   ├── utils/                        # Pure utility functions
│   │   ├── validation.ts             # Zod schemas
│   │   ├── formatting.ts
│   │   └── deepLinking.ts
│   └── types/                        # Shared TypeScript types
│       ├── database.ts               # Matches Supabase schema
│       ├── navigation.ts
│       └── enums.ts
├── assets/                           # Images, fonts
├── supabase/
│   ├── migrations/                   # SQL migrations
│   └── functions/                    # Edge functions
├── app.config.ts                     # Expo config
├── eas.json                          # EAS Build config
├── tailwind.config.js                # NativeWind config
└── tsconfig.json
```

### Structural Decisions

1. **File-based routing mirrors navigation** — the `community/[id]` folder naturally scopes all community content.
2. **`src/` for non-route code** — clean separation between routes (`app/`) and logic/components (`src/`).
3. **Hooks as the bridge** — TanStack Query hooks in `src/hooks/` are how screens access data. Screens stay thin.
4. **Services handle API calls** — hooks call services, services call Supabase. Keeps Supabase coupling in one layer.
5. **WatermelonDB for messaging only** — requests and town hall use TanStack Query's in-memory cache. Messages use WatermelonDB for instant-load offline persistence.
