---
color: brown
position:
  x: -826
  y: -1161
isContextNode: false
agent_name: Amy
---

# Database: Schema & Migrations

PostgreSQL 15+ database on Supabase with 99+ migration files.

## Core Tables

### Authentication & Users
```sql
-- Managed by Supabase Auth
auth.users (id, email, created_at)

-- Custom profiles table
profiles (
    id UUID PRIMARY KEY (FK to auth.users),
    name TEXT NOT NULL,
    email TEXT,
    avatar_url TEXT,
    bio TEXT,
    phone TEXT,
    push_token TEXT,
    approved BOOLEAN DEFAULT false,
    is_admin BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
```

### Rides & Favors
```sql
rides (
    id UUID PRIMARY KEY,
    user_id UUID (poster),
    claimed_by UUID,
    type TEXT,
    date DATE,
    time TIME,
    pickup TEXT,
    destination TEXT,
    seats INT,
    notes TEXT,
    gift TEXT,
    status TEXT, -- 'open', 'pending', 'confirmed', 'completed'
    reviewed BOOLEAN,
    review_skipped BOOLEAN,
    estimated_cost FLOAT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)

favors (
    id UUID PRIMARY KEY,
    user_id UUID,
    claimed_by UUID,
    title TEXT,
    description TEXT,
    location TEXT,
    duration TEXT, -- 'under_hour', 'couple_hours', etc.
    requirements TEXT,
    date DATE,
    time TIME,
    gift TEXT,
    status TEXT,
    reviewed BOOLEAN,
    review_skipped BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)

-- Join tables for co-requestors
ride_participants (ride_id, user_id)
favor_participants (favor_id, user_id)
```

### Messaging
```sql
conversations (
    id UUID PRIMARY KEY,
    created_by UUID,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)

conversation_participants (
    conversation_id UUID,
    user_id UUID,
    last_seen TIMESTAMPTZ,
    PRIMARY KEY (conversation_id, user_id)
)

messages (
    id UUID PRIMARY KEY,
    conversation_id UUID,
    from_id UUID,
    text TEXT,
    image_url TEXT,
    audio_url TEXT,
    audio_duration FLOAT,
    latitude FLOAT,
    longitude FLOAT,
    location_name TEXT,
    message_type TEXT, -- 'text', 'image', 'audio', 'location', 'system'
    reply_to_id UUID,
    read_by UUID[], -- Array of user IDs
    edited_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ
)

message_reactions (
    message_id UUID,
    user_id UUID,
    reaction TEXT, -- emoji
    created_at TIMESTAMPTZ,
    PRIMARY KEY (message_id, user_id, reaction)
)
```

### Notifications
```sql
notifications (
    id UUID PRIMARY KEY,
    user_id UUID,
    type TEXT,
    title TEXT,
    message TEXT,
    read BOOLEAN DEFAULT false,
    ride_id UUID,
    favor_id UUID,
    conversation_id UUID,
    message_id UUID,
    review_id UUID,
    created_at TIMESTAMPTZ
)
```

### Community
```sql
town_hall_posts (
    id UUID PRIMARY KEY,
    user_id UUID,
    content TEXT,
    vote_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)

town_hall_comments (
    id UUID PRIMARY KEY,
    post_id UUID,
    user_id UUID,
    parent_id UUID, -- For threading
    content TEXT,
    vote_count INT DEFAULT 0,
    created_at TIMESTAMPTZ
)

town_hall_votes (
    user_id UUID,
    post_id UUID,
    comment_id UUID,
    vote_type TEXT, -- 'upvote' or 'downvote'
    PRIMARY KEY (user_id, post_id, comment_id)
)
```

### Reviews
```sql
reviews (
    id UUID PRIMARY KEY,
    reviewer_id UUID,
    reviewee_id UUID,
    ride_id UUID,
    favor_id UUID,
    rating INT, -- 1-5 stars
    comment TEXT,
    created_at TIMESTAMPTZ
)
```

### Admin
```sql
invite_codes (
    id UUID PRIMARY KEY,
    code TEXT UNIQUE,
    created_by UUID,
    used_by UUID,
    max_uses INT,
    uses INT DEFAULT 0,
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ
)
```

## Row Level Security (RLS)

### Critical Policies

**Profiles:**
- Users can read all profiles
- Users can update only their own profile
- Admins can update any profile

**Rides/Favors:**
- Users can read all open/confirmed requests
- Users can insert with `user_id = auth.uid()`
- Users can update own requests OR claimed requests
- ⚠️ **BUG:** Claim UPDATE policy blocks claimers (see below)

**Messages:**
- Users can read messages in conversations they're part of
- Users can insert messages to conversations they're part of
- Users can update/delete only their own messages

**Notifications:**
- Users can only see their own notifications
- System can insert notifications for any user

## Database Functions (RPCs)

### get_badge_counts(user_id)
Returns unread message and notification counts.
⚠️ **Performance Issue:** Does `COUNT(*)` on every call.

### get_conversations_with_details(user_id)
Returns conversations with participants, last message, unread count.
Recently optimized with better indexing.

### handle_new_user()
Trigger function that creates profile when auth.users row is inserted.

### update_conversation_updated_at()
Trigger to update `conversations.updated_at` on new message.

### increment_town_hall_comment_count()
Trigger to update `town_hall_posts.comment_count`.

## Recent Migrations

### Migration 097: Fix Request Claim RLS
Attempted to fix claim RLS but incomplete:
```sql
-- Split into separate claim/unclaim policies
-- But still doesn't allow initial claim when claimed_by IS NULL
```

### Migrations 101, 102, 106: Performance Indexes
```sql
-- Hot indexes for message search and badge counts
CREATE INDEX idx_messages_conversation_created
    ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_read_by_gin
    ON messages USING GIN (read_by);
```

### Migrations 104, 105: Disable Legacy Triggers
Disabled old message queue push notification trigger in favor of Edge Functions.

## Known Issues

### 🔴🔴🔴 Claim RLS Policy Bug (CRITICAL)

**Current Policy:**
```sql
CREATE POLICY "Users can update own or claimed rides"
ON rides FOR UPDATE
USING (auth.uid() = user_id OR auth.uid() = claimed_by)
WITH CHECK (auth.uid() = user_id OR auth.uid() = claimed_by);
```

**Problem:**
When `claimed_by IS NULL` (open request), claimer can't pass the USING clause:
- `auth.uid() = user_id` → FALSE (claimer ≠ poster)
- `auth.uid() = claimed_by` → FALSE (NULL ≠ anything)

**Fix Needed:**
```sql
-- Allow claim when claimed_by IS NULL
CREATE POLICY "Users can claim open rides"
ON rides FOR UPDATE
TO authenticated
USING (claimed_by IS NULL AND status = 'open')
WITH CHECK (claimed_by = auth.uid() AND status = 'confirmed');

-- Allow unclaim
CREATE POLICY "Users can unclaim their rides"
ON rides FOR UPDATE
TO authenticated
USING (claimed_by = auth.uid())
WITH CHECK (claimed_by IS NULL AND status = 'open');
```

Same issue exists for `favors` table.

## Migration File Organization

```
database/
├── 001_initial_schema.sql
├── 002_add_profiles.sql
├── ...
├── 097_fix_request_claim_rls.sql (incomplete fix)
├── 098-106_recent_optimizations.sql
└── 107_fix_claim_rls_properly.sql (NEEDED)
```

Total: 99 migration files + several needed

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
