# Multi-community: owner decisions, 2026-10-17

> These decisions were taken by the owner on 2026-10-17 and govern the build. Where this file and [`2026-10-07-multi-community-design.md`](2026-10-07-multi-community-design.md) differ, this file wins. Every decision the spec lists that is not mentioned here takes the spec's recommendation.

## Build scope and mechanics

1. **Scope: Phases 0, 1, 2 and 3** of the spec. Phases 4 and 5 are not part of this build.
2. **Production.** Each Phase 0 migration file is first dry-run inside one rolled-back transaction against the live project together with its probes, then applied through the Supabase MCP one function or policy per call, with the short probe (insert, claim, complete, review, delete a probe account) after every step. The rollout stops at the first failed probe. **Step 4 (the account-lifecycle functions) is an owner step in the SQL editor**; the build pauses there and resumes on the owner's word.
3. **New Swift files** are added through the Xcode MCP file tools with **this worktree's** project open (`.claude/worktrees/naarscars-multi-community-roadmap-f08594/NaarsCars/NaarsCars.xcodeproj`). An agent must confirm the open workspace path before writing; if another project is open it writes the file to disk, records it in the task's result as "not yet in the project", and does not claim a green build.
4. **Publishing.** The branch is pushed to the public repository without the research maps (kept locally). A draft pull request is opened once the first Swift change lands, so CI runs.
5. **Verification lane.** Lane B (headless `xcodebuild`, one simulator, Xcode closed or idle) for builds, unit tests and screenshots. One build at a time on this Mac.

## Product decisions (spec ids)

| Spec id | Decision |
|---|---|
| D2 | **(b)** Per-community membership approval with open account creation. Creating a community makes the creator active at once. |
| D6 | **(a)** Requests is one merged feed with a community chip per card and an optional narrow in the title menu; chips hidden with one membership. Town Hall and the leaderboard switch per community. |
| D7 | **(a)** Guests see public communities only; the default community is public at back-fill; only platform admins can flag a community public. |
| D8 | **(a)** Messaging reach is "shares a community with you", creator-relative; group threads may bridge communities; threads survive leaving and removal. |
| D16 | **(a)** Public storage buckets are accepted for now; private buckets and signed URLs are Phase 5. |
| D28 | **(a)** The additive `total` key in `get_badge_counts` ships in Phase 0 as its own revertable call and is checked on a device. |
| D1, D18 | The default community is "Naar's Cars Seattle"; its owner is the project owner's account; the other platform admins are `admin`. The word is "community". |

## Amendments to the spec

### A1. Creation limits and a limit-raise request (replaces the numbers in D14 and D25)

- `create_community` allows **1 community per account per day** and **3 owned communities per account** by default. The owned limit is a server-owned column `profiles.max_owned_communities integer not null default 3` (added to the guarded set in `protect_admin_fields`; never client-writable).
- A member who is at their owned limit can **request a higher limit**: `request_owned_community_limit(p_requested integer, p_reason text) → {request_id}` writes a row to a new table `community_limit_requests (id, user_id, requested_max, reason, status pending|approved|declined, decided_by, decided_at, created_at)`, one open request per user, requested value between 4 and 20, reason required. Platform admins get an `announcement` bell row ("<name> asks to own up to N communities"), the same mechanism the spec uses for the new-community notice (no push, no new notification type).
- A platform admin decides with `decide_owned_community_limit(p_request_id, p_approve boolean)`: approval sets `profiles.max_owned_communities = requested_max` and tells the requester with an `announcement` row; a decline tells them too. The platform Communities list (Phase 2) shows open requests with approve and decline.
- Client (Phase 2): when Create is refused for the limit, `MyCommunitiesView` offers "Request a higher limit" (requested number and reason); the request's status shows on that screen until decided.
- Member invite codes stay single-use with a 7-day expiry; admin codes are multi-use with a required expiry, as the spec says.

### A2. Reporting a community that is public (extends F20 and rule 10)

- Any signed-in account can report a community it can see: one it belongs to, one it holds a valid invite code for (the preview sheet), or **any public community** (from the public community's preview and from its Town Hall header when the viewer is not a member). Guests tapping Report get the existing sign-in prompt (`GuestRestrictionReason`, the report case).
- `report_community` therefore accepts a community the caller can read under the `communities` SELECT policy (public, member, admin, or applicant) **or** a valid code; it writes a report with `reported_community_id`, routed to platform admins only. The existing `report_type` vocabulary is used; the description is free text.
- A report about a public community that violates the guidelines is handled by a platform admin from the Communities list: archive, or flag it private (`is_public = false`), both already platform-admin actions in the spec.
- The community guidelines (the seventh section added in Phase 2) say that a community's name, description and public content are subject to the same rules as any post.

### A3. Deleting the account of a community's only owner (replaces D23 and rule 14)

- Communities where the deleting user is the only owner **and another active admin exists** are handed to the longest-standing admin; members get the announcement row and the new owner a push, as the spec says.
- Communities where the deleting user is the only owner **and no other admin exists** are **archived as part of the deletion**. All members lose access; each gets an `announcement` row "<community> was closed because its owner's account was deleted". In-flight claims in it are cancelled with notice, as for any archive.
- The client's delete-account flow shows, before the final confirmation, a warning that names those communities and says every member will lose access, and requires an explicit confirmation. **The server does not depend on that confirmation:** `delete_user_account` always applies the rules above, because account deletion must succeed from every state (App Store 5.1.1(v)).
- There is no ownerless state, no `owner_vacant_since`, no `claim_community_ownership` and no F21. `leave_community` is unchanged from the spec: the last owner must transfer ownership or promote an admin first, unless they are the only member, in which case leaving archives the community.
- **The default community (A3 + INV-L1, confirmed 2026-10-18 when the owner applied `20261017_0004`):** Seattle is never archived while a member remains. When its only owner deletes their account and no other admin exists, its longest-standing active member (platform admins first) becomes owner; only with nobody left at all is it archived.

### A4. Sequencing relative to the Android initiative

Communities are built first (roadmap ordering A). The harness phases are not part of this build; the existing rolled-back-probe discipline from the 2026-10 migrations is used instead, plus a committed probe script (`supabase/probes/communities_probe.sql`).

### A5. Scope extended to Phases 4 and 5 (owner decision, 2026-10-19)

With Phases 0-3 built, gated and pushed (`a4e56d4`), the owner extended the build to the spec's Phases 4 and 5 on the same branch and draft PR, Phase 4 first. Three decisions shape it:

1. **Universal Links are built in full in Phase 4**: the client code (`onOpenURL` → `DeepLinkParser` → `.joinCommunity(code)` → the join sheet; signed out → `PendingInviteStore` and the Welcome banner) and the `com.apple.developer.associated-domains` entitlement `applinks:naarscars.com`. The owner enables the Associated Domains capability on the App ID (team `WT4DGUYKL4`, bundle `com.NaarsCars`) and hosts the `apple-app-site-association` file at `https://naarscars.com/.well-known/` **before the next archive**, since an entitlement the provisioning profile lacks fails the archive; the Phase 4 plan gives the exact file and steps. Simulator verification needs neither.
2. **Phase 5 is split.** *5a, built now:* delete the dead invite UI and the superseded screens with their project references (through the Xcode MCP file tools, not by hand), stop writing `heard_about` / `join_reason` to `profiles` for new rows, add a definer geocoding lookup and move the client to it, move the client to signed storage URLs (they work while the buckets are still public). *5b, gated:* the legacy bridges, the `fill_request_community` fallback and `is_default` dependence, the `admin_reject_pending_user` revoke, the `invite_codes` drop, the `geocoding_cache` SELECT revoke and the bucket flip to private are written, dry-run and probed, with headers **NOT APPLIED until the owner confirms from App Store Connect that no pre-community build remains in use**. The same gate applies to any Phase 4 server change that would alter what the installed build receives (the `membership_update` producers and the real `broadcast` push): registry entries ship now, producers are gated.
3. **Order:** Phase 4, then 5a, each with its own plan, workflow, gate and push, on this branch; PR #6 remains the single review unit.

The owner's standing instruction on SQL (apply from the orchestrator session, one call per block, dry run and probes first) continues to apply to Phase 4 and 5a; 5b's apply waits for the gate in point 2.

### A6. Answers to the Phase 4 and 5 plan questions (owner, 2026-10-19)

1. **Voice notes are included in Phase 5**: the `audio-messages` bucket joins the four image buckets in 5a (signed audio URLs, prefetch through a narrow protocol rather than a direct `MessagingSyncEngine` → `MessageAudioPlayer` call) and in 5b's bucket flip (File E block 4 runs).
2. **The 5b NOT APPLIED files are pushed with 5a** on the same branch: the gaps they close are already described in the pushed spec (D16, section 3.8) and the files add remediation, not exposure.
3. **The first App Store build with communities waits for 5a**, so Files D and E of Phase 5 gate only on the pre-community build aging out.

Planner choices accepted as written, with the owner's standing delegation: the onboarding "Try again" button is relabelled rather than removed (Phase 4 Task 10 d); the community time zone is both the create-form default and the forms' default (Tasks 8 and 9); "All communities" for announcements stays deferred (SQL plan D-S9); the edge functions are not redeployed in Phase 4 (D-S4); only the bare `naarscars.com` hosts `/join`; `delete_user_account`'s successor notice keeps the type `announcement` (D-S3) and moves with Phase 5b if at all; `readmit_community_member` moves to `membership_update` in the gated File C (D-S10); the server-side answer-copy removal stays gated (Phase 5 D-9); File B block 7's revokes are kept in the gated set (Phase 5 D-S3); signed URLs are resolved in memory while the stored public URL stays in the database and SwiftData (D-2); the string keys orphaned by the deletions stay in the catalog until an owner-approved clean-up.
