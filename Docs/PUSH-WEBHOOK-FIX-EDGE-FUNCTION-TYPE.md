# Fix 401 on Push Webhooks (Supabase Edge Functions type)

Your webhooks are set up as **Supabase Edge Functions** and you already have the correct Authorization headers—but every call still returns **401**. The Edge Runtime rejects the request **before** your function runs, so the issue is at the gateway, not your code.

**Cause:** When the webhook type is "Supabase Edge Functions", the Dashboard may not actually send the configured headers to the function (or the runtime may not accept them). So the request arrives without a valid JWT and returns 401.

**Fix:** Turn off JWT verification for these two functions so the webhook can invoke them without a Bearer token. The functions use `SUPABASE_SERVICE_ROLE_KEY` for DB access and don't rely on the incoming JWT.

## What was changed in the repo

- **`supabase/config.toml`** was added with:
  - `[functions.send-notification]` → `verify_jwt = false`
  - `[functions.send-message-push]` → `verify_jwt = false`

The CLI uses this on deploy so the next deployment of these functions will accept unauthenticated requests (e.g. from the Database Webhook).

## What you need to do

1. **Redeploy both functions** (from the project root, with Supabase CLI linked to your project):

   ```bash
   supabase functions deploy send-notification
   supabase functions deploy send-message-push
   ```

2. **Test:** Trigger a notification (e.g. new message or new row in `notification_queue`).  
   In **Edge Functions** → **Logs** you should see **200** instead of 401.

3. **(Optional)** You can remove the Authorization header from the webhooks in the Dashboard if you want; it's no longer required for these two functions.

After this, push delivery should work as long as your APNs secrets (e.g. `APNS_PRODUCTION=true`) are set correctly.
