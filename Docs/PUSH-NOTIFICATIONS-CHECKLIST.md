# Push Notifications Checklist (TestFlight / Production)

Use this when push notifications work in development but not in TestFlight or production.

**Note:** Supabase MCP was not available in the session that created this doc; validation was done from the codebase. To verify secrets and webhooks live, use the Supabase Dashboard or Supabase CLI.

---

## 1. APNs environment (most common cause)

**TestFlight and App Store builds must use production APNs.** The app’s entitlements and Supabase Edge must both support production; the Edge code already supports **both** sandbox and production with one deployment.

### One Edge config for both TestFlight and Xcode debug

In **`supabase/functions/_shared/apns.ts`**, the sender tries one APNs environment first, and on **400 BadDeviceToken / DeviceTokenNotForTopic** it automatically tries the other:

- **`APNS_PRODUCTION === 'true'`** → try **production** first, then **sandbox** (fallback).
- **`APNS_PRODUCTION !== 'true'`** → try **sandbox** first, then **production** (fallback).

So a **single** Supabase Edge deployment with **`APNS_PRODUCTION=true`** can serve:

- **TestFlight / App Store** (production tokens) → first request succeeds.
- **Xcode run / Debug** (sandbox tokens) → first request gets 400 → fallback to sandbox → succeeds.

**Recommendation:** Set **`APNS_PRODUCTION`** = **`true`** so production (TestFlight) is preferred; debug builds still work via fallback.

### Xcode entitlements (already correct in this project)

- **Release / TestFlight**: `NaarsCars.entitlements` → `aps-environment` = **production** ✅  
- **Debug**: `NaarsCarsDebug.entitlements` → `aps-environment` = **development** ✅  

No change needed unless you add a new configuration.

### Supabase Edge Function secrets

In **Supabase Dashboard** → **Project Settings** → **Edge Functions** → **Secrets**, set:

| Secret            | Value | Purpose |
|-------------------|--------|---------|
| `APNS_PRODUCTION` | **`true`** | Prefer production APNs (TestFlight/App Store); sandbox still used when token is sandbox (automatic fallback in code). |
| `APNS_TEAM_ID`    | Your Apple Team ID | Required for APNs JWT. |
| `APNS_KEY_ID`     | Your APNs Key ID   | Required for APNs JWT. |
| `APNS_KEY`        | Base64-encoded .p8 file content | Required for APNs JWT. |
| `APNS_BUNDLE_ID`  | e.g. `com.NaarsCars` | Must match the app’s bundle ID. |

If `APNS_PRODUCTION` is `false` or unset, the Edge Function tries sandbox first; TestFlight devices (production tokens) may not receive pushes until the fallback runs.

---

## 2. Database webhook (send-notification)

Push for **request/notification** events is sent by the `send-notification` Edge Function, which must be invoked when the `notification_queue` table is updated.

- **Trigger**: `trigger_notification_send()` runs on `notification_queue` AFTER UPDATE when `processed_at` is set; it only does `pg_notify('notification_ready', ...)`.  
- **Invocation**: The actual send is done by a **Database Webhook** that calls the Edge Function. If the webhook is missing or wrong, no push is sent.

**Check in Supabase Dashboard** → **Database** → **Webhooks**:

- There is a webhook on table **`notification_queue`**.
- Events include **INSERT** and/or **UPDATE** (as per `send-notification/WEBHOOK_SETUP.md`).
- Type: **Supabase Edge Functions**.
- Function: **`send-notification`**.

If the webhook is not configured, add it (see `supabase/functions/send-notification/WEBHOOK_SETUP.md`).

---

## 3. Message pushes (send-message-push)

**New message** pushes use a different Edge Function: **`send-message-push`**, usually invoked by a webhook on the **`messages`** table (or similar). Confirm in Database → Webhooks that the messages table has a webhook pointing to **`send-message-push`** (or whatever your message push function is named).

Same Edge secrets apply: `APNS_PRODUCTION` must be **`true`** for TestFlight.

---

## 4. Push tokens in the database

The app logs **"Updated device token for user …"** when it successfully upserts into `push_tokens`. If that appears, the token is in the DB.

**Verify in Supabase** → **Table Editor** → **`push_tokens`**:

- There is a row for the test user with `user_id` = their UUID.
- `token` is the APNs device token string.
- `platform` = `ios` (or your convention).

If no row appears after login, check RLS and that `PushNotificationService.registerDeviceToken()` is called after auth (and that the app has notification permission).

---

## 5. Quick verification

1. Set **`APNS_PRODUCTION`** = **`true`** for the Supabase project used by TestFlight.  
2. Confirm **Database Webhooks** for `notification_queue` → `send-notification` and (if used) `messages` → `send-message-push`.  
3. Install the TestFlight build, log in, and confirm a row in **`push_tokens`** for that user.  
4. Background or quit the app and trigger a notification (e.g. new request or new message from another user).  
5. Check **Edge Function logs** in Supabase for `send-notification` / `send-message-push`: look for “Sent push” or “No push tokens” / 4xx errors.

---

## 6. References

- **APNs shared code**: `supabase/functions/_shared/apns.ts` (uses `APNS_PRODUCTION === 'true'` for production URL).  
- **Request/notification push**: `supabase/functions/send-notification/index.ts`.  
- **Message push**: `supabase/functions/send-message-push/index.ts`.  
- **Webhook setup**: `supabase/functions/send-notification/WEBHOOK_SETUP.md`.
