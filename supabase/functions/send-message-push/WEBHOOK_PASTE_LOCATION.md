# Where to Paste the Request Body Template

## Step-by-Step Location

1. **Go to**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/database/webhooks

2. **Click**: **"Create a new hook"** button (usually top right)

3. **Fill in the form** (top to bottom):

   - **Name**: `message_push_webhook`
   - **Table**: Select `messages` from dropdown
   - **Events**: Check `INSERT` only
   - **Type**: Select `HTTP Request`
   - **URL**: `https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push`
   - **HTTP Method**: Select `POST`

4. **HTTP Headers** section:
   - Click **"+ Add Header"** button
   - **Header 1**:
     - Key: `Authorization`
     - Value: `Bearer [your-service-role-key]` (get from Settings → API)
   - Click **"+ Add Header"** again
   - **Header 2**:
     - Key: `Content-Type`
     - Value: `application/json`

5. **Scroll down** to find: **"Request Body Template"** or **"Payload Template"** field

   This field is usually:
   - Below the HTTP Headers section
   - A large text area or code editor box
   - May be labeled as:
     - "Request Body Template"
     - "Payload Template"
     - "Request Body"
     - "Webhook Payload"
     - Sometimes has a dropdown for "Custom" vs "Default"

6. **Paste this EXACT text** into that field:

```json
{
  "id": "{{NEW.id}}",
  "conversation_id": "{{NEW.conversation_id}}",
  "from_id": "{{NEW.from_id}}",
  "text": "{{NEW.text}}"
}
```

**Important**: 
- Keep the `{{` and `}}` exactly as shown (these are Supabase template variables)
- Make sure you paste it into the **Request Body Template** field, NOT the URL field or headers

7. **Click**: **"Create webhook"** or **"Save"** button at the bottom

---

## Visual Guide

```
┌─────────────────────────────────────────┐
│ Create Webhook                          │
├─────────────────────────────────────────┤
│ Name: [message_push_webhook]            │
│ Table: [messages ▼]                     │
│ Events: ☑ INSERT  ☐ UPDATE  ☐ DELETE   │
│ Type: [HTTP Request ▼]                  │
│ URL: [https://...]                      │
│ Method: [POST ▼]                        │
│                                         │
│ HTTP Headers:                           │
│   [Key]      [Value]                    │
│   Authorization  Bearer ...             │
│   Content-Type   application/json       │
│   [+ Add Header]                        │
│                                         │
│ ▼ Request Body Template ← PASTE HERE!  │
│ ┌─────────────────────────────────────┐ │
│ │ {                                    │ │
│ │   "id": "{{NEW.id}}",               │ │
│ │   "conversation_id": "...",         │ │
│ │   ...                               │ │
│ │ }                                    │ │
│ └─────────────────────────────────────┘ │
│                                         │
│        [Create webhook]  [Cancel]       │
└─────────────────────────────────────────┘
```

---

## If You Can't Find "Request Body Template" Field

Sometimes the field might be:
- Collapsed/hidden - look for a "▼" arrow or "Show advanced options"
- Labeled differently - look for any field about "body", "payload", or "data"
- In a different tab - check if there are tabs like "Basic" and "Advanced"

If you still can't find it, the webhook might have a default payload. The webhook will still work, but the Edge Function will need to parse the default format instead.

---

## After Pasting

1. Review all fields to make sure they're correct
2. Click **"Create webhook"** or **"Save"**
3. You should see the webhook appear in your webhooks list
4. It should show as "Active" or have a green status indicator

