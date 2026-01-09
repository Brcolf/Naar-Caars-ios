# Fix Webhook Configuration for Edge Function Type

## Current Issue

Your webhook is configured as **"Supabase Edge Functions"** type, which is correct! However, you only have **one parameter** (`id`) configured. The Edge Function needs more data.

## Solution: Add Missing Parameters

Since you're using the **"Supabase Edge Functions"** type, you have two options:

### Option 1: Add All Required Parameters (Recommended)

In the **"HTTP Parameters"** section, add these 3 more parameters:

1. **Parameter Name**: `conversation_id`  
   **Parameter Value**: `{{NEW.conversation_id}}`

2. **Parameter Name**: `from_id`  
   **Parameter Value**: `{{NEW.from_id}}`

3. **Parameter Name**: `text`  
   **Parameter Value**: `{{NEW.text}}`

So you should have **4 parameters total**:
- `id`: `{{NEW.id}}`
- `conversation_id`: `{{NEW.conversation_id}}`
- `from_id`: `{{NEW.from_id}}`
- `text`: `{{NEW.text}}`

### Option 2: Remove Parameters (Let Supabase Auto-Pass Data)

When using **"Supabase Edge Functions"** type, Supabase automatically passes the NEW row data as JSON in the request body. So you might not need parameters at all!

**Try this**:
1. Remove the `id` parameter (click the X)
2. Leave HTTP Parameters section empty
3. Save the webhook
4. Test again

The Edge Function should automatically receive the full message row data.

---

## Which Option to Use?

**Try Option 2 first** (remove parameters). If that doesn't work, use Option 1 (add all parameters).

The Edge Function I just updated can handle both:
- JSON body (auto-passed by Supabase Edge Functions type)
- Form parameters (if you configure them)

---

## After Making Changes

1. **Save** the webhook
2. **Send another test message** from your app
3. **Check Edge Function logs**: https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/functions/send-message-push/logs

You should see:
- `📨 Received webhook payload (JSON): {...}` or `📨 Received webhook payload (Form Data): {...}`
- `🔍 Extracted fields: {...}`
- Either success or detailed error

---

## Current Configuration Summary

✅ **Correct**:
- Type: Supabase Edge Functions
- Edge Function: send-message-push
- Method: POST
- Headers: Content-type and Authorization

⚠️ **Needs Fix**:
- HTTP Parameters: Only has `id`, missing `conversation_id`, `from_id`, `text`
- OR: Remove parameters entirely and let Supabase auto-pass the data

