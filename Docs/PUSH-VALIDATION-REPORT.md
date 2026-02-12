# Push Notifications – Supabase MCP Validation Report

Ran via Supabase MCP on the linked project. Summary and required fix below.

---

## 1. Edge Functions

| Function             | Status  | Version |
|----------------------|--------|--------|
| `send-notification`  | ACTIVE | 10     |
| `send-message-push`  | ACTIVE | 18     |

Both functions exist and are deployed.

---

## 2. Database

| Check              | Result |
|--------------------|--------|
| **push_tokens**    | Table exists with expected columns: `id`, `user_id`, `device_id`, `token`, `platform`, `created_at`, `updated_at`, `last_used_at`. |
| **push_tokens rows** | **6** rows. Multiple devices/users have registered tokens. |
| **notification_queue** | **1,379** rows. Queue is in use. |

Sample `push_tokens`: user `0da568d8-924c-4420-8853-206a48d277b6` has tokens (e.g. prefix `1fb2a7903b18`) with `last_used_at` set (e.g. 2026-02-08), so push has worked for this user in the past.

---

## 3. Edge Function Logs (last 24h)

- **Every** logged request to `send-notification` and `send-message-push` returned **401 Unauthorized**.
- So webhooks **are** calling the Edge Functions, but the requests are **rejected before the function runs** (no push logic, no APNs calls).

Conclusion: the Database Webhooks are **not** sending a valid `Authorization` header (or the key is wrong/rotated).

---

## 4. Root cause and fix

**Cause:**  
Edge Functions have `verify_jwt: true`. The Database Webhooks that POST to these functions must send:

```http
Authorization: Bearer <SERVICE_ROLE_KEY>
```

If this header is missing or invalid, Supabase returns 401 and the function never executes.

**Fix (in Supabase Dashboard):**

1. Go to **Database** → **Webhooks**:  
   https://supabase.com/dashboard/project/easlpsksbylyceqiqecq/database/webhooks  
2. For **each** webhook that invokes `send-notification` or `send-message-push`:
   - Open the webhook.
   - If it’s an **HTTP Request** webhook: add a header **Authorization** = **Bearer \<your-service-role-key\>** (get the key from **Project Settings** → **API** → **service_role**).
   - If it’s an **Edge Function** webhook: check the docs for your Supabase version; if it doesn’t auto-add auth, switch to **HTTP Request** and set the URL to  
     `https://easlpsksbylyceqiqecq.supabase.co/functions/v1/send-notification` (or `send-message-push`) and add the **Authorization: Bearer \<service_role_key\>** header.
3. Save and trigger a test (e.g. new message or notification queue update). In **Edge Function** logs you should see **200** (or function-level errors), not 401.

---

## 5. APNs / secrets (not visible via MCP)

MCP cannot read Edge Function **secrets**. Confirm in the Dashboard:

- **Project Settings** → **Edge Functions** → **Secrets**
- **APNS_PRODUCTION** = **true** (for TestFlight/production; sandbox fallback is in code).
- **APNS_TEAM_ID**, **APNS_KEY_ID**, **APNS_KEY**, **APNS_BUNDLE_ID** are set and correct.

Once the webhook returns 200, if pushes still don’t arrive, check Edge Function logs for APNs errors (e.g. BadDeviceToken, 410) and that these secrets match your app and Apple config.

---

## 6. Checklist summary

| Item                         | Status |
|-----------------------------|--------|
| Edge Functions deployed     | OK     |
| push_tokens table & data    | OK     |
| notification_queue in use   | OK     |
| Webhooks invoking functions  | OK (they are called) |
| Webhook auth (401 → 200)    | **Fix: add Authorization: Bearer \<service_role_key\>** |
| APNs secrets                | Verify manually in Dashboard |

After fixing the webhook Authorization header, re-test push from TestFlight and from a debug build; use Edge Function logs to confirm 200 and any APNs errors.
