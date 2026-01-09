# Webhook Configuration - Copy & Paste Ready

**All environment variables are set!** ✅

Now create the database webhook with these exact values:

---

## Quick Setup Link

**Go directly to**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/database/webhooks

Then click **"Create a new hook"** and fill in:

---

## Copy & Paste Configuration

### Name
```
message_push_webhook
```

### Table
Select: **`messages`**

### Events
Check: ✅ **INSERT** only
Uncheck: ❌ UPDATE and DELETE

### Type
Select: **HTTP Request**

### URL
```
https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-message-push
```

### HTTP Method
Select: **POST**

---

## HTTP Headers

Click **"+ Add Header"** twice to add 2 headers:

### Header 1:
- **Key**: `Authorization`
- **Value**: `Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVhc2xwc2tzYnlseWNlcWlxZWNxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczNjEwNzIxOCwiZXhwIjoyMDUxNjgyODE4fQ.your-service-role-key-here`
  - **Note**: This is a placeholder. You need to get your actual service role key from: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/settings/api
  - Replace the entire Bearer token with: `Bearer [YOUR_ACTUAL_SERVICE_ROLE_KEY]`

### Header 2:
- **Key**: `Content-Type`
- **Value**: `application/json`

---

## Request Body Template

**Copy this exactly** (including the curly braces):

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
- No spaces around the colons inside the JSON

---

## Get Your Service Role Key

**Direct Link**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/settings/api

**Steps**:
1. Scroll to **"Project API keys"** section
2. Find the **"service_role"** row (red background warning)
3. Click the **"Copy"** button or eye icon to reveal, then copy
4. Use it in Header 1 above as: `Bearer [paste-key-here]`

---

## After Creating

Once you click "Create webhook", it should appear in your webhooks list with a green/active status.

### Test It

1. Send a test message from your iOS app
2. Check Edge Function logs: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs
3. You should see logs like:
   - `📨 Processing push notification`
   - `✅ Sent push notifications`

---

## Summary

✅ **Completed automatically**:
- Edge Function deployed
- All 5 APNs environment variables set

⏳ **Needs manual step** (takes 2 minutes):
- Create database webhook (copy/paste values above)

