# Push Notifications — Root Cause Review

**Date:** 2026-02-08  
**Status:** Handoff for fix plan  
**Context:** Push notifications not working after turning off JWT auth on edge functions. This document summarizes the full pipeline, evidence, and likely root causes so a plan can be created to fix.

---

## 1. Pipeline Overview

### 1.1 App (iOS)

- **Permission:** `PushNotificationService.requestPermission()` / `checkAuthorizationStatus()`
- **Token:** APNs gives a device token → `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken` → `PushNotificationService.storeDeviceToken` + `registerDeviceToken(deviceToken:userId:)`
- **Registration:** Token is upserted into Supabase table `push_tokens` (by `user_id` + `device_id`). After login/signup, `registerStoredDeviceTokenIfNeeded(userId:)` runs to sync any stored token.

### 1.2 Backend (Supabase)

- **Tables:**  
  - `push_tokens`: one row per device; columns include `user_id`, `device_id`, `token`, `platform`, `last_used_at`.  
  - `notification_queue`: rows with `notification_type`, `recipient_user_id`, `payload`, `processed_at`, `sent_at`, `batch_key`.

- **Flow for general notifications (e.g. ride_claimed, completion_reminder):**  
  1. App or backend logic inserts into `notification_queue`.  
  2. Trigger `on_notification_queue_insert` (BEFORE INSERT) sets `processed_at = NOW()` for non-batched rows.  
  3. So the row is **inserted with `processed_at` already set**; there is **no subsequent UPDATE** on that row.  
  4. A **Database Webhook** (configured in Supabase Dashboard) must fire on `notification_queue` and call the Edge Function.  
  5. Edge Function **send-notification** runs. It either handles a direct request or parses webhook payload (event type / table). For queue processing it runs `processNotificationQueue()`: fetches up to 100 rows with `sent_at IS NULL` and `batch_key IS NULL`, sends via APNs, then sets `sent_at` for successful/skipped sends.

- **Flow for message pushes:**  
  1. New row in `messages`.  
  2. Database Webhook on `messages` invokes Edge Function **send-message-push**.  
  3. Function resolves recipient(s), fetches push tokens and badge count, sends APNs.

- **Trigger that does not invoke the Edge by itself:**  
  `on_notification_processed` (AFTER UPDATE on `notification_queue`) only runs when `processed_at` transitions from NULL to non-NULL. Because the BEFORE INSERT trigger already sets `processed_at`, **this UPDATE case rarely occurs** for normal inserts. The trigger does `pg_notify('notification_ready', ...)`, which is **not** the mechanism that calls the Edge Function; the **Database Webhook** is.

### 1.3 Edge Functions

- **send-notification** (`verify_jwt: false`):  
  - Handles direct payloads, `completion_response`, or webhook payloads.  
  - For webhook: expects `type`/`table` (e.g. `notification_queue`), and for **UPDATE** requires a “processed transition”: `record.processed_at` set, `old_record.processed_at` unset, `record.sent_at` unset.  
  - Then calls `processNotificationQueue()` which uses `SUPABASE_SERVICE_ROLE_KEY` and reads/writes `notification_queue` and `push_tokens`.

- **send-message-push** (`verify_jwt: false`):  
  - Handles webhook payload from `messages` (INSERT).  
  - Resolves sender/recipient, fetches tokens and badge (including `get_badge_counts`), sends APNs.

- **Shared APNs** (`_shared/apns.ts`):  
  - Requires env: `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY`, `APNS_BUNDLE_ID`.  
  - `APNS_PRODUCTION === 'true'` → try production first, then sandbox; otherwise sandbox first, then production.  
  - On 400 BadDeviceToken/DeviceTokenNotForTopic, retries the other environment.

---

## 2. Current Evidence

### 2.1 Edge Functions

- **MCP list_edge_functions:**  
  - `send-notification`: ACTIVE, **verify_jwt: false**, version 10.  
  - `send-message-push`: ACTIVE, **verify_jwt: false**, version 18.

- **Edge Function logs (recent):**  
  - All shown requests to both functions return **HTTP 200**.  
  - So the previous 401 (webhook auth) issue is **resolved**; the Edge is being invoked and runs to completion.

### 2.2 Database

- **push_tokens:**  
  - Table exists; multiple rows present (e.g. 6+), with recent `last_used_at` for some users.  
  - Indicates tokens are being stored and have been used for send attempts in the past.

- **notification_queue:**  
  - **46 rows** in state `processed_at` set and **sent_at** NULL (“processed_unsent”).  
  - **9** pending (processed_at NULL), **1388** sent.  
  - So a non-trivial number of notifications are being marked processed but **never** marked sent.

- **Triggers:**  
  - `notification_queue`: `on_notification_queue_insert` (BEFORE INSERT), `on_notification_processed` (AFTER UPDATE), `notifcation-queue-processor` (likely Database Webhook → `http_request`).  
  - `messages`: `message_push_webhook`, `on_message_created` (handle_new_message).

### 2.3 Postgres Logs

- One recent **ERROR**:  
  `malformed array literal: "[\"EE395FA8-455E-490B-B3FF-70214AEF195A\"]"`.  
- Suggests somewhere (app or backend) an array parameter (e.g. UUID array) is being passed as a **string** (e.g. JSON string) instead of a proper Postgres array.  
- This could affect RPCs used by the Edge (e.g. badge or message read state) and cause failures or wrong behavior during send.

### 2.4 App / Config

- **config.toml:**  
  - `[functions.send-notification]` and `[functions.send-message-push]` have `verify_jwt = false`.  
- **App:**  
  - Registers for remote notifications and registers token with Supabase after login; token is stored in `push_tokens` and updated on re-registration.

---

## 3. Root Cause Hypotheses (in order of likelihood)

### A. Webhook configuration (notification_queue)

- **Observation:** 46 notifications are processed but not sent. The only way the Edge runs for these is via the **Database Webhook** on `notification_queue`. The trigger `on_notification_processed` fires only on UPDATE when `processed_at` goes from NULL → set; for normal inserts, `processed_at` is set in the same INSERT, so **no UPDATE** happens and that trigger does not drive the Edge.
- **Hypothesis:**  
  - The webhook might be configured only for **UPDATE**. Then most inserts (with `processed_at` already set) never trigger the webhook.  
  - Or the webhook is not configured for the right table/events, or the webhook URL/type is wrong.
- **Check:** In Supabase Dashboard → Database → Webhooks, confirm a webhook on **notification_queue** that fires on **INSERT** (and optionally UPDATE), and that it targets the **send-notification** Edge Function (or the correct URL). Ensure it actually fires (e.g. by inserting a test row and checking Edge logs).

### B. send-notification UPDATE logic when webhook does fire on UPDATE

- **Observation:** For **UPDATE** events, the function only continues to `processNotificationQueue()` if the payload has a “processed transition”: `record.processed_at` set, `old_record.processed_at` unset, `record.sent_at` unset. Payload shape depends on Dashboard webhook (e.g. `record` / `old_record` vs `new` / `old`).
- **Hypothesis:**  
  - When the webhook sends an UPDATE, the payload might use different key names or structure.  
  - Then `resolveRecord` / `resolveOldRecord` don’t find the right fields, the transition check fails, and the function returns `{ skipped: true, reason: 'ignored_update' }` **without** processing the queue.
- **Check:** In the Edge Function, log the raw webhook payload (or at least `eventType`, `record`, `old_record`) for UPDATE events and confirm the transition is detected when it should be. Optionally make the transition check tolerant of more payload shapes.

### C. processNotificationQueue never sees the 46 rows (ordering / limit)

- **Observation:** `processNotificationQueue()` selects up to 100 rows with `sent_at IS NULL` and `batch_key IS NULL`, ordered by `created_at` ascending.
- **Hypothesis:**  
  - If the webhook fires often (e.g. many INSERTs), the function might repeatedly process “older” unsent rows and hit the 100 limit before reaching the 46.  
  - Unlikely to explain 46 stuck forever unless the webhook rarely runs or the same 100 rows are always chosen.
- **Check:** Log how many rows are returned and their IDs in each run; confirm whether the 46 appear in the result set.

### D. APNs send fails (no tokens, BadDeviceToken, or env)

- **Observation:** In the Edge, `sent_at` is only set when `result.sent || result.skipped` (e.g. “no_tokens” is skipped). If **all** device sends **fail** (e.g. APNs returns 4xx for every token), the code does not set `sent_at`, so the row stays “processed_unsent”.
- **Hypothesis:**  
  - For the 46 rows, recipients might have **no** `push_tokens` rows (e.g. wrong user id or token never registered).  
  - Or tokens are invalid (reinstall, different env) and APNs returns BadDeviceToken/410; the shared code retries the other environment and may still throw, so no `sent_at` update.  
  - Or Edge secrets are wrong/missing: `APNS_PRODUCTION`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY`, `APNS_BUNDLE_ID`.
- **Check:** In Edge logs, look for “No push tokens found for user” or APNs error lines. In Dashboard → Edge Functions → Secrets, confirm all APNs env vars. For a known recipient of one of the 46 rows, confirm they have a row in `push_tokens` and that the token is for the correct app/environment.

### E. get_badge_counts or other RPC failing (e.g. malformed array)

- **Observation:** Postgres log shows `malformed array literal: "[\"UUID\"]"`. The Edge calls `get_badge_counts(supabase, userId)` (and possibly other RPCs that take array arguments).
- **Hypothesis:**  
  - If the Edge or another client passes an array as a JSON string instead of a proper array, Postgres can throw.  
  - If that happens inside the send path, the request could 500 or skip updating `sent_at`.
- **Check:** Confirm whether `get_badge_counts` is called with correct types (e.g. `p_user_id` as UUID, `p_include_details` as boolean). Search code paths (including app) for any place that might pass `read_by` or similar as a string. Fix the caller to pass proper types; harden the RPC if it accepts client input that could be malformed.

---

## 4. Recommended Fix Plan (for handoff)

1. **Webhook (notification_queue)**  
   - In Dashboard, add or adjust the webhook on `notification_queue` so it fires on **INSERT** (and optionally UPDATE).  
   - Point it to the **send-notification** Edge Function.  
   - Verify: insert a test row and confirm one or more requests in Edge logs and that the row gets `sent_at` set when send succeeds or is skipped (e.g. no tokens).

2. **send-notification payload handling**  
   - Log incoming webhook payload (or at least type, table, record, old_record) for a few UPDATE and INSERT events.  
   - If UPDATE is used, align `resolveRecord` / `resolveOldRecord` with the actual webhook payload shape so the “processed transition” is recognized when appropriate.  
   - Optionally: for webhooks that don’t carry record/old_record, still call `processNotificationQueue()` so that any unsent rows (including the 46) are processed.

3. **APNs and tokens**  
   - Confirm Edge secrets (APNs env vars) in the Dashboard.  
   - For one recipient with a “processed_unsent” row, confirm they have a `push_tokens` row and that the token format and environment (sandbox vs production) match the app build.  
   - In Edge logs, add or inspect logs for “No push tokens” and APNs error responses to see if the 46 are failing due to tokens or APNs.

4. **Badge / RPC robustness**  
   - Track down the “malformed array literal” call site (app or Edge).  
   - Ensure all array arguments (e.g. UUID arrays) are passed as proper Postgres arrays, not JSON strings.  
   - If the Edge uses `get_badge_counts` with service role, ensure `p_user_id` is always passed (since `auth.uid()` may be null) and that the RPC is tolerant or that callers don’t pass invalid types.

5. **Retry the 46 rows**  
   - After webhook and code fixes, either:  
     - Trigger the Edge once with an empty or minimal body (it will run `processNotificationQueue()` and pick up the 46 if they match the query), or  
     - Run a one-off script/cron that POSTs to the send-notification URL to process the queue.  
   - Then confirm in DB that the 46 rows get `sent_at` set where expected.

---

## 5. References

- **Checklist:** `Docs/PUSH-NOTIFICATIONS-CHECKLIST.md`  
- **Validation report (pre–JWT fix):** `Docs/PUSH-VALIDATION-REPORT.md`  
- **Webhook 401 fix:** `Docs/PUSH-WEBHOOK-FIX-EDGE-FUNCTION-TYPE.md`  
- **Edge:** `supabase/functions/send-notification/index.ts`, `send-message-push/index.ts`, `_shared/apns.ts`, `_shared/badges.ts`  
- **App:** `NaarsCars/Core/Services/PushNotificationService.swift`, `AppDelegate.swift`  
- **DB:** `database/078_pg_cron_notification_jobs.sql`, `082_fix_notification_queue_processing.sql`, `104_disable_legacy_message_queue_push_trigger.sql`

---

## 6. Summary

- **JWT:** Fixed; Edge Functions return 200.  
- **Likely causes of “push not working”:**  
  1) **Database Webhook for notification_queue** not firing on INSERT (or not configured), so send-notification often never runs for new queue rows.  
  2) When it does run on UPDATE, **payload shape** can cause the function to skip queue processing.  
  3) **APNs or tokens:** some sends may fail (no tokens, bad token, or wrong APNs env), so those rows stay processed_unsent.  
  4) **RPC/array error** may occasionally break the send path.  

- **Next steps:** Verify and fix webhook (INSERT) for `notification_queue`, align send-notification with webhook payload, confirm APNs and tokens, fix malformed array usage, then reprocess the 46 unsent rows and re-test end-to-end.

---

## 7. Optional: app-side debug instrumentation

Temporary logging was added for handoff so that when you reproduce (e.g. on Simulator), you can confirm token and permission flow:

- **AppDelegate:** logs when APNs token is received (`tokenPrefix`, `hasUserId`) and when registration for remote notifications fails.
- **PushNotificationService:** logs at `registerStoredDeviceTokenIfNeeded` (permission status, “no stored token”, register success/failure) and when a token is updated/inserted in the DB.

Logs are sent via HTTP to the debug ingest endpoint (`http://127.0.0.1:7242/ingest/...`). That only works when the app can reach the host (e.g. **Simulator**). Ensure the debug log server is running and the log file is cleared before a run; then run the app (login, grant notification permission), trigger a notification, and inspect `.cursor/debug.log` for `push_handoff` entries. Remove these logs after the fix is verified.
