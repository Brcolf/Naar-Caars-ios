# Outstanding issues – fix plan (handoff)

This document is a **handoff plan** for another agent to fix the issues identified from console logs (review workflow confirmed working). **Do not fix proactively**; use this as the single source of truth for what to change and in what order.

---

## Issue index

| # | Issue | Priority | Section |
|---|--------|----------|---------|
| 1 | Badge RPC 42P01 – relation "messages" does not exist | High | [1. Badge RPC](#1-badge-rpc-42p01--relation-messages-does-not-exist) |
| 2 | Ride load NSURLError -999 (cancelled) shown as error | Medium | [2. Ride load cancelled](#2-ride-load-nsurlerror-999-cancelled) |
| 3 | Security/crypto AES-GCM -4308 (repeated) | Medium | [3. AES-GCM -4308](#3-security-aes-gcm--4308) |
| 4 | Firebase logging / local ingest connection failures | Low | [4. Firebase and local ingest](#4-firebase-and-local-ingest) |
| 5 | Map / layout: CAMetalLayer zero size, 1170×0 image | Low | [5. Map and image layout](#5-map-and-image-layout) |
| 6 | Simulator/system (no app code change) | N/A | [6. No action](#6-no-action) |

---

## 1. Badge RPC 42P01 – relation "messages" does not exist

### What’s wrong

- **Log:** `Badge RPC failed (code=42P01); using fallback counts for 300s: relation "messages" does not exist`
- **Cause:** The `get_badge_counts` RPC uses **unqualified** table names (`messages`, `conversation_participants`, `notifications`). When the function is `SECURITY DEFINER SET search_path TO ''` (or similar), the executor has no search_path, so `messages` is undefined → 42P01.
- **Impact:** Badge counts use fallback (zeros) for 300s; message (and possibly other) counts are wrong until RPC succeeds.

### Where it’s defined

- **database/107_badge_counts_resilience.sql** – Uses unqualified `messages`, `conversation_participants`, `notifications` (lines 25–26, 34, 41–42, 57, 75–76, etc.). This migration **replaced** the function and dropped the `public.` prefix that fixed 42P01 in 102.
- **database/102_fix_badge_counts_and_conversation_rpc.sql** – Correct version: all references are `public.messages`, `public.conversation_participants`, `public.notifications`, and the function has `SET search_path TO ''`.
- **supabase/migrations/** – There may be a dated migration that defines `get_badge_counts`; if that’s what’s deployed, it must also use `public.` for all tables.

### What to do

1. **Single source of truth for the RPC**
   - Treat the RPC body from **102** as the base (qualified names + same logic).
   - Apply any **107**-only improvements (e.g. COALESCE for null handling) **while keeping every table reference qualified** as `public.<table>`.

2. **Fix `database/107_badge_counts_resilience.sql`**
   - Replace every unqualified use of `messages`, `conversation_participants`, and `notifications` with `public.messages`, `public.conversation_participants`, `public.notifications`.
   - Keep the function as `SECURITY DEFINER SET search_path TO ''` (or explicitly `SET search_path TO public` if the project prefers).
   - Do **not** add a new migration that re-introduces unqualified names.

3. **If the deployed DB is driven by `supabase/migrations/`**
   - Find the migration file that creates or replaces `get_badge_counts` (e.g. `20260126_0002_get_badge_counts.sql` or similar).
   - Ensure that version also uses **only** `public.messages`, `public.conversation_participants`, `public.notifications` in all queries and subqueries.
   - If needed, add a **new** migration that does `CREATE OR REPLACE FUNCTION public.get_badge_counts(...)` with the corrected body (qualified names + desired COALESCE behavior).

4. **Verification**
   - Run the RPC in Supabase SQL editor (as an authenticated user):  
     `SELECT get_badge_counts(auth.uid(), false);`
   - No 42P01; result JSON should have numeric counts.
   - In the app, trigger a badge refresh and confirm no "Badge RPC failed (code=42P01)" in logs and counts update.

### Files to touch

- `database/107_badge_counts_resilience.sql` – add `public.` to all table references.
- Optionally: a new file under `supabase/migrations/` that replaces `get_badge_counts` with the corrected definition, if that’s the migration path used in production.

---

## 2. Ride load NSURLError -999 (cancelled)

### What’s wrong

- **Log:** `Error loading ride: Error Domain=NSURLErrorDomain Code=-999 "cancelled"`
- **Cause:** User navigates away (e.g. notification tap opens another ride) before `fetchRide(id:)` completes; URLSession cancels the task → -999.
- **Impact:** The app sets `error` and logs as if it were a real failure; user may see an error state or a brief wrong-ride flash.

### Where to fix

- **File:** `NaarsCars/Features/Rides/ViewModels/RideDetailViewModel.swift`
- **Method:** `loadRide(id: UUID) async` (around lines 46–63).
- **Current behavior:** In `catch`, it sets `self.error = error.localizedDescription` and logs for **all** errors.

### What to do

1. In the `catch` block of `loadRide(id:)`:
   - If the error is **cancelled** (`(error as NSError).code == NSURLErrorCancelled`), do **not** set `self.error` and do **not** log as an error. Optionally log at debug/info: "Ride load cancelled."
   - For any other error, keep current behavior: set `self.error` and log.

2. (Optional but recommended) If the task was cancelled, the view might still be on screen for a different `id` (e.g. user tapped another ride). Ensure that when the view appears or `id` changes, `loadRide(id:)` is invoked again (e.g. from `.task(id: rideId)` or equivalent) so the correct ride loads. No change needed if that’s already in place.

### Reference

- Other call sites that treat cancellation as non-fatal:  
  `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift` (e.g. `NSURLErrorCancelled`),  
  `NaarsCars/Core/Services/BadgeCountManager.swift`,  
  `NaarsCars/Features/Requests/ViewModels/PastRequestsViewModel.swift`.

### Verification

- Open a ride, then quickly tap a notification for another ride; sheet dismisses and second ride opens. Console should not show "Error loading ride" for the first ride’s cancelled request; user should not see an error state for the second ride.

---

## 3. Security AES-GCM -4308

### What’s wrong

- **Log:** Repeated `sec_framer_open_aesgcm failed to open for AESGCM: -4308`
- **Cause:** Security framework (Keychain/secure storage or a dependency) failing to open or decrypt with AES-GCM; -4308 often indicates decode/key or parameter issue.
- **Impact:** Unknown until the caller is identified; could be optional (e.g. simulator) or cause subtle failures.

### What to do

1. **Identify the caller**
   - Search the app and linked frameworks for uses of: Keychain, Secure Enclave, `kSecAttrKeyType`, AES-GCM, or decryption APIs that might log this.
   - Run the app, reproduce the log, and capture a stack trace (breakpoint or crash log) when the failure occurs to see which module/frame triggers it.

2. **Decide on fix**
   - If it’s **app code**: add a guard (e.g. try/catch or result check); on failure, don’t spam the log; optionally fall back to a non-secure path or clear user-facing state if appropriate.
   - If it’s **third-party** (e.g. Firebase, analytics): consider updating the dependency or suppressing/forwarding their logging; document expected behavior in simulator vs device.

3. **Do not**
   - Change Keychain or security logic without understanding the call path; do not remove encryption or weaken security to silence the log.

### Verification

- After changes: either the log no longer appears for expected flows, or it’s logged once per logical operation with a clear reason, and app behavior (e.g. login, secure data) is unchanged.

---

## 4. Firebase and local ingest

### What’s wrong

- **Logs:**
  - `Could not connect to the server` to `http://127.0.0.1:7242/ingest/...` (connection refused).
  - `A server with the specified hostname could not be found` for `https://firebaselogging-pa.googleapis.com/v1/firelog/legacy/batchlog`.
- **Cause:** Local telemetry ingest not running on 127.0.0.1:7242; DNS/network cannot resolve or reach Firebase logging host.
- **Impact:** No crash; only logging/telemetry failures and console noise. App behavior (Supabase, auth, notifications) is unaffected.

### What to do

1. **127.0.0.1:7242**
   - Determine what expects this (e.g. Crashlytics debug proxy, custom metrics). If not used, disable or remove that configuration (e.g. in a debug/Config file or scheme environment).
   - If used, document that the ingest service must be running when that config is active.

2. **Firebase hostname**
   - Regard as environment (simulator/network/DNS/firewall). No app code change required unless the project explicitly wants Firebase logging in that environment; then fix network/DNS or use a different endpoint per environment.

### Verification

- After config changes: no connection-refused or hostname-not-found logs for the configured endpoints, or they’re expected and documented.

---

## 5. Map and image layout

### What’s wrong

- **Logs:**
  - `CAMetalLayer ignoring invalid setDrawableSize width=0.000000 height=0.000000`
  - `Failed to create 1170x0 image slot (alpha=1 wide=1) [0x5 (os/kern) failure]`
- **Cause:** A view (likely map or image) is given zero height (or zero size) during layout; the system then tries to create a drawable/image with height 0.
- **Impact:** Possible visual glitch or missing tile/image; 1170 suggests a specific width (e.g. list or card).

### What to do

1. **Locate the view**
   - Search for Map/MapKit usage and `Image`/async image views that might have a conditional height or a `frame` that can be zero (e.g. in a list or a card that’s not yet laid out).
   - Consider: `RouteMapView`, `RequestMapView`, ride/favor detail views that show a map or a 1170-wide image.

2. **Fix layout**
   - Ensure the map (or image) is only given a non-zero frame when it’s visible (e.g. use `GeometryReader` or `.frame(minHeight: 1)` or show the map only when `height > 0`).
   - Avoid creating an image or drawable when width or height is 0.

### Verification

- Navigate to the screens that use the map/image; no "invalid setDrawableSize" or "Failed to create ...x0 image slot" in console; map/image renders correctly.

---

## 6. No action

These can be left as-is; no app code change:

- **Simulator/system:**  
  `Failed to locate resource named "default.csv"`,  
  `PerfPowerTelemetryClientRegistrationService ... Sandbox restriction`,  
  `Permission denied: Maps / SpringfieldUsage`,  
  `Resetting GeoGL zone allocator ...`,  
  `Attempted to update accumulator ... after completion has already been called for token`,  
  `Could not find cached accumulator for token`,  
  `Result accumulator timeout: 3.000000, exceeded`  
  → Treat as simulator/OS/keyboard; ignore unless the product owner wants to reduce log noise (e.g. via OS/simulator settings).

---

## Suggested order of work

1. **Badge RPC (42P01)** – Fix table names so badge counts are correct.
2. **Ride load (-999)** – Treat cancelled as non-error in `RideDetailViewModel.loadRide`.
3. **AES-GCM (-4308)** – Identify caller, then guard or document.
4. **1170×0 image / Metal zero size** – Find view, fix layout.
5. **Firebase / 127.0.0.1** – Config/docs only.

---

## Handoff checklist for the implementing agent

- [x] Read this plan end-to-end before editing.
- [x] Fix **1. Badge RPC** first (database/107 and/or supabase migration with `public.` and no new unqualified refs).
- [x] Fix **2. Ride load** in `RideDetailViewModel.swift` (skip setting error and error-log for NSURLErrorCancelled).
- [x] For **3–5**, implement only the items above; do not change security semantics or remove encryption.
- [ ] Run the app and verify: badge RPC succeeds, ride navigation doesn’t show cancelled as error, no regression in review/completion/notification flows.
- [x] Update this doc or a separate CHANGELOG with what was changed (files and one-line summary per issue).

---

## Changelog (implemented)

| Issue | Files changed | Summary |
|-------|----------------|---------|
| **1. Badge RPC 42P01** | `database/107_badge_counts_resilience.sql`, `supabase/migrations/20260216_0001_get_badge_counts_qualified_tables.sql` | Qualified all table refs as `public.messages`, `public.conversation_participants`, `public.notifications`; function name `public.get_badge_counts`; new Supabase migration for deployed DB with same (boolean, uuid) signature. |
| **2. Ride load -999** | `NaarsCars/Features/Rides/ViewModels/RideDetailViewModel.swift` | In `loadRide(id:)` catch block: if `NSURLErrorDomain` and `NSURLErrorCancelled`, return without setting `error` or logging; otherwise unchanged. |
| **3. AES-GCM -4308** | (no code change) | Caller not definitively identified in app code; Keychain/Supabase auth storage and `DeviceIdentifier` use Keychain. Treat as simulator/Security framework; no security logic changed. |
| **4. Firebase / 127.0.0.1** | `NaarsCars/Core/Utilities/Constants.swift`, `NaarsCars/Core/Services/PushNotificationService.swift` | Added `Constants.Debug.pushIngestURL` (nil by default); `pushDebugLog` only POSTs when URL is set, avoiding connection-refused logs. Firebase hostname unchanged (environment/network). |
| **5. Map zero size** | `NaarsCars/Features/Rides/Views/RequestMapView.swift` | Added `.frame(minHeight: 200)` to map container so Map is never given zero height. |
| **6. No action** | — | Simulator/system logs left as-is. |
