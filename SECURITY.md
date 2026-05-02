# Naar's Cars Security Requirements

## Document Information
- **Type**: Security Requirements
- **Phase**: 0 (Must be completed alongside Foundation)
- **Last Updated**: January 2025
- **Status**: REQUIRED for all development phases

---

## 1. Overview

This document defines security requirements for the Naar's Cars iOS application. All developers MUST read and follow these requirements. Security is not optional and takes precedence over feature velocity.

### Security Principles

1. **Defense in Depth**: Multiple layers of protection (client + server)
2. **Least Privilege**: Users only access what they need
3. **Fail Secure**: Errors default to denying access
4. **Don't Trust the Client**: All security enforced server-side

---

## 2. Row Level Security (RLS) Policies

All Supabase tables MUST have RLS enabled. The following policies are REQUIRED before any production deployment.

### 2.1 profiles

The `profiles` table contains PII (`email`, `phone_number`, `is_admin`, `is_banned`, `ban_reason`, `banned_by`, `heard_about`, `join_reason`, `application_submitted_at`, `application_complete`, `notify_*`). Direct SELECT on `profiles` is restricted to **self and admin only**. All cross-user profile reads — messaging sender hydration, town-hall author lookup, user search, invite flows, profile cards — go through the **`public_profiles` view** instead, which exposes only non-PII columns (`id`, `name`, `avatar_url`, `car`, `approved`, `created_at`, `updated_at`).

This split was introduced by audit-CRIT-7 in `supabase/migrations/20260416_0002_security_profiles_projection_split.sql`. See [§2.1.1 The `public_profiles` view](#211-the-public_profiles-view) below for the design rationale.

| Policy Name | Operation | Roles | SQL Check |
|-------------|-----------|-------|-----------|
| `profiles_select_own` | SELECT | authenticated | `auth.uid() = id` |
| `profiles_select_admin` | SELECT | authenticated | `is_admin_user(auth.uid())` |
| `Users can insert own profile` | INSERT | (all) | `WITH CHECK (auth.uid() = id)` |
| `Users can update own profile` | UPDATE | (all) | `auth.uid() = id` |
| `profiles_update_own` | UPDATE | (all) | `auth.uid() = id` |
| `profiles_update_admin` | UPDATE | (all) | `is_admin_user(auth.uid())` |
| `profiles_admin_delete` | DELETE | authenticated | `approved = false AND <caller is admin>` |

```sql
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Self-read full row
CREATE POLICY "profiles_select_own"
ON public.profiles FOR SELECT TO authenticated
USING (auth.uid() = id);

-- Admin-read full row
CREATE POLICY "profiles_select_admin"
ON public.profiles FOR SELECT TO authenticated
USING (is_admin_user(auth.uid()));

-- Anyone can create their own profile during signup
CREATE POLICY "Users can insert own profile"
ON public.profiles FOR INSERT
WITH CHECK (auth.uid() = id);

-- Self and admin can update
CREATE POLICY "profiles_update_own"
ON public.profiles FOR UPDATE
USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_admin"
ON public.profiles FOR UPDATE
USING (is_admin_user(auth.uid())) WITH CHECK (is_admin_user(auth.uid()));

-- Admins can prune unapproved applications
CREATE POLICY "profiles_admin_delete"
ON public.profiles FOR DELETE TO authenticated
USING (
  approved = false
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.is_admin = true
  )
);
```

#### 2.1.1 The `public_profiles` view

```sql
CREATE OR REPLACE VIEW public.public_profiles
WITH (security_barrier = true, security_invoker = false) AS
SELECT id, name, avatar_url, car, approved, created_at, updated_at
FROM public.profiles;

REVOKE ALL  ON public.public_profiles FROM PUBLIC;
GRANT SELECT ON public.public_profiles TO authenticated, anon, service_role;
```

**Design decision: `security_invoker = false` is intentional.** The Supabase advisor `0010_security_definer_view` flags this view because it bypasses the underlying RLS on `profiles` and runs with the view-creator's (postgres) privileges. **This is the mechanism that makes the split work** — if the view ran as the invoker, the narrowed RLS on `profiles` (self + admin only) would block every cross-user profile lookup the app does (messaging, town hall, search, invites).

Realistic alternatives evaluated and rejected:

| Alternative | Why rejected |
|---|---|
| Convert to `security_invoker = true` + permissive RLS on `profiles` + column-level GRANTs | Would require self/admin to read PII through a separate SECURITY DEFINER RPC, weakens defense-in-depth (PII becomes column-grant-protected instead of network-unreachable on the base table), and column-level GRANT semantics are easy to misconfigure. |
| Convert to a SECURITY DEFINER RPC (`get_public_profiles(ids[])`) | Breaks every relationship-style join in `MessageService`, `ConversationService`, `TownHallService`, `TownHallCommentService`, `InviteService`, `ProfileService`, `UserSearchView`, `SupabaseService` (e.g. `sender:public_profiles!messages_from_id_fkey(id, name, avatar_url)`). PostgREST doesn't join RPCs. Trades one advisor warning for another. |

**The view stays as-is.** The advisor warning is a known accepted exception — record it as such, do not auto-remediate. If the underlying `profiles` schema changes (new PII columns), update the view's column list at the same time.

### 2.2 rides

| Policy Name | Operation | SQL Check |
|-------------|-----------|-----------|
| `rides_select_approved` | SELECT | User is approved |
| `rides_insert_own` | INSERT | `auth.uid() = user_id` |
| `rides_update_own_or_claimer` | UPDATE | `auth.uid() = user_id OR auth.uid() = claimed_by` |
| `rides_delete_own` | DELETE | `auth.uid() = user_id` |

```sql
ALTER TABLE public.rides ENABLE ROW LEVEL SECURITY;

-- Approved users can view all rides
CREATE POLICY "rides_select_approved" ON public.rides
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

-- Users can only create their own rides
CREATE POLICY "rides_insert_own" ON public.rides
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can update their own rides or rides they've claimed
CREATE POLICY "rides_update_own_or_claimer" ON public.rides
  FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = claimed_by);

-- Users can only delete their own rides
CREATE POLICY "rides_delete_own" ON public.rides
  FOR DELETE USING (auth.uid() = user_id);
```

### 2.3 favors

Same pattern as rides:

```sql
ALTER TABLE public.favors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "favors_select_approved" ON public.favors
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

CREATE POLICY "favors_insert_own" ON public.favors
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "favors_update_own_or_claimer" ON public.favors
  FOR UPDATE USING (auth.uid() = user_id OR auth.uid() = claimed_by);

CREATE POLICY "favors_delete_own" ON public.favors
  FOR DELETE USING (auth.uid() = user_id);
```

### 2.4 ride_participants

```sql
ALTER TABLE public.ride_participants ENABLE ROW LEVEL SECURITY;

-- Approved users can view participants
CREATE POLICY "ride_participants_select_approved" ON public.ride_participants
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

-- Only ride owner can add participants
CREATE POLICY "ride_participants_insert_owner" ON public.ride_participants
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.rides 
      WHERE id = ride_participants.ride_id 
      AND user_id = auth.uid()
    )
  );
```

### 2.5 favor_participants

```sql
ALTER TABLE public.favor_participants ENABLE ROW LEVEL SECURITY;

-- Approved users can view participants
CREATE POLICY "favor_participants_select_approved" ON public.favor_participants
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

-- Only favor owner can add participants
CREATE POLICY "favor_participants_insert_owner" ON public.favor_participants
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.favors 
      WHERE id = favor_participants.favor_id 
      AND user_id = auth.uid()
    )
  );
```

### 2.6 request_qa

```sql
ALTER TABLE public.request_qa ENABLE ROW LEVEL SECURITY;

-- Approved users can view Q&A
CREATE POLICY "request_qa_select_approved" ON public.request_qa
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

-- Approved users can ask questions
CREATE POLICY "request_qa_insert_approved" ON public.request_qa
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

-- Users can only delete their own questions/answers
CREATE POLICY "request_qa_delete_own" ON public.request_qa
  FOR DELETE USING (auth.uid() = created_by);
```

### 2.7 messages

| Policy Name | Operation | SQL Check |
|-------------|-----------|-----------|
| `messages_select_participant` | SELECT | User is participant in conversation |
| `messages_insert_participant` | INSERT | User is sender and participant |

```sql
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Users can only see messages in conversations they're part of
CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants 
      WHERE conversation_id = messages.conversation_id 
      AND user_id = auth.uid()
    )
  );

-- Users can only send messages as themselves in conversations they're in
CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = from_id
    AND EXISTS (
      SELECT 1 FROM public.conversation_participants 
      WHERE conversation_id = messages.conversation_id 
      AND user_id = auth.uid()
    )
  );
```

### 2.8 conversations

```sql
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Users can only see conversations they're part of
CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants 
      WHERE conversation_id = id 
      AND user_id = auth.uid()
    )
  );
```

### 2.9 conversation_participants

```sql
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

-- Helper function to check participation without RLS recursion
CREATE OR REPLACE FUNCTION public.is_conversation_participant(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id
  );
$$;

-- Users can see participants in their conversations
-- Uses SECURITY DEFINER function to avoid infinite recursion
CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT USING (
    -- User can see their own participation
    user_id = auth.uid()
    OR
    -- User can see other participants in conversations where they are a participant
    public.is_conversation_participant(conversation_participants.conversation_id, auth.uid())
  );

-- Users can add themselves or be added by conversation creator
CREATE POLICY "participants_insert_creator_or_self" ON public.conversation_participants
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_participants.conversation_id
      AND c.created_by = auth.uid()
    )
  );

-- Users can update their own participation
CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE USING (user_id = auth.uid());

-- Users can remove their own participation
CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE USING (user_id = auth.uid());
```

### 2.10 notifications

```sql
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Users can only see their own notifications
CREATE POLICY "notifications_select_own" ON public.notifications
  FOR SELECT USING (auth.uid() = user_id);

-- Users can only update (mark read) their own notifications
CREATE POLICY "notifications_update_own" ON public.notifications
  FOR UPDATE USING (auth.uid() = user_id);

-- System/admins can insert notifications for any user
CREATE POLICY "notifications_insert" ON public.notifications
  FOR INSERT WITH CHECK (true);
```

### 2.11 invite_codes

```sql
ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;

-- Users can see their own created codes
CREATE POLICY "invite_codes_select_own" ON public.invite_codes
  FOR SELECT USING (auth.uid() = created_by);

-- Approved users can create invite codes
CREATE POLICY "invite_codes_insert_approved" ON public.invite_codes
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

-- Allow code lookup during signup (before user is authenticated)
CREATE POLICY "invite_codes_select_for_validation" ON public.invite_codes
  FOR SELECT USING (used_by IS NULL);
```

### 2.12 push_tokens

```sql
ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only manage their own push tokens
CREATE POLICY "push_tokens_own" ON public.push_tokens
  FOR ALL USING (auth.uid() = user_id);
```

### 2.13 reviews

```sql
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

-- Approved users can view all reviews
CREATE POLICY "reviews_select_approved" ON public.reviews
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

-- Users can only create reviews as themselves
CREATE POLICY "reviews_insert_own" ON public.reviews
  FOR INSERT WITH CHECK (auth.uid() = reviewer_id);
```

### 2.14 town_hall_posts

```sql
ALTER TABLE public.town_hall_posts ENABLE ROW LEVEL SECURITY;

-- Approved users can view all posts
CREATE POLICY "town_hall_posts_select_approved" ON public.town_hall_posts
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND approved = true)
  );

-- Users can only create their own posts
CREATE POLICY "town_hall_posts_insert_own" ON public.town_hall_posts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can delete their own posts, admins can delete any
CREATE POLICY "town_hall_posts_delete_own_or_admin" ON public.town_hall_posts
  FOR DELETE USING (
    auth.uid() = user_id 
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
  );
```

### 2.15 Admin Operations

Any operation that requires admin privileges MUST verify via RLS:

```sql
-- Example: Only admins can update other users' approved status
CREATE POLICY "admin_approve_users" ON public.profiles
  FOR UPDATE USING (
    -- Either updating own profile OR is admin updating others
    auth.uid() = id 
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- Only admins can toggle admin status
-- IMPORTANT: This should be an Edge Function for additional safety
```

### 2.16 content_moderation_events (audit log)

Append-only audit log of moderation actions: which content (`message`, `town_hall_post`, `town_hall_comment`, `ride`, `favor`) was hidden / dismissed / restored / auto-hidden, by which admin, with what reason, linked to which report. Created by `supabase/migrations/20260403_0011_content_moderation_redesign.sql`. RLS enabled and a single admin-only SELECT policy added in `supabase/migrations/20260502_0001_enable_rls_content_moderation_events.sql` (audit ref: Supabase advisor `rls_disabled_in_public`).

| Policy Name | Operation | Roles | SQL Check |
|---|---|---|---|
| `moderation_events_select_admin` | SELECT | authenticated | `is_admin_user(auth.uid())` |

```sql
ALTER TABLE public.content_moderation_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "moderation_events_select_admin"
ON public.content_moderation_events FOR SELECT TO authenticated
USING (is_admin_user(auth.uid()));
```

**Insert path:** legitimate inserts come from SECURITY DEFINER RPCs in `20260403_0011` (e.g. `hide_content`, `dismiss_report`, `restore_content`, the auto-hide trigger). Those run as `postgres` (the table owner) and bypass RLS — RLS does not need an INSERT policy. Direct client INSERTs are denied by default.

**UPDATE/DELETE:** blocked by the `content_moderation_events_append_only` trigger from `20260403_0011`, which raises an exception. The trigger catches row-level mutations; RLS adds belt-and-braces denial.

**Pre-fix exposure (now closed):** before `20260502_0001` enabled RLS, anon/authenticated callers with the publishable anon key could `SELECT *` (see who hid what), and could `INSERT` arbitrary rows (planting fake `auto_hide` events into the audit trail).

---

## 3. Credential Management

### 3.1 Supabase Keys

The Supabase anon key is intentionally client-exposed (this is Supabase's design). Security comes from:
1. Row Level Security (RLS) policies
2. Server-side validation

**Requirement SEC-CRED-001**: Apply basic obfuscation to deter casual extraction:

```swift
// Secrets.swift - DO NOT COMMIT TO GIT
import Foundation

enum Secrets {
    // XOR-obfuscated values (not true encryption, but deters casual inspection)
    private static let key: [UInt8] = [0x4E, 0x61, 0x61, 0x72, 0x73] // "Naars"
    
    private static func deobfuscate(_ encoded: [UInt8]) -> String {
        let decoded = encoded.enumerated().map { index, byte in
            byte ^ key[index % key.count]
        }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }
    
    // Obfuscated URL bytes (generate with helper script)
    private static let urlBytes: [UInt8] = [/* generated bytes */]
    
    // Obfuscated anon key bytes (generate with helper script)
    private static let anonKeyBytes: [UInt8] = [/* generated bytes */]
    
    static var supabaseURL: String {
        deobfuscate(urlBytes)
    }
    
    static var supabaseAnonKey: String {
        deobfuscate(anonKeyBytes)
    }
}
```

**Important**: Obfuscation is NOT security. It deters casual inspection only. Real security comes from RLS policies.

### 3.2 Key Rotation

If the anon key needs rotation:
1. Generate new key in Supabase dashboard
2. Update obfuscated bytes in Secrets.swift
3. Release app update
4. Revoke old key after 30 days (allow update propagation)

### 3.3 What NOT to Store Client-Side

Never store in the iOS app:
- Supabase service role key
- Database connection strings
- Admin credentials
- API keys for third-party services (use Edge Functions instead)

---

## 4. Admin Authorization

### 4.1 Defense in Depth

Admin operations are protected at three layers:

| Layer | Purpose | Bypassed By |
|-------|---------|-------------|
| Client UI | UX convenience | Memory editing, direct navigation |
| Client verification | Defense in depth | Skilled attacker with modified client |
| Server RLS | Actual security | Nothing (if properly configured) |

### 4.2 AdminService Implementation

**Requirement SEC-ADMIN-001**: All admin operations MUST verify admin status server-side:

```swift
// Core/Services/AdminService.swift
@MainActor
final class AdminService {
    static let shared = AdminService()
    private let supabase = SupabaseService.shared.client
    
    /// Verify current user is admin before any admin operation
    private func verifyAdminStatus() async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw AppError.unauthorized
        }
        
        // Fresh check from server, not cached
        let response = try await supabase
            .from("profiles")
            .select("is_admin")
            .eq("id", userId.uuidString)
            .single()
            .execute()
        
        struct AdminCheck: Decodable {
            let isAdmin: Bool
            enum CodingKeys: String, CodingKey {
                case isAdmin = "is_admin"
            }
        }
        
        let check = try JSONDecoder().decode(AdminCheck.self, from: response.data)
        
        guard check.isAdmin else {
            Log.security("Non-admin attempted admin operation: \(userId)")
            throw AppError.unauthorized
        }
    }
    
    func approveUser(userId: UUID) async throws {
        try await verifyAdminStatus()
        // ... implementation
    }
    
    func setAdminStatus(userId: UUID, isAdmin: Bool) async throws {
        try await verifyAdminStatus()
        // ... implementation
    }
    
    func sendBroadcast(title: String, message: String, pinToNotifications: Bool) async throws {
        try await verifyAdminStatus()
        // ... implementation
    }
}
```

### 4.3 Security Logging

**Requirement SEC-ADMIN-002**: Log all admin operation attempts:

```swift
Log.security("Admin operation: \(operation) by \(userId) - \(success ? "SUCCESS" : "DENIED")")
```

Review logs for:
- Failed admin operations from non-admins (possible attack)
- Unusual patterns (many approvals in short time)

---

## 5. Rate Limiting

### 5.1 Client-Side Rate Limiting

**Requirement SEC-RATE-001**: Implement client-side rate limiting:

```swift
// Core/Utilities/RateLimiter.swift
actor RateLimiter {
    static let shared = RateLimiter()
    private var lastActionTime: [String: Date] = [:]
    
    func checkAndRecord(action: String, minimumInterval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastActionTime[action],
           now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        lastActionTime[action] = now
        return true
    }
}
```

### 5.2 Client-Side Limits

| Action | Minimum Interval | Rationale |
|--------|------------------|-----------|
| Claim/unclaim request | 5 seconds | Prevent toggle spam |
| Send message | 1 second | Prevent flood |
| Generate invite code | 10 seconds | Prevent mass generation |
| Refresh data (pull-to-refresh) | 2 seconds | Prevent API spam |
| Login attempt | 2 seconds | Prevent rapid retries |
| Invite code validation | 3 seconds | Prevent brute force |
| Password reset request | 30 seconds | Prevent enumeration |

### 5.3 Server-Side Rate Limiting

For production deployment, implement server-side rate limiting via Supabase Edge Functions or database triggers:

| Action | Limit | Window | Implementation |
|--------|-------|--------|----------------|
| Claim/unclaim | 3 | 1 minute | Database trigger |
| Messages | 10 | 1 minute | Edge Function |
| Invite validation | 5 | 1 hour | Edge Function with IP tracking |
| Login failures | 5 | 15 minutes | Supabase Auth config |
| Password reset | 3 | 1 hour | Edge Function |
| Invite generation | 5 | 24 hours | Database trigger |

### 5.4 Implementation Priority

1. **MVP**: Client-side rate limiting (required)
2. **Pre-launch**: Server-side for auth operations (strongly recommended)
3. **Post-launch**: Server-side for all operations (recommended)

---

## 6. Invite Code Security

### 6.1 Code Format

- Format: `NC` + 8 alphanumeric characters (uppercase)
- Character set: A-Z, 0-9 (excluding confusing: 0/O, 1/I/L)
- Effective set: 32 characters
- Combinations: 32^8 = ~1.1 trillion

```swift
enum InviteCodeGenerator {
    private static let characters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    
    static func generate() -> String {
        var code = "NC"
        for _ in 0..<8 {
            let randomIndex = Int.random(in: 0..<characters.count)
            code.append(characters[randomIndex])
        }
        return code
    }
}
```

### 6.2 Brute Force Protection

1. **Rate limiting**: 5 attempts per hour per device (see section 5)
2. **Uniform errors**: Don't reveal if code exists but is used
3. **Strong randomness**: Use cryptographic random generation

### 6.3 Error Messages

| Scenario | User-Facing Message |
|----------|---------------------|
| Code doesn't exist | "Invalid or expired invite code" |
| Code already used | "Invalid or expired invite code" |
| Rate limited | "Too many attempts. Please try again later." |

---

## 7. Push Token Security

### 7.1 Token Storage

- Tokens stored in `push_tokens` table
- RLS ensures users can only see/modify their own tokens
- `device_id` prevents token accumulation from same device

### 7.2 Token Cleanup

Server-side cleanup job (weekly):

```sql
-- Remove tokens older than 90 days
DELETE FROM push_tokens 
WHERE last_used_at < NOW() - INTERVAL '90 days'
   OR (last_used_at IS NULL AND created_at < NOW() - INTERVAL '90 days');
```

### 7.3 APNs Invalid Token Handling

When APNs returns 410 (Unregistered), immediately delete token:

```javascript
// In Edge Function sending push
if (apnsResponse.status === 410) {
    await supabase.from('push_tokens').delete().eq('token', token);
}
```

---

## 9. Security Logging

### 8.1 Log Categories

```swift
enum Log {
    static func security(_ message: String) {
        print("🔒 [SECURITY] \(message)")
        // In production: send to analytics/monitoring service
    }
}
```

### 8.2 Events to Log

| Event | Log Level | Example |
|-------|-----------|---------|
| Admin operation attempt | Security | "Admin operation: approve_user by UUID - SUCCESS/DENIED" |
| Rate limit triggered | Warning | "Rate limit: claim action by UUID" |
| Auth failure | Info | "Login failed for email@example.com" |
| Invite code attempt | Security | "Invite code attempt: NC•••••••• - INVALID" |
| Session expired | Info | "Session expired for UUID" |

---

## 10. Pre-Launch Security Checklist

### 9.1 RLS Policies

- [ ] All tables have RLS enabled
- [ ] All policies created per this document
- [ ] Tested: Non-owner cannot read private data
- [ ] Tested: Non-owner cannot modify others' data
- [ ] Tested: Non-admin cannot perform admin actions
- [ ] Tested: Unapproved user cannot access approved-only content

### 9.2 Client Security

- [ ] Credentials obfuscated in Secrets.swift
- [ ] Secrets.swift in .gitignore
- [ ] Rate limiter implemented
- [ ] AdminService verifies status server-side
- [ ] Security logging implemented

### 9.3 Server Security

- [ ] Server-side rate limiting for auth operations
- [ ] Push token cleanup scheduled
- [ ] APNs invalid token handling implemented

---

## 11. Incident Response

If a security issue is discovered:

1. **Assess severity**: Data exposed? Users affected?
2. **Contain**: Disable affected feature if necessary
3. **Notify**: Inform team immediately
4. **Fix**: Deploy patch ASAP
5. **Communicate**: Notify affected users if required
6. **Review**: Post-incident analysis

---

*End of Security Requirements*
