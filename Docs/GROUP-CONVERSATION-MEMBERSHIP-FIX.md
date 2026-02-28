# Group conversation membership fix — root cause and fix plan

**Status:** Root cause identified and fixes implemented. Migration applied to Supabase via MCP.

## Summary

- **Remove doesn’t stick:** The app was doing a direct `UPDATE` on `conversation_participants`. RLS allows UPDATE only on the current user’s row (`user_id = auth.uid()`), so updating another user’s `left_at` affected 0 rows. **Fix:** Call the existing SECURITY DEFINER RPC `remove_conversation_participant` instead.
- **Leave then send still works:** Client and server treated “has any row” in `conversation_participants` as “is participant,” not “has row with `left_at IS NULL`.” **Fix:** Client checks and messages INSERT policy now require active participation (`left_at IS NULL`); optional creator path allows conversation creator to send when they have no participant row.

---

## 1. Data sources (where participants are stored and rendered)

| What | Source | Location |
|------|--------|----------|
| **Participants list (ConversationDetailView)** | `ConversationParticipantsViewModel.loadParticipants()` | `ConversationDetailView.swift` (ConversationParticipantsViewModel) |
| **Participants list (MessageDetailsPopup)** | Local state `participants` initialized from `participantsViewModel.participants`; refetched via `loadParticipants()` (direct Supabase query) | `MessageDetailsPopup.swift` |
| **Authoritative store** | Table `conversation_participants` (columns `conversation_id`, `user_id`, `left_at`). Active = `left_at IS NULL`. | Supabase |
| **Local cache** | SwiftData `SDConversation.participantIds`; updated in `ConversationParticipantsViewModel.loadParticipants()` and `MessagingRepository.syncConversations()` | `SDModels.swift`, `MessagingRepository.swift` |
| **Message send auth** | `MessageService.sendMessage()` does a Supabase select on `conversation_participants` (no `left_at` filter); then inserts into `messages`. | `MessageService.swift` |
| **System messages (add/remove/leave)** | `ConversationParticipantService.sendSystemMessage()` inserts into `messages` with `message_type: "system"`. | `ConversationParticipantService.swift` |

- **Participants fetch**: `ConversationDetailView` and `MessageDetailsPopup` both query `conversation_participants` with `.is("left_at", value: nil)` (active only). `ConversationParticipantsViewModel` also preloads from SwiftData then overwrites with the same Supabase result and writes back to SwiftData.
- **Realtime**: No subscription found that pushes participant list changes; participants are read on demand.

---

## 2. Remove-participant flow (why it doesn’t stick)

**Flow:**  
`MessageDetailsPopup` → `removeParticipant(userId)` → `ConversationParticipantService.removeParticipantFromConversation()` → **direct Supabase UPDATE** on `conversation_participants` (set `left_at` for the **target** user) → then system message and local `participants.removeAll { $0.id == userId }`.

**Root cause:**  
RLS on `conversation_participants` allows **UPDATE only on the current user’s row** (`user_id = auth.uid()`). Removing another user means updating **that** user’s row (`user_id = target`), which RLS forbids. The UPDATE therefore affects **0 rows**. Supabase returns success; the client does not check row count, so it:

1. Shows success and removes the user from local state.
2. Creates the system message (remover is still a participant, so insert succeeds).
3. On next open, `loadParticipants()` refetches from DB and gets the unchanged list (target still has `left_at = NULL`), so the removed user reappears.

**Evidence:**  
- `ConversationParticipantService.removeParticipantFromConversation()` uses direct table update (lines 305–310).  
- RLS: `pg_policies` for `conversation_participants` UPDATE shows `qual` and `with_check` both `(user_id = auth.uid())`.  
- The DB already provides a **SECURITY DEFINER** RPC `remove_conversation_participant(p_conversation_id, p_user_id, p_removed_by)` that correctly sets `left_at`; the app does **not** call it.

---

## 3. Leave-conversation flow (why send still works after leave)

**Leave:**  
`MessageDetailsPopup.leaveConversation()` → `ConversationParticipantService.leaveConversation()` → direct UPDATE on **own** row (`user_id = auth.uid()`). RLS allows this, so `left_at` is set and leave **does** persist.

**Send after leave:**  
- **Client:** `MessageService.sendMessage()` checks membership with a select on `conversation_participants` **without** `.is("left_at", value: nil)`. The user still has a row (with `left_at` set), so `participantCheck?.data.isEmpty == false` and the client allows send.  
- **Server:** Messages INSERT policy is  
  `EXISTS (SELECT 1 FROM conversation_participants WHERE conversation_id = ... AND user_id = auth.uid())`  
  with **no** `left_at IS NULL` condition, so the backend also allows insert.

So both client and server treat “has any row” as “is participant,” not “has active row (`left_at IS NULL`).”

**Evidence:**  
- `MessageService.sendMessage()` (lines 385–391): no `left_at` filter.  
- `MessageService.hasRemoteConversationMembership()` (lines 56–62): same.  
- Supabase `messages` INSERT policy: only checks existence in `conversation_participants`, not `left_at`.

---

## 4. Add participant (why it works)

Add uses **INSERT** into `conversation_participants`. RLS `authenticated_users_can_add_participants` allows insert when `user_id = auth.uid()` or creator; for adding others the creator case applies. New rows have `left_at = NULL`, so they appear in all “active only” queries. No mismatch.

---

## 5. Recommended fix plan (minimal risk first)

### (a) Fix remove: use RPC instead of direct UPDATE  
**Risk: low.**  
- **File:** `NaarsCars/Core/Services/ConversationParticipantService.swift`  
- **Change:** In `removeParticipantFromConversation`, call the existing RPC `remove_conversation_participant(conversationId, userId, removedBy)` instead of direct UPDATE.  
- **Effect:** DB write will succeed; participants list and SwiftData will correct on next load/refetch.

### (b) Fix leave (optional consistency)  
**Risk: low.**  
- **File:** `ConversationParticipantService.swift`  
- **Change:** In `leaveConversation`, call RPC `leave_conversation(conversationId, userId)` instead of direct UPDATE.  
- **Effect:** Same behavior with one code path; RPC is already SECURITY DEFINER and correct.

### (c) Fix send-after-leave: client + server  
**Risk: low.**  
- **Client:** `MessageService.sendMessage()` and `hasRemoteConversationMembership()`: add `.is("left_at", value: nil)` to the `conversation_participants` select so only active participants can send.  
- **Server:** New migration: update **messages** INSERT (and SELECT if desired) policy so the `conversation_participants` EXISTS subquery requires `AND left_at IS NULL`.  
- **Effect:** After leave, client will get no active row and deny send; server will deny insert if client is bypassed.

### (d) Client refresh after remove  
**Risk: low.**  
- **File:** `MessageDetailsPopup.swift`  
- **Change:** After a successful remove, call `await loadParticipants()` so the popup’s list is from the server; optionally post `NotificationCenter.default.post(name: .conversationUpdated, object: conversationId)` so the parent refetches (e.g. `participantsViewModel.loadParticipants()` on next appear).  
- **Effect:** UI stays in sync with DB even before sheet close.

### (e) DEBUG instrumentation  
**Risk: none (DEBUG only).**  
- Log exact payloads and Supabase responses/errors for remove/leave/add.  
- After each action, refetch participants from Supabase and log the returned list and current user’s membership (e.g. `left_at`).  
- Log realtime participant events if/when a subscription is added.

---

## 6. Database and policies audit (summary)

- **Canonical membership:** `conversation_participants`; active = `left_at IS NULL`.  
- **RPCs:** `leave_conversation`, `remove_conversation_participant` exist and are SECURITY DEFINER; app currently does not use them for leave/remove.  
- **RLS:**  
  - **conversation_participants UPDATE:** only own row (`user_id = auth.uid()`) → prevents “remove other” via direct UPDATE.  
  - **messages INSERT:** allows if user has **any** row in `conversation_participants` for that conversation → should require `left_at IS NULL`.  
- **is_conversation_participant:** Returns true if **any** row exists (no `left_at` check). Used in conversation_participants SELECT; messages policies use a direct EXISTS, so fixing the EXISTS in messages is enough; we can optionally add an `is_active_conversation_participant` helper later.

---

## 7. Files to change (exact)

| File | Change |
|------|--------|
| `NaarsCars/Core/Services/ConversationParticipantService.swift` | Use RPC `remove_conversation_participant` for remove; optionally use RPC `leave_conversation` for leave. Add DEBUG logs (payload, response, refetch result). |
| `NaarsCars/Core/Services/MessageService.swift` | In `sendMessage()` and `hasRemoteConversationMembership()`, add `.is("left_at", value: nil)` to the `conversation_participants` select. Add DEBUG log after membership check. |
| `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift` | After successful remove, call `await loadParticipants()` and post `.conversationUpdated`. Add DEBUG logs for remove/leave/add and refetch. |
| `database/110_messages_insert_active_participant_only.sql` and `supabase/migrations/20260218_0001_messages_insert_active_participant_only.sql` | Replace messages INSERT policy so the EXISTS on `conversation_participants` includes `AND left_at IS NULL`; allow conversation creator via separate EXISTS on `conversations.created_by`. **Applied to Supabase.** |

All of (a)–(e) have been implemented. Remove now persists, send-after-leave is blocked (client + server), and the popup refetches participants after remove and notifies the parent.
