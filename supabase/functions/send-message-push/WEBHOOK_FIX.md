# Fix Webhook Configuration

## Problem

The Edge Function is receiving the webhook, but the request body format is incorrect. The error shows:
```
Missing required message data from webhook
```

This means the webhook isn't sending the data in the expected format.

---

## Solution: Update Webhook Request Body

The webhook needs to send the message data as a JSON object. Here's how to fix it:

### Step 1: Go to Webhook Settings

1. Go to: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/database/webhooks
2. Find the webhook for `messages` table (should be named something like `message_push_webhook` or `on_message_inserted_push`)
3. Click **"Edit"** or the webhook name

### Step 2: Check Request Body Template

The request body should be in **JSON format**, not parameter format.

**If you see "Parameter Name" and "Parameter Value" fields**:
- Look for a toggle/button that says **"JSON"**, **"Raw"**, or **"Custom"**
- Switch to JSON mode
- You should see a single text area

**If you see a JSON text area**:
- Replace the content with the JSON below

### Step 3: Use This Exact JSON

**Copy and paste this exactly** (including the curly braces):

```json
{
  "id": "{{NEW.id}}",
  "conversation_id": "{{NEW.conversation_id}}",
  "from_id": "{{NEW.from_id}}",
  "text": "{{NEW.text}}"
}
```

**Important**:
- Keep the `{{` and `}}` exactly as shown
- No extra spaces
- No quotes around the template variables (just `{{NEW.id}}`, not `"{{NEW.id}}"`)

### Step 4: Save and Test

1. Click **"Save"** or **"Update"**
2. Send another test message from your app
3. Check Edge Function logs - you should now see:
   - `📨 Received webhook payload: {...}` (shows what was received)
   - `🔍 Extracted fields: {...}` (shows what was extracted)
   - Either success or a more detailed error message

---

## Alternative: If JSON Mode Not Available

If your webhook UI only supports parameter format, try this:

### Option A: Use Parameter Format (if required)

Add these parameters:

1. **Parameter Name**: `id` → **Parameter Value**: `{{NEW.id}}`
2. **Parameter Name**: `conversation_id` → **Parameter Value**: `{{NEW.conversation_id}}`
3. **Parameter Name**: `from_id` → **Parameter Value**: `{{NEW.from_id}}`
4. **Parameter Name**: `text` → **Parameter Value**: `{{NEW.text}}`

**Note**: This might not work if Supabase expects JSON format. The Edge Function needs the data as a JSON object, not form parameters.

### Option B: Check Webhook Type

Make sure the webhook type is set to:
- **Type**: HTTP Request
- **HTTP Method**: POST
- **Content-Type header**: `application/json`

---

## Verify Webhook is Working

After updating, check the Edge Function logs:
https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs

You should now see:
```
📨 Received webhook payload: {
  "id": "...",
  "conversation_id": "...",
  "from_id": "...",
  "text": "..."
}
🔍 Extracted fields: {
  "message_id": "...",
  "conversation_id": "...",
  "sender_id": "..."
}
```

If you still see errors, the logs will now show exactly what fields are missing.

---

## What the Edge Function Expects

The Edge Function looks for these fields in the webhook payload:
- `id` or `message_id` → Message UUID
- `conversation_id` → Conversation UUID
- `from_id` or `sender_id` → Sender's user UUID
- `text` → Message text (optional, used for preview)

If any of the first three are missing, you'll get the error.

