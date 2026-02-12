# Requests Module – Broken State Review Report

**Date:** February 6, 2025  
**Scope:** Post ride/favor, claim ride/favor, and related request workflows.  
**Intent:** Identify what is broken and clarify expected behavior before any fixes.  
**Updated:** After user feedback and Supabase RLS review.

---

## 1. Executive Summary

Review of the Requests module shows **several likely causes** for “unable to post rides or favors” and “claiming doesn’t work”:

- **Claim flow:** The claim confirmation sheet dismisses immediately when the user taps Confirm, without waiting for the claim API call. If the claim fails, the user never sees an error. This can make claiming appear broken even when the failure is network/backend.
- **Error visibility:** Create flows surface errors in the form; claim flows do not surface `ClaimViewModel.error` anywhere, so claim failures are silent.
- **Possible navigation timing:** After a successful create, navigation to the new ride/favor detail depends on setting a binding before the sheet dismisses; SwiftUI timing could occasionally prevent the push.
- **Data consistency (non-blocking):** SwiftData `participantIds` are never synced from the API, so “My Requests” for invited participants could be incomplete; poster/claimer are still covered by `userId`/`claimedBy`.

No code was changed; this document only reports findings and asks clarifying questions.

---

## 2. Workflows Traced

### 2.1 Post Ride / Post Favor

**Entry:** Requests tab → “+” → “Create Ride” or “Create Favor” → sheet (`CreateRideView` / `CreateFavorView`).

**Flow:**

1. User fills form and taps “Post”.
2. `CreateRideViewModel.createRide()` / `CreateFavorViewModel.createFavor()`:
   - Validates (pickup/destination or title/location, date, etc.).
   - Calls `RideService.createRide(...)` / `FavorService.createFavor(...)`.
   - Supabase: `.from("rides")` / `.from("favors")` → `.insert(rideData)` → `.select().single().execute()`.
   - Optionally adds participants via `ride_participants` / `favor_participants`.
3. On success: `onRideCreated?(ride.id)` / `onFavorCreated?(favor.id)` run **before** dismiss.
4. Parent `RequestsDashboardView` sets `navigateToRide = rideId` or `navigateToFavor = favorId`.
5. Success checkmark, short delay (`Constants.Timing.successDismissNanoseconds`), then `dismiss()`.
6. `navigationDestination(item: $navigateToRide)` / `$navigateToFavor` should push `RideDetailView(rideId:)` / `FavorDetailView(favorId:)`.

**Error handling (create):** If `createRide()` / `createFavor()` throws, `viewModel.error` is set and the create views show it in a `Section { Text(error) }` in the form. So create errors are visible as long as that section is on screen.

---

### 2.2 Claim Ride / Claim Favor

**Entry:** From Requests list → `RideDetailView(rideId:)` / `FavorDetailView(favorId:)` → “Claim” (or “Unclaim” if already claimed by me).

**Flow:**

1. User taps “Claim”.
2. `claimButtonSection` runs a `Task`:
   - `claimViewModel.checkCanClaim()` (checks profile has phone number).
   - If no phone → `showPhoneRequired = true` (PhoneRequiredSheet).
   - If can claim → `showClaimSheet = true`.
3. User sees `ClaimSheet` and taps “Confirm”.
4. **Current implementation (bug):**
   - `ClaimSheet` calls `onConfirm()` and **immediately** sets `showSuccess = true`.
   - `onConfirm` in the parent is:
     - `Task { do { try await claimViewModel.claim(...); await viewModel.loadRide(id:) } catch { } }`.
   - So the sheet does **not** wait for this `Task`; it dismisses right away.
5. `ClaimViewModel.claim()` runs asynchronously: rate limit check, phone check, then `ClaimService.claimRequest(...)` (Supabase update `status = "confirmed"`, `claimed_by = claimerId`).
6. On success, `viewModel.loadRide(id:)` / equivalent for favor runs and detail view refreshes. On failure, `claimViewModel.error` is set but **never shown** (see below).

**Error handling (claim):**  
`ClaimViewModel` sets `self.error` and rethrows. The detail views’ `onConfirm` only has `catch { // Error handled in viewModel }` and do **not** bind or display `claimViewModel.error` anywhere. So claim failures are invisible to the user.

---

### 2.3 Unclaim

Same pattern as claim: `UnclaimSheet` gets an `onConfirm` that runs a `Task` with `claimViewModel.unclaim(...)`. If the sheet dismisses without waiting for that Task, the same “no feedback on failure” issue applies (and `claimViewModel.error` is still not shown).

---

## 3. Root Causes Identified

### 3.1 Claim / Unclaim: Sheet Dismisses Before API Completes (High impact)

**Where:**  
`ClaimSheet.swift`: Confirm button calls `onConfirm()` then sets `showSuccess = true`.  
`onConfirm` in `RideDetailView` / `FavorDetailView` starts a `Task { try await claimViewModel.claim(...) }` but does not block the sheet.

**Effect:**  
- Sheet closes as soon as the user taps Confirm.  
- If the claim (or unclaim) fails (network, RLS, rate limit, etc.), the user sees no error and may think “claim doesn’t work.”  
- If the user expects to stay on the sheet until the request is claimed, the current behavior also feels broken.

**Expected behavior to confirm:**  
- Should the sheet stay open with a loading state until the claim (or unclaim) request finishes?  
- On failure, should an error message be shown in the sheet (or on the detail view) and the sheet remain open until the user dismisses or retries?

---

### 3.2 Claim / Unclaim: No UI for Errors (High impact)

**Where:**  
`RideDetailView`, `FavorDetailView`: neither view displays `claimViewModel.error`.  
`ClaimSheet` does not take the claim view model or an error message; it only has `onConfirm`.

**Effect:**  
Any claim/unclaim failure (auth, phone, rate limit, Supabase) is only logged or stored in `claimViewModel.error`, so the user has no feedback.

**Expected behavior to confirm:**  
- Should claim/unclaim errors be shown in the claim sheet, or on the detail view (e.g. banner/toast), or both?

---

### 3.3 Post: Navigation After Create (Medium impact – possible)

**Where:**  
`RequestsDashboardView`:  
- `.sheet(isPresented: $showCreateRide)` / `$showCreateFavor` with `CreateRideView` / `CreateFavorView`.  
- Callbacks set `navigateToRide` / `navigateToFavor` **before** `dismiss()`.  
- `.navigationDestination(item: $navigateToRide)` / `$navigateToFavor` push the detail view.

**Risk:**  
In SwiftUI, setting a `navigationDestination` item while a sheet is presented can sometimes not result in a push when the sheet is dismissed (timing/state). If that happens, the user would see the list again and might not see their new request or might think “post didn’t work” even though the insert succeeded.

**Expected behavior to confirm:**  
- After a successful post, should the user always be taken to the new ride/favor detail screen?  
- If sometimes they are not, is that a bug you want fixed?

---

### 3.4 SwiftData: `participantIds` Never Populated (Lower impact)

**Where:**  
- `RequestsDashboardViewModel.syncRidesToSwiftData` / `syncFavorsToSwiftData`: when inserting or updating `SDRide` / `SDFavor`, `participantIds` is never set (so it stays `[]`).  
- `DashboardSyncEngine.syncRides` / `syncFavors`: same; new/updated SwiftData models do not get `participantIds`.

**Effect:**  
- “My Requests” uses a predicate that includes `participantIds.contains(userId)` for the “mine” filter.  
- Poster and claimer are still included via `userId` and `claimedBy`, so **posting and claiming visibility** are not blocked.  
- Only “invited participants” (co-requestors) might be missing from “My Requests” in the dashboard until participant data is synced.

**Expected behavior to confirm:**  
- Should “My Requests” include requests where the user is only an invited participant (not poster/claimer)? If yes, we need to sync or derive `participantIds` (or equivalent) from the API.

---

### 3.5 Other Possible Causes (Backend / Config)

- **Supabase RLS:** Inserts on `rides`/`favors` or updates (claim) could be blocked by RLS. **Confirmed for claim — see §8.**  
- **Auth:** If the session is missing or invalid, create/claim would fail; with current UI, only create errors are visible.  
- **Network / Supabase URL/keys:** Wrong or empty URL/keys in `Secrets` would cause requests to fail; again, claim errors are not shown.  
- **Date decoding:** Create response is decoded with `DateDecoderFactory.makeSupabaseDecoder()`. If the DB returns dates in an unexpected format, decode could throw and the user would see the create error in the form.

---

## 7. User Feedback Summary (Answered)

1. **Post:** No errors when it fails; the Post button seems to do nothing (small touch animation, no request created). Expected: acceptance confirmation via navigation to the posted request details page.
2. **Claim:** User gets the claim pop-up, taps Yes, sees a green check, then the sheet disappears — but the request detail card does not update (still shows open). Expected: green check, then navigate back to request details with it showing as claimed and the option to message participants.
3. **Claim sheet:** User reports the sheet does stay open while it “processes” and shows success before closing, but nothing actually happens in the background to mark the request as claimed or assign the claimer. So the “success” is the **immediate** checkmark (see §3.1); the API is not succeeding (RLS blocks it — see §8).
4. **Supabase:** Significant recent changes to RLS and others; project files and Supabase MCP reflect latest state.

---

## 8. Supabase RLS: Claim Update Blocked (Root Cause)

Current RLS policies on `rides` and `favors` were queried via Supabase MCP. Both tables have RLS enabled and the following UPDATE policies:

**Rides:**

| Policy | Roles | USING (qual) | WITH CHECK |
|--------|--------|--------------|------------|
| Users can update own or claimed rides | public | `auth.uid() = user_id OR auth.uid() = claimed_by` | same |
| Users can update their own rides | authenticated | `user_id = auth.uid()` | `user_id = auth.uid()` |

**Favors:** Same structure (own or claimed / their own).

**Why claiming fails:**  
When a **claimer** (not the poster) tries to update a row to set `claimed_by = auth.uid()` and `status = 'confirmed'`:

- The row currently has `user_id = poster_id` and `claimed_by = NULL`.
- **USING:** For the update to be allowed, the row must satisfy `auth.uid() = user_id OR auth.uid() = claimed_by`. The claimer is not the poster (`auth.uid() ≠ user_id`) and `claimed_by` is NULL, so `auth.uid() = claimed_by` is false. **No policy allows the claimer to “see” the row for update.**
- Result: the Supabase UPDATE returns 0 rows (or an RLS violation); the claim never persists. The app’s success checkmark is shown immediately in the UI, so the user sees success even though the server rejected the update.

**Recommended RLS change (for implementation plan):**  
Add a policy that allows an authenticated (or approved) user to UPDATE a ride/favor **only when** `claimed_by IS NULL`, and restrict the updated columns or values so the only change is setting `claimed_by = auth.uid()` and `status = 'confirmed'` (e.g. a dedicated “claim” policy or a USING that allows `claimed_by IS NULL` with a WITH CHECK that `claimed_by = auth.uid()` after update). Same idea for unclaim (allow poster or current claimer to set `claimed_by = NULL`, `status = 'open'`).

**Post (insert):**  
INSERT policies are “Users can create rides” / “Users can create favors” with `with_check: (user_id = auth.uid())`. So inserts should succeed for authenticated users whose JWT `auth.uid()` matches the app’s `currentUserId`. If post still “does nothing,” possible causes: (1) create error is set but the error `Section` is at the bottom of the form and the user doesn’t scroll; (2) session/auth mismatch; (3) response decode failure after insert. Making create errors more visible (e.g. alert or at top of form) is recommended so any insert failure is seen.

---

## 4. Clarifying Questions for You

*(Answered in §7; kept for reference.)* To align fixes with product intent, it would help to have your expectations on the following:

### Post ride / favor

1. When post **succeeds**, should the user always be navigated to the new ride/favor detail screen, or is it acceptable to sometimes stay on the list?
2. When post **fails**, do you currently see an error message in the create form, or does the sheet close with no message, or something else?
3. Are you testing against a real Supabase project with RLS enabled? Any chance inserts are blocked (e.g. missing policy for authenticated users)?

### Claim / unclaim

4. When you say “claiming doesn’t work,” what exactly happens?  
   - Do you see the claim confirmation sheet, tap Confirm, and then the sheet closes but the request still shows as unclaimed?  
   - Or do you never see the claim sheet (e.g. always the “phone required” sheet)?  
   - Or does the app crash or hang?
5. Should the claim (and unclaim) sheet stay open and show a loading state until the API call completes, and only then dismiss on success (and show an error and stay open on failure)?
6. Where do you want claim/unclaim errors to appear: inside the claim sheet, as a toast/banner on the detail view, or both?

### General

7. Have you recently changed Supabase URL, anon key, or RLS policies?  
8. For “unable to post,” do you see any error text in the create form, or does the sheet simply close with no visible error?

---

## 5. File Reference (No Changes Made)

| Area | Files |
|------|--------|
| Requests dashboard | `NaarsCars/Features/Requests/Views/RequestsDashboardView.swift`, `ViewModels/RequestsDashboardViewModel.swift` |
| Create ride/favor | `NaarsCars/Features/Rides/Views/CreateRideView.swift`, `ViewModels/CreateRideViewModel.swift`, `NaarsCars/Features/Favors/Views/CreateFavorView.swift`, `ViewModels/CreateFavorViewModel.swift` |
| Detail & claim | `NaarsCars/Features/Rides/Views/RideDetailView.swift`, `NaarsCars/Features/Favors/Views/FavorDetailView.swift`, `NaarsCars/Features/Claiming/Views/ClaimSheet.swift`, `ViewModels/ClaimViewModel.swift` |
| Services | `NaarsCars/Core/Services/RideService.swift`, `FavorService.swift`, `ClaimService.swift` |
| SwiftData sync | `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift` (syncRidesToSwiftData, syncFavorsToSwiftData), `NaarsCars/Core/Storage/DashboardSyncEngine.swift` |
| Models | `NaarsCars/Core/Models/Ride.swift`, `Favor.swift`, `NaarsCars/Core/Storage/SDModels.swift` (SDRide, SDFavor) |

---

## 6. Summary Table

| Issue | Severity | Likely user-visible effect |
|-------|----------|----------------------------|
| **RLS blocks claim UPDATE** | **Critical** | Claim API fails; row not updated; detail still shows open. User sees green check then sheet closes with no actual claim. |
| Claim sheet shows success without waiting for API | **High** | Green check and dismiss are UI-only; server may have rejected (e.g. RLS). |
| Claim/unclaim errors never shown | **High** | User has no way to know why claim doesn't work. |
| Post "does nothing" / no errors visible | **High** | Create error may be set but only in a Section at bottom of form; user doesn't scroll so sees nothing. |
| Navigation to detail after create might not push | **Medium** | User might not see the new request detail after posting. |
| SwiftData `participantIds` not synced | **Low** | "My Requests" might miss some invited-participant requests. |

**Next step:** Implement fixes: (1) RLS policy allowing claimer to UPDATE when `claimed_by IS NULL`; (2) claim sheet waits for API and shows success only after server confirms, with errors shown on failure; (3) make create errors prominent (e.g. alert or top of form) so post failures are visible; (4) ensure navigation to new request detail after successful post.

---

**Report status:** Research complete. Ready for an implementation plan (no code changes made in this phase).
