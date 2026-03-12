---
color: green
position:
  x: -575
  y: -1201
isContextNode: false
agent_name: Amy
---

# Backend: Supabase Edge Functions

TypeScript/Deno functions running on Supabase Edge Runtime.

## Edge Functions

### send-message-push
**Path:** `supabase/functions/send-message-push/`

**Purpose:** Send APNs push notifications for new messages.

**Trigger:** Database webhook on `messages` table INSERT.

**Flow:**
1. Receive message webhook payload
2. Parse JSON/FormData/Text (fragile multi-format handling)
3. Fetch conversation participants
4. Filter out sender and blocked users
5. Batch fetch push tokens for recipients
6. Batch fetch badge counts in parallel
7. Construct APNs payload for each recipient
8. Send to Apple Push Notification Service

**APNs Payload:**
```json
{
  "aps": {
    "alert": {
      "title": "Sender Name",
      "body": "Message preview..."
    },
    "badge": 5,
    "sound": "default",
    "category": "MESSAGE"
  },
  "conversation_id": "uuid",
  "message_id": "uuid"
}
```

**Authentication:**
Uses Apple Push Notification Service (APNs) with:
- Team ID
- Key ID
- Private key (`.p8` file)
- JWT signing

**Recent Improvements:**
✅ Batch fetches push tokens (was N+1)
✅ Parallel badge count fetching

**Technical Debt:**
🟡 **Fragile webhook parsing** - Nested try-catch for multiple formats indicates inconsistent upstream payloads.

---

### send-notification
**Path:** `supabase/functions/send-notification/`

**Purpose:** Send push notifications for various app events (not messages).

**Trigger:** Called by other database functions/triggers.

**Events:**
- Ride/favor posted
- Request claimed
- Review received
- Town Hall reply
- Admin approval

**Similar to send-message-push but generalized for all notification types.**

---

## Shared Code

### _shared/apns.ts
Common APNs utilities:
- JWT signing for APNs authentication
- HTTP/2 client for APNs API
- Token validation
- Error handling

### _shared/database.ts (implied)
Database connection utilities:
- Supabase client setup
- RLS bypass for server operations
- Query helpers

## Database Webhooks

Configured in Supabase dashboard:
- **messages INSERT** → send-message-push
- **notifications INSERT** → send-notification (maybe)
- **rides/favors status change** → send-notification

## Environment Variables

Edge Functions require:
```bash
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=xxx
APPLE_TEAM_ID=xxx
APPLE_KEY_ID=xxx
APPLE_PRIVATE_KEY=xxx
```

## Deployment

```bash
supabase functions deploy send-message-push
supabase functions deploy send-notification
```

## Monitoring

Supabase provides:
- Function invocation logs
- Error tracking
- Performance metrics
- Webhook delivery status

## Local Development

```bash
supabase functions serve send-message-push
# Test with curl
curl -X POST http://localhost:54321/functions/v1/send-message-push \
  -H "Content-Type: application/json" \
  -d '{"record": {...}}'
```

## Technical Debt

### 🟡 Webhook Parsing Fragility
```typescript
// Multiple try-catch blocks for different formats
try {
  body = await req.json()
} catch {
  try {
    const formData = await req.formData()
    body = Object.fromEntries(formData)
  } catch {
    body = await req.text()
  }
}
```

**Issue:** Indicates inconsistent webhook payload formats from Supabase.

**Fix:** Standardize on JSON and add strict typing.

### 🟢 Badge Count Query (mentioned earlier)
Edge Functions call `get_badge_counts` RPC which is slow.
Fix in database layer will benefit Edge Functions too.

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
