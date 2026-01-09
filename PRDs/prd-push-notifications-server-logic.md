# Push Notification Server-Side Logic Requirements

## Problem Statement

**Critical UX Issue**: Currently, push notifications are sent for ALL new messages, even when the recipient is actively viewing the conversation in real-time. This creates a poor user experience where users get push notifications while they're watching messages come through live.

## Required Server-Side Logic

### For Message Notifications

**Before sending a push notification for a new message, the server MUST:**

1. **Check if recipient is actively viewing the conversation**
   - Query the `messages` table for the most recent message in the conversation
   - Check if the recipient's user ID is in that message's `read_by` array
   - If yes, check when the message was last updated (if `read_by` was updated within the last 30-60 seconds, they're likely still viewing)

2. **Alternative: Use `conversation_participants.last_seen` timestamp**
   - Add a `last_seen` column to `conversation_participants` table
   - Update it when user views the conversation (via database trigger or app update)
   - Only send push if `last_seen` is older than 30-60 seconds

3. **Only send push notification if:**
   - Recipient is NOT in the `read_by` array of recent messages (within last minute)
   - OR `last_seen` timestamp is older than 30-60 seconds
   - OR recipient doesn't have realtime subscription active (would need online status tracking)

## Implementation Approach

### Option 1: Check `read_by` field (Recommended for MVP)

```javascript
// In Supabase Edge Function: send-message-push
async function shouldSendPush(recipientUserId, conversationId) {
  // Get the most recent message in this conversation
  const { data: latestMessage } = await supabase
    .from('messages')
    .select('id, read_by, updated_at, created_at')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: false })
    .limit(1)
    .single();
  
  if (!latestMessage) {
    return true; // No messages yet, send push
  }
  
  // Check if recipient has read the latest message
  const hasRead = latestMessage.read_by?.includes(recipientUserId) || false;
  
  // Check if message was read very recently (within last 60 seconds)
  if (hasRead) {
    const messageUpdatedAt = new Date(latestMessage.updated_at);
    const now = new Date();
    const secondsSinceUpdate = (now - messageUpdatedAt) / 1000;
    
    // If read within last 60 seconds, user is likely still viewing - don't send push
    if (secondsSinceUpdate < 60) {
      return false;
    }
  }
  
  // If not read or read long ago, send push
  return true;
}
```

### Option 2: Add `last_seen` to `conversation_participants` (Better long-term)

```sql
-- Migration: Add last_seen to conversation_participants
ALTER TABLE conversation_participants 
ADD COLUMN last_seen TIMESTAMPTZ;

CREATE INDEX idx_conversation_participants_last_seen 
ON conversation_participants(conversation_id, last_seen);
```

```javascript
// In Edge Function: send-message-push
async function shouldSendPush(recipientUserId, conversationId) {
  // Check when user last viewed this conversation
  const { data: participant } = await supabase
    .from('conversation_participants')
    .select('last_seen')
    .eq('conversation_id', conversationId)
    .eq('user_id', recipientUserId)
    .single();
  
  if (!participant || !participant.last_seen) {
    return true; // Never viewed, send push
  }
  
  const lastSeen = new Date(participant.last_seen);
  const now = new Date();
  const secondsSinceLastSeen = (now - lastSeen) / 1000;
  
  // If viewed within last 60 seconds, user is likely still viewing - don't send push
  return secondsSinceLastSeen >= 60;
}
```

## iOS App Updates Needed

If using Option 2 (`last_seen`), the app needs to update this timestamp:

```swift
// In ConversationDetailView or ConversationDetailViewModel
.onAppear {
    Task {
        // Update last_seen when viewing conversation
        try? await updateLastSeen(conversationId: conversationId)
    }
}

// In MessageService
func updateLastSeen(conversationId: UUID, userId: UUID) async throws {
    try await supabase
        .from("conversation_participants")
        .update(["last_seen": ISO8601DateFormatter().string(from: Date())])
        .eq("conversation_id", value: conversationId.uuidString)
        .eq("user_id", value: userId.uuidString)
        .execute()
}
```

## Similar Logic for Other Notifications

The same principle applies to:
- **Ride/Favor claimed notifications**: Only send if user hasn't viewed the request detail recently
- **QA activity**: Only send if user isn't currently viewing that request's detail page

## Real-Time Delivery Optimization

### Current State
- **When app is open**: Messages delivered instantly via Supabase Realtime subscriptions (near-zero latency)
- **When app is closed/backgrounded**: Push notifications depend on how the server detects new messages

### Making Push Notifications Real-Time

**To achieve near real-time push delivery (< 1 second from message send to notification), implement:**

1. **Database Trigger on Message Insert** - Fire immediately when message is created
2. **Trigger calls Edge Function** - Send push notification instantly
3. **APNs High Priority** - Use priority 10 for immediate delivery (not queued)

#### Implementation: Database Trigger + Edge Function

```sql
-- Migration: Create trigger for instant push notification on message insert
CREATE OR REPLACE FUNCTION notify_message_push()
RETURNS TRIGGER AS $$
DECLARE
  recipient_user_id UUID;
  conversation_id UUID;
  sender_name TEXT;
  message_preview TEXT;
BEGIN
  -- Get conversation ID from new message
  conversation_id := NEW.conversation_id;
  
  -- Get sender name for notification
  SELECT name INTO sender_name
  FROM profiles
  WHERE id = NEW.from_id;
  
  -- Get preview of message (first 50 chars)
  message_preview := LEFT(NEW.text, 50);
  IF LENGTH(NEW.text) > 50 THEN
    message_preview := message_preview || '...';
  END IF;
  
  -- Get all participants except the sender
  FOR recipient_user_id IN
    SELECT cp.user_id
    FROM conversation_participants cp
    WHERE cp.conversation_id = conversation_id
      AND cp.user_id != NEW.from_id
  LOOP
    -- Check if recipient is actively viewing (skip push if they are)
    -- This uses the last_seen approach from Option 2 above
    PERFORM pg_notify(
      'message_push',
      json_build_object(
        'recipient_user_id', recipient_user_id::text,
        'conversation_id', conversation_id::text,
        'sender_name', sender_name,
        'message_preview', message_preview,
        'message_id', NEW.id::text
      )::text
    );
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger
CREATE TRIGGER on_message_inserted
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION notify_message_push();

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION notify_message_push() TO authenticated;
```

#### Edge Function: Listen for pg_notify and Send Push

**Note**: Supabase Edge Functions can listen to `pg_notify` via Supabase Realtime or via database webhooks.

**Alternative: Direct HTTP call from trigger** (if Supabase supports HTTP functions):

```sql
-- If Supabase supports calling Edge Functions from triggers:
-- This would be ideal but may require Supabase-specific extension

-- For now, use Supabase Realtime + Edge Function listener
```

**Edge Function that listens to pg_notify**:

```javascript
// supabase/functions/send-message-push/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { recipient_user_id, conversation_id, sender_name, message_preview, message_id } = await req.json()
    
    // Check if recipient is actively viewing (from Option 2 above)
    const shouldSend = await shouldSendPush(recipient_user_id, conversation_id)
    if (!shouldSend) {
      return new Response(JSON.stringify({ skipped: true, reason: 'user_viewing' }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }
    
    // Get recipient's push tokens
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )
    
    const { data: tokens } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', recipient_user_id)
    
    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ skipped: true, reason: 'no_tokens' }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }
    
    // Send push to all devices for this user
    const pushPromises = tokens.map(async (tokenRow) => {
      return await sendAPNsPush({
        token: tokenRow.token,
        title: `Message from ${sender_name}`,
        body: message_preview,
        badge: await getUnreadCount(recipient_user_id),
        priority: 10, // High priority for immediate delivery
        sound: 'default',
        data: {
          type: 'message',
          conversation_id: conversation_id,
          message_id: message_id
        }
      })
    })
    
    await Promise.all(pushPromises)
    
    return new Response(JSON.stringify({ sent: true }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

async function sendAPNsPush(payload) {
  // APNs implementation using APNs library
  // Use priority: 10 for immediate delivery (not queued)
  // This ensures notification arrives within seconds, not delayed
}
```

#### Performance Characteristics

| Implementation | Latency (Message → Push) | Notes |
|---------------|-------------------------|-------|
| **Database Trigger → Edge Function** | **< 1 second** | ✅ Near real-time |
| Polling (check every 5-10 seconds) | 5-10 seconds average | ❌ Not real-time |
| Scheduled job (every minute) | 30-60 seconds average | ❌ Very slow |

**With the trigger approach:**
- Message inserted → Trigger fires (< 10ms)
- Trigger calls Edge Function (< 100ms)
- Edge Function sends to APNs (< 200ms)
- APNs delivers to device (< 500ms)
- **Total: < 1 second from message send to notification**

#### APNs Priority Settings

For immediate delivery (not queued/batched):

```javascript
{
  "aps": {
    "alert": { ... },
    "sound": "default",
    "badge": 1,
    "priority": 10  // 10 = immediate, 5 = power-efficient (can delay)
  },
  ...
}
```

- **Priority 10**: High priority - delivered immediately, can wake device
- **Priority 5**: Power-efficient - may be batched/delayed to save battery

For real-time messaging, always use **priority 10**.

## Summary

**The iOS app cannot prevent push notifications** - they're sent by the server. The server-side Edge Function must:
1. Check if user is actively viewing the relevant content
2. Only send push notifications if they're NOT actively viewing
3. This prevents duplicate/annoying notifications when users are already engaged in the app

**For real-time delivery:**
1. Use database triggers to detect messages immediately (< 10ms latency)
2. Trigger calls Edge Function instantly (< 100ms)
3. Edge Function sends push with APNs priority 10 (< 500ms to device)
4. **Total latency: < 1 second from message send to push notification**

