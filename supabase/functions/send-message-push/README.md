# Edge Function: send-message-push

## 🚀 Getting Started

**For complete setup instructions, see:**
**[STEP_BY_STEP_SETUP.md](./STEP_BY_STEP_SETUP.md)** ← **Start here!**

This guide includes:
- Exact terminal commands and where to run them
- Precise Supabase UI navigation (where to click)
- Step-by-step configuration with examples

---

## Purpose

This Edge Function listens for `pg_notify` events from the database trigger `on_message_inserted_push` and sends push notifications to recipients when they receive new messages.

## How It Works

1. **Database Trigger** (`on_message_inserted_push` in `messages` table) fires immediately when a message is inserted
2. Trigger checks if recipient is actively viewing (via `last_seen` timestamp)
3. If not actively viewing, trigger sends `pg_notify` event with message details
4. This Edge Function listens for `pg_notify` events via Supabase Realtime
5. Edge Function fetches recipient's push tokens and sends to APNs

## Implementation

### Option 1: Listen via Supabase Realtime

```typescript
// supabase/functions/send-message-push/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

serve(async (req) => {
  try {
    const { recipient_user_id, conversation_id, sender_name, message_preview, message_id, sender_id } = await req.json()
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey)
    
    // Double-check if recipient is actively viewing (defense in depth)
    const { data: participant } = await supabase
      .from('conversation_participants')
      .select('last_seen')
      .eq('conversation_id', conversation_id)
      .eq('user_id', recipient_user_id)
      .single()
    
    if (participant?.last_seen) {
      const lastSeen = new Date(participant.last_seen)
      const now = new Date()
      const secondsSinceLastSeen = (now - lastSeen) / 1000
      
      // If viewed within last 60 seconds, skip push (user is viewing)
      if (secondsSinceLastSeen < 60) {
        return new Response(JSON.stringify({ skipped: true, reason: 'user_viewing' }), {
          headers: { 'Content-Type': 'application/json' },
        })
      }
    }
    
    // Get recipient's push tokens
    const { data: tokens, error: tokenError } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', recipient_user_id)
    
    if (tokenError || !tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ skipped: true, reason: 'no_tokens' }), {
        headers: { 'Content-Type': 'application/json' },
      })
    }
    
    // Get unread count for badge
    const { data: unreadData } = await supabase.rpc('get_unread_message_count', {
      p_user_id: recipient_user_id
    })
    const badgeCount = unreadData?.[0]?.count ?? 0
    
    // Send push to all devices for this user
    const pushPromises = tokens.map(async (tokenRow) => {
      return await sendAPNsPush({
        token: tokenRow.token,
        title: `Message from ${sender_name}`,
        body: message_preview,
        badge: badgeCount,
        priority: 10, // High priority for immediate delivery
        sound: 'default',
        data: {
          type: 'message',
          conversation_id: conversation_id,
          message_id: message_id,
          sender_id: sender_id
        }
      })
    })
    
    await Promise.all(pushPromises)
    
    return new Response(JSON.stringify({ sent: true, devices: tokens.length }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Error sending push notification:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

async function sendAPNsPush(payload: {
  token: string
  title: string
  body: string
  badge: number
  priority: number
  sound: string
  data: Record<string, string>
}) {
  // APNs implementation using apns2 or similar library
  // Use priority: 10 for immediate delivery (not queued)
  // This ensures notification arrives within seconds, not delayed
  
  // Example using apns2 library:
  // const apns = new apns2.Provider({
  //   team: Deno.env.get('APNS_TEAM_ID')!,
  //   keyId: Deno.env.get('APNS_KEY_ID')!,
  //   key: Deno.env.get('APNS_KEY')!
  // })
  // 
  // const notification = new apns2.Notification(payload.token, {
  //   topic: Deno.env.get('APNS_BUNDLE_ID')!,
  //   priority: payload.priority,
  //   payload: {
  //     aps: {
  //       alert: {
  //         title: payload.title,
  //         body: payload.body
  //       },
  //       sound: payload.sound,
  //       badge: payload.badge
  //     },
  //     ...payload.data
  //   }
  // })
  // 
  // return await apns.send(notification)
}
```

### Option 2: Direct HTTP Call from Trigger (if supported)

If Supabase supports calling Edge Functions directly from database triggers via `http` extension, you could modify the trigger to make an HTTP request directly.

## Environment Variables

Required in Supabase Dashboard > Edge Functions > Settings:

- `APNS_TEAM_ID` - Your Apple Team ID
- `APNS_KEY_ID` - Your APNs Key ID
- `APNS_KEY` - Your APNs private key (.p8 file content)
- `APNS_BUNDLE_ID` - Your app's bundle ID (e.g., `com.naarscars.app`)
- `APNS_PRODUCTION` - `true` for production, `false` for sandbox

## Testing

Test the Edge Function by sending a test payload:

```bash
curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/send-message-push \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "recipient_user_id": "USER_UUID",
    "conversation_id": "CONVERSATION_UUID",
    "sender_name": "Test Sender",
    "message_preview": "Test message preview...",
    "message_id": "MESSAGE_UUID",
    "sender_id": "SENDER_UUID"
  }'
```

## Performance

Expected latency:
- Database trigger fires: < 10ms
- pg_notify delivery: < 50ms
- Edge Function execution: < 200ms
- APNs delivery: < 500ms
- **Total: < 1 second from message insert to push notification**

