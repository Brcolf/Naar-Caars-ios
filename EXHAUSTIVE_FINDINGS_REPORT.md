## Exhaustive Findings Report

### Workspace & Build Context (Discovered)
- Repo root: `/Users/bcolf/.cursor/worktrees/naars-cars-ios/bwt`
- `git status -sb`: `## HEAD (no branch)` with `package-lock.json` modified
- `git log -1`: `3deb6ebeb1f054b89e77f46401922481037c91d3` “Final cleanup of project root build files”
- Required local secrets/configs missing: `NaarsCars/Core/Utilities/Secrets.swift` (gitignored); no `.env` or `.xcconfig` files found.
- Clean build attempt failed due to CoreSimulator connection invalid and sandbox write restrictions to `DerivedData/SourcePackages`.
- Simulator (iPhone 15) + physical device (iPhone 17 Pro) runs are not verified.

---

### 1) Blocker — Messaging cache API mismatch (likely build failure)
- **Location:** `NaarsCars/Core/Services/MessageService.swift`
- **Steps to Repro:** Build app target.
- **Expected:** `CacheManager` exposes conversation/message cache APIs used by `MessageService`.
- **Actual:** `CacheManager` defines only profiles/rides/favors/notifications/town hall caches; message/conversation cache APIs are missing.
- **Root Cause Hypothesis:** Cache APIs removed/renamed without updating `MessageService` (or missing file).
- **Fix Recommendation:** Add message/conversation cache APIs to `CacheManager` or remove cache references in favor of SwiftData.
- **Test Coverage Gap:** No unit tests ensuring `CacheManager` API parity.

### 2) High — Requests list shows “Unknown User” after refresh (missing poster/claimer)
- **Location:** `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`
- **Steps to Repro:** Open Requests tab, pull to refresh.
- **Expected:** Poster/claimer names and avatars show.
- **Actual:** Cards often show “Unknown User”.
- **Root Cause Hypothesis:** SwiftData conversion drops `poster`/`claimer` fields entirely; only IDs are stored.
- **Fix Recommendation:** Persist poster/claimer data in SwiftData or hydrate profiles in view model.
- **Test Coverage Gap:** No UI test validating request cards show user names after refresh.

### 3) High — Message history missing (pagination blocked by cache)
- **Location:** `NaarsCars/Core/Services/MessageService.swift`, `NaarsCars/Core/Storage/MessagingRepository.swift`
- **Steps to Repro:** Open a long conversation; scroll up to load older messages.
- **Expected:** Older messages load in pages.
- **Actual:** History stops after cached slice (last 25).
- **Root Cause Hypothesis:** `fetchMessages` returns cached messages even when `beforeMessageId` is provided; repository sync only fetches last 25.
- **Fix Recommendation:** Bypass cache for pagination, add timestamp-based incremental fetch, and persist full history in SwiftData.
- **Test Coverage Gap:** No pagination tests for message history.

### 4) High — Message notifications not clearing reliably (group chats)
- **Location:** `NaarsCars/Core/Services/MessageService.swift`, `ConversationDetailViewModel`
- **Steps to Repro:** Open group chat “Test Unique”, read messages, return to list/bell.
- **Expected:** Unread counts and notifications clear.
- **Actual:** Badge/notification may persist.
- **Root Cause Hypothesis:** Per-message updates are slow and errors are swallowed; batch RPC exists (`mark_messages_read_batch`) but is unused.
- **Fix Recommendation:** Use batch RPC for read marking; surface errors when read marking fails.
- **Test Coverage Gap:** No tests covering group chat read/unread transitions.

### 5) High — Edit Profile can clear avatar + possible RLS failure
- **Location:** `NaarsCars/Features/Profile/ViewModels/EditProfileViewModel.swift`, `NaarsCars/Core/Services/ProfileService.swift`
- **Steps to Repro:** Edit profile without selecting a new avatar image.
- **Expected:** Existing avatar remains unchanged.
- **Actual:** Avatar may be cleared; users report RLS save errors.
- **Root Cause Hypothesis:** Update payload includes `avatarUrl: nil`, which clears `avatar_url`; RLS policy may block updates for non-admin users.
- **Fix Recommendation:** Only include `avatarUrl` when a new image is uploaded; verify profile update RLS.
- **Test Coverage Gap:** No tests for “edit without new avatar” or RLS update permissions.

### 6) Medium — Apple Maps open uses name instead of full address (missing house number)
- **Location:** `NaarsCars/UI/Components/Inputs/LocationAutocompleteField.swift`
- **Steps to Repro:** Select autocomplete address, open in Apple Maps.
- **Expected:** Full address with house number.
- **Actual:** Approximate location (name/POI only).
- **Root Cause Hypothesis:** Field stores `details.name` instead of `details.address`.
- **Fix Recommendation:** Store full address for ride/favor pickup/destination; display name separately if needed.
- **Test Coverage Gap:** No integration tests for Apple Maps deep link with full address.

### 7) Medium — Conversations list may include conversations the user left
- **Location:** `NaarsCars/Core/Services/MessageService.swift`
- **Steps to Repro:** Leave a conversation, return to list.
- **Expected:** Left conversation removed or archived.
- **Actual:** Conversation may still appear.
- **Root Cause Hypothesis:** Initial participant query ignores `left_at IS NULL`.
- **Fix Recommendation:** Filter `conversation_participants` by active status (`left_at IS NULL`).
- **Test Coverage Gap:** No tests for leave-conversation list behavior.

### 8) Medium — Performance risk: Requests realtime triggers full reload
- **Location:** `NaarsCars/Features/Requests/ViewModels/RequestsDashboardViewModel.swift`
- **Steps to Repro:** Frequent ride/favor realtime updates.
- **Expected:** Incremental updates.
- **Actual:** Full network reload per event.
- **Root Cause Hypothesis:** Realtime handlers call `loadRequests()` on every insert/update/delete.
- **Fix Recommendation:** Upsert from realtime payloads instead of full fetch.
- **Test Coverage Gap:** No perf tests for realtime update storms.

### 9) Medium — Security/Privacy: conversation_participants assumes RLS disabled
- **Location:** `NaarsCars/Core/Services/MessageService.swift`
- **Risk:** If RLS is disabled, user membership data is exposed to all authenticated users.
- **Fix Recommendation:** Enforce RLS on `conversation_participants` and use authorized queries/RPCs.
- **Test Coverage Gap:** No security tests for conversation membership visibility.

---

### Build/Run/Device Testing Status
- Build: Not verified (sandbox permission and CoreSimulator errors).
- Simulator: Not verified.
- Physical device: Not verified.
- QA scripts: Not executed.


