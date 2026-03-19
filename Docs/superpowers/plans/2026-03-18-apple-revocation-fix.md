# Apple Token Revocation Fix — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Apple token revocation so both Delete Account and Unlink Apple flows correctly revoke Apple authorization, with shared logic, safety guards, and diagnosable logging.

**Architecture:** Extract a shared `revokeAppleAuthorization()` helper in AuthService that handles the Apple Sign-In sheet → Edge Function → Keychain cleanup cycle. Both `revokeAppleSignIn()` (delete path) and `unlinkAppleAccount()` (unlink path) call this shared helper before their respective backend operations. The Edge Function gets structured logging and PEM handling fixes. A new DB migration adds an auth-method guard to `unlink_apple_identity`.

**Tech Stack:** Swift/SwiftUI (iOS 17+), Supabase Edge Functions (Deno/TypeScript), PostgreSQL (Supabase)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `supabase/functions/revoke-apple-token/index.ts` | Rewrite | Structured logging, PEM fix, request_id, structured responses |
| `NaarsCars/Core/Services/AuthService+AppleSignIn.swift` | Modify (lines 344-531) | Shared helper, auth-method guard, remove redundant unlinkIdentity |
| `database/131_unlink_apple_identity_function.sql` | Create | Capture live function + add auth-method guard |

---

### Task 1: Rewrite Edge Function

**Files:**
- Modify: `supabase/functions/revoke-apple-token/index.ts`

- [ ] **Step 1: Rewrite with structured logging, PEM fix, request_id**

Key changes:
- Add `request_id` (crypto.randomUUID) logged at every step
- Fix PEM handling: replace literal `\\n` with real newlines
- Fix misleading DER comment (Web Crypto returns P1363, not DER)
- Structured JSON responses with `status` field
- Log each step: secrets_loaded, jwt_generated, token_exchange, revocation
- Sanitized Apple error bodies in logs

- [ ] **Step 2: Verify Edge Function syntax is valid**

Run: `deno check supabase/functions/revoke-apple-token/index.ts` (or visual review)

- [ ] **Step 3: Commit**

```
feat(auth): rewrite revoke-apple-token edge function with structured logging
```

**NOTE:** `verify_jwt: true` must be set during deployment via `supabase functions deploy revoke-apple-token --no-verify-jwt=false` or by updating the Supabase dashboard. This is a deploy-time config, not a code change.

---

### Task 2: Extract Shared Revocation Helper + Fix Unlink Flow

**Files:**
- Modify: `NaarsCars/Core/Services/AuthService+AppleSignIn.swift` (lines 344-531)

- [ ] **Step 1: Add `revokeAppleAuthorization()` shared helper**

Extract from `revokeAppleSignIn()`:
- Check Keychain for Apple user identifier
- Check credential state with Apple
- Obtain fresh auth code via Apple Sign-In sheet
- Call `revoke-apple-token` Edge Function
- Clear Keychain
- Does NOT touch Supabase identities or auth.users (callers handle that)

- [ ] **Step 2: Simplify `revokeAppleSignIn()` to use shared helper**

Replace body with: call `revokeAppleAuthorization()`, remove redundant `unlinkIdentity` block (delete_user_account RPC handles auth.users deletion).

- [ ] **Step 3: Rewrite `unlinkAppleAccount()` with guard + revocation**

Add:
1. Auth-method guard: check `session.user.identities` for non-Apple provider
2. Call `revokeAppleAuthorization()` before RPC
3. Then call `unlink_apple_identity` RPC
4. Refresh session, log success

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build`

- [ ] **Step 5: Commit**

```
feat(auth): shared Apple revocation helper, auth-method guard on unlink
```

---

### Task 3: Create DB Migration for unlink_apple_identity

**Files:**
- Create: `database/131_unlink_apple_identity_function.sql`

- [ ] **Step 1: Write migration with auth-method guard**

CREATE OR REPLACE the function with:
- auth.uid() verification (already in live DB)
- NEW: Guard that another identity exists before allowing unlink
- DELETE from auth.identities where provider = 'apple'
- GRANT to authenticated

- [ ] **Step 2: Commit**

```
feat(auth): add migration for unlink_apple_identity with auth-method guard
```
