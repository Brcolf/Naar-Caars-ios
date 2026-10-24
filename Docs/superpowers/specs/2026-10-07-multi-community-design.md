# Multi-community Naar's Cars — design spec

> Date: 2026-10-07
> Status: **Proposed.** Nothing here is approved, applied to Supabase, built or scheduled. The 28 open decisions are in section 7.
> Roadmap and sequencing: [`Docs/roadmap/2026-10-07-next-level-roadmap.md`](../../roadmap/2026-10-07-next-level-roadmap.md). Companion spec: [`2026-10-07-android-parity-design.md`](2026-10-07-android-parity-design.md). Evidence base: the research maps, kept outside the repository (see `the research maps (local) README.md`); they are cited below as "the backend map", "the notifications map" and so on.
> Reading note: "v1" in this document is the first synthesis, written before the adversarial review. It is not in the repository; section 10 records how each review finding changed it. "Minimal", "Model" and "Product" are the three competing designs the synthesis was built from; section 9 says what each contributed and why it was not chosen.
> Public-repository note: sections 3.8, 5 and decision D16 describe exposures that are still open on the live backend (public storage buckets, the geocoding cache, a message push that reaches a member who left a thread). Per `CLAUDE.md`, ask the owner before pushing this file.

Prepared 2026-10-07 against the worktree at `8d558f6` and the live Supabase schema snapshot of 2026-10-06 (the live schema notes: 26 tables, 103 policies, 38 triggers, 19 profiles, 106 rides, 61 favors, 34 posts, 2,830 notifications, 243 `xp_events`). This is the second synthesis. It keeps the first one's shape and folds in the review: 51 confirmed findings (13 of them high or critical, each upheld by a three-vote refutation panel) and 3 disputed ones. Section 10 has one line per finding; section 1.4 lists what materially changed. Paths are repo-relative; Swift paths are under `NaarsCars/` (so `Core/Services/AdminService.swift` means `NaarsCars/Core/Services/AdminService.swift`); migrations are under `supabase/migrations/`. Where the live database and a committed file differ, the live body is what is cited.

---

## 1. Summary and recommendation

### 1.1 The recommendation in one paragraph

Add a `communities` table, a `community_members` table (role `owner | admin | member`, status `pending | active | left | removed`), a `community_invites` table with redemptions, and one `community_id` column on the three content tables that define a community (`rides`, `favors`, `town_hall_posts`) plus `xp_events`, `notifications` (nullable, derived) and `reports` (nullable, derived). Every "everyone" predicate in RLS and in the fan-out loops becomes a membership predicate evaluated once per statement through caller-bound helpers (`my_community_ids()`, `my_admin_community_ids()`), so isolation is enforced by the database from the first server-side migration and no client filter is ever the security boundary. Keep `profiles.approved` and `profiles.application_complete` as **maintained mirrors** of the membership table (`approved` = has an active membership in a live community; `application_complete` = has an active or pending one), and bridge the installed build's three legacy writes (application submit, admin approve, admin reject) to memberships in the default community with state-based, re-entrant triggers, so the App Store build keeps working unchanged against the new schema. Back-fill every existing row into one default community ("Naar's Cars Seattle", public, approval-gated). On the client, **Requests is a merged feed** across the person's communities (a community chip on each card, hidden while they belong to one), **Town Hall and the leaderboard are per community** behind a title menu on the Community tab, **Messages and the bell are one per-person inbox**, and the create-ride / create-favor forms ask "Post to" only when the person belongs to more than one community. Someone in exactly one community (every current member on day one) sees an app that is identical to today except for one new Profile row.

### 1.2 Why this shape

- **Isolation lands server-side first and needs no app update.** Phase 0 is database-only; the installed build sees the same 106 / 61 / 34 rows, the same pushes and the same approval screens, because its "everyone" is the default community, which is still everyone. Phase 0 is ordered so that every single MCP call leaves the live app working (section 4), and `NOT NULL` is the last step, not the first.
- **The merged Requests feed is the cheapest correct option on the fragile data path.** `DashboardSyncEngine.performFullSync` keeps calling `fetchRides()` / `fetchFavors()` with no filter (`Core/Storage/DashboardSyncEngine.swift:89-91`); RLS returns the union of the person's communities; the SwiftData store holds that union; the reconciliation deletes at `Core/Storage/BackgroundSyncActor.swift:738-741, 775-778` stay correct with no partitioning and no wipe; `RefreshCoordinator.reset()` is never called for a community switch. It is also the right product answer for a rides app: a time-critical ask in community B is never hidden from a person looking at A.
- **No new auth state, no new notification type through Phase 3, no coordinator or realtime change.** `AuthState` keeps its seven cases (`Core/Services/AuthService.swift:729-737`) because the two mirrored flags keep driving `checkAccountStatus`; "no community" is the existing `.needsApplication`, whose root view becomes the community onboarding screen. Realtime stays conversation-scoped.
- **Every bridge is attached to the right event and is state-based.** The installed build submits an application with a direct `UPDATE profiles … application_complete = true` (`Core/Services/ProfileService+AccountStatus.swift:38-49`), approves with a direct `UPDATE profiles SET approved = true` (`Core/Services/AdminService.swift:258-290`), rejects through `admin_reject_pending_user`, and routes at launch on `is_banned / approved / application_complete` (`App/AppLaunchManager.swift:243-267`). The bridges hook exactly those writes. None tests `current_user`; each is a no-op when the state it would write already holds.
- **No RPC signature changes.** Adding a defaulted parameter to an existing name creates a second overload and makes the installed build's call ambiguous. Every community-scoped RPC has a **new name**; the old names stay and become thin wrappers that resolve the default or primary community.
- **Account deletion by anyone other than the user is not widened.** `auth.users` rows are deleted only by `delete_user_account` (self) or by a platform admin rejecting an applicant to the default community who holds no other membership. Community owners and admins can never delete an account (section 3.5).

### 1.3 Where the three designs disagreed, and what this document decides

| Question | Minimal | Model | Product | Decision here |
|---|---|---|---|---|
| Requests dashboard | one active community, switcher, wipe-on-switch, `reset(domains:)` overload | one active community, partitioned store, `reset()` | merged feed with chips, optional narrow | **Merged feed with chips and an optional local narrow.** No wipe, no partition, no `reset()`. |
| Town Hall / leaderboard | per active community | per active community | per community, independent of Requests | **Per community via a title menu on the Community tab; the switch is one `forceFullRefreshAndWait(.townHall, …)` from the ViewModel** (never `invalidate`, which CLAUDE.md forbids from a ViewModel). Section 3.7 defines what a nil community means and how a joined sync is handled. |
| Launch state | keep 7 `AuthState` cases, derived flags | replace `checkAccountStatus` with `get_my_memberships`, add `.noCommunity` | add `.noCommunity`, RPC launch read | **Keep the 7 cases and `checkAccountStatus`.** `get_my_memberships` is loaded after launch hydration starts and never blocks launch. |
| Legacy sign-up bridge | AFTER UPDATE OF `application_complete` | AFTER UPDATE OF `application_complete` | AFTER INSERT on `profiles` (verified wrong) | **AFTER UPDATE OF `application_complete`, false→true, only when the user holds no active or pending membership.** |
| Legacy approve bridge | `current_user in ('authenticated')` (cannot fire inside a definer trigger) | state-based | none (verified gap) | **State-based (section 3.3).** |
| Legacy reject | not covered | delete membership only | not covered | **Platform-admin-only, default-community applicants only; deletes the account only when no other membership row exists (section 3.5, D20).** |
| RLS helpers | per-row `is_active_member(uuid)` | `my_community_ids()` InitPlan arrays + wrappers | per-row `is_community_member(uuid)` | **Model's array helpers; Minimal's names kept as wrappers.** |
| `communities.created_by` | `NOT NULL … ON DELETE SET NULL` | nullable | nullable | **Nullable.** |
| `rides.community_id` FK | no action | `ON DELETE RESTRICT`, archive only | `ON DELETE CASCADE` | **`ON DELETE RESTRICT`; communities are archived, never deleted while content exists.** |
| `community_members` visibility | own rows or any active member reads every row | tiered | tiered | **Own rows and the community's admins only. Members read the directory through `get_community_members`, which hides application answers from non-admins.** |
| Community admins reading `profiles` | never | new `profiles` SELECT policy | never | **Never.** |
| Community admins reading `reports` | not covered | table policy | table policy | **Never by table policy. They read `get_community_reports`, which omits the reporter and excludes reports about themselves (section 3.5).** |
| Invites | widen dormant `invite_codes` | new `community_invites` + redemptions | new `community_invites`, one active link | **New `community_invites` + `community_invite_redemptions`; `invite_codes` stays frozen.** |
| Phase order of the visibility tightening | all in the server-only Phase 0 | Phase 6 (verified leak window) | Phase 1 | **All of it in Phase 0, before any second community can exist.** |
| `get_or_create_conversation` side door | "add when touched, or leave and note" | closed | not mentioned | **Closed in Phase 0.** |
| Join policy vocabulary | `invite \| approve` + `is_public` | 3 × 3 | two booleans | **`join_policy in ('invite','approve')` + `is_public`.** |
| `notifications.community_id` | deferred | day one, derive trigger | day one | **Day one, nullable, derived, back-filled now.** |
| Universal Links | later | Phase 5 | Phase 3 | **Phase 4, with the code in the URL fragment.** |
| New notification types | none in Phases 0–2 | none before the tolerant decoder ships | none for core flows | **None through Phase 3; the tolerant decoder ships in the first iOS build (Phase 1).** |

### 1.4 What changed from v1

1. **Phase 0 is reordered so no step can break the live app.** `NOT NULL` moves to a final step applied after the XP writers, fill triggers and fan-out are live and probed; `xp_events` gets its own fill trigger; no step relies on several MCP calls being one transaction; `guard_last_owner` ships in the same SQL-editor run as the new `delete_user_account`.
2. **Nobody but the user or a platform admin can delete an account.** `admin_reject_pending_user` stays platform-admin-only, acts only on applicants to the default community, and refuses everything else with an error the installed build already displays.
3. **Community owners actually receive what the design sends them.** `should_notify_user` is edited in Phase 0; the `pending_approval` tap gets a real destination and an approve / reject screen in Phase 2 (v1 had neither until Phase 3).
4. **The two mirrored flags are both fully maintained.** A person whose last community ends (leave, removal, archive) is routed to onboarding, on both builds, instead of a waiting screen with nothing pending; the new build also re-routes a running session.
5. **Town Hall scoping has defined behaviour for a nil community, for rows cached by the previous build, for launch order and for a refresh that joins a sync started for another community.**
6. **Reputation is per person by construction.** Rating, review count and fulfilled count come from one definer RPC, so they no longer depend on who is looking; the review list stays scoped to what the viewer may read.
7. **Reporter privacy carries over to community admins**, reports about an owner or admin skip that community's admins, and a community itself can be reported.
8. **Legal documents are a Phase 2 deliverable** (privacy policy, terms, FAQ and the Notion copies the app links to).
9. **Invite abuse is bounded by the RPC**, validation requires a signed-in account, and the code alphabet matches the app's generator (31 symbols).
10. **Archive is a real state**: the helpers exclude archived communities and archiving re-evaluates every member's flags.
11. Nine new decisions (D20–D28); D3, D5, D8, D10, D15, D16 and D17 are revised.
12. Four v1 defects the review did not raise were found while revising and are fixed; they are listed at the end of section 10.

---

## 2. Product behaviour

Vocabulary: **community** (the tab is already called Community; "Town Hall" stays the feed's name). "Member" always means `status = 'active'`, not platform-banned, in a community that is not archived. The current group becomes **the default community** (name per D1; "Naar's Cars Seattle" assumed below). **Platform admin** means `profiles.is_admin` (today's four). **Community admin** means role `owner` or `admin` in that community.

### 2.1 Rules

1. **A community is private by default.** Its requests, Town Hall, leaderboard, member directory and announcements are visible only to its active members. `is_public = true` makes it browsable by guests (addresses still blanked) and lets a signed-in person request to join it without an invite. The default community is public at backfill so the guest path Apple reviewed is unchanged (D7).
2. **Every ride, favor and Town Hall post belongs to exactly one community**, fixed at creation; editing cannot move it.
3. **A person may belong to several communities.** Requests shows all of them merged (chip per card); the Community tab shows one at a time (title menu); Messages, the bell and Profile are the same everywhere. `profiles.primary_community_id` is the server-side tie-breaker for clients that do not say where to post (the installed build). It is server-owned: a client cannot write it directly, only through `set_primary_community`.
4. **Posting:** with one membership the create forms are unchanged. With two or more, a first "Post to" section shows a picker. Its default is the community Requests is narrowed to, else the Community tab's community, else the one last posted to, else the primary (D24). The submit button reads "Post to <community>", so a wrong default is visible at the moment of posting.
5. **Joining** happens one of three ways, all ending in the same membership row: redeem an invite (typed code, link, or QR), request to join a public community (the two existing application questions), or be the creator. A community with `join_policy = 'invite'` admits an invite redeemer at once; `'approve'` makes the membership `pending` until a community admin approves. A platform-banned account cannot join or be approved anywhere. The default community keeps `'approve'`, so today's application and admin approval continue to work for it.
6. **Creating:** any signed-in, unbanned account can create a community and becomes its `owner` (active). No platform approval is needed; this is how a newcomer becomes "approved" without ever touching Seattle. Platform admins are told about every new community and can archive it (D25). Section 3.8 lists what "approved" still unlocks now that it can be self-granted.
7. **Messaging is not community-scoped.** You can start a conversation with anyone who shares an active community with you; the directory is the union of your communities' members. The check is made against the person who creates the thread or adds someone, so a member of two communities can put people from both in one group thread; from then on those people can see each other's name and avatar and message in that thread (D8). Existing threads survive leaving or removal and stay writable. A person with no community at all is in onboarding and cannot reach Messages until they join one.
8. **Leaderboard and spotlights are per community**, computed from activity in that community. **Reputation is per person**: rating, review count, fulfilled count, savings, total XP and badges are the same whoever looks, served by RPCs. The list of written reviews shows only reviews of requests the viewer can see, with a line "N more reviews in other communities" (D5).
9. **Guests** browse only public communities. If none is public, the guest tabs show the existing empty states and the already-defined `GuestRestrictionReason.joinCommunity`.
10. **Admin and moderation.** Platform admins keep every power they have and can act in any community (the always-reachable moderator Guideline 1.2 needs). Community owners and admins approve and reject applicants (Phase 2), remove and promote members, send announcements and handle reports about their community (Phase 3). Every report always reaches the platform admins. From Phase 3 a report also reaches that community's admins, with three limits: they never see who reported; the reported person is never among the recipients; and a report about an owner's or admin's content or behaviour goes to the platform admins only. A community admin can never delete anyone's account and never sees a member's email or phone number.
11. **Removal is a membership status, not a ban.** A removed member no longer sees that community and cannot redeem an invite to it; only a community admin can re-admit them (D4). If it was their only community they land on the onboarding screen (rule 18). The platform ban (`profiles.is_banned`) is unchanged and global.
12. **Notifications:** new rides, favors and posts notify only the community's members who have not muted it (the mute switch ships with the first multi-community build, Phase 2). The bell and badges aggregate across communities (one inbox, one app-icon number). The Community tab badge is the sum over all of the person's communities; opening the tab marks only the visible community's Town Hall rows read, and the title menu shows a count beside each other community. Bell rows carry a community chip when the person has two or more memberships. A push or bell row for a Town Hall post in community B switches the Community tab to B before opening the post; a push for a ride needs no switch (Requests is merged).
13. **Leaving** has three stated consequences in that community, listed with counts on the Leave sheet: claims you made are reopened and the posters are told; open requests you posted are removed; requests you posted that a neighbor already claimed are cancelled and the helper is told (D26). Completed history stays. Your posts and comments stay and show "Former member" to people who can no longer see your profile. Invite codes you created for it stop working. The last owner must transfer ownership first, unless they are the only member, in which case leaving archives the community.
14. **Account deletion** removes all memberships and revokes the user's invite codes. A community the user owns alone is handed to its longest-standing admin; if it has no other admin it stays open without an owner and any member can take it over; if it has no other member it is archived (D23).
15. **Old builds** keep working: an installed build posts into the primary community without knowing communities exist, reads the union of its memberships (exactly the default community until the person joins a second one from a new build), and its admins keep approving and rejecting default-community applicants through the bridges.
16. **Archiving** (owner or platform admin) makes a community invisible and read-nothing for its members at once; its content is kept, not deleted, and a platform admin can restore it. Members are told. People with an in-flight claim there are told it was cancelled.
17. **Blocks are global and unchanged.** The member directory and member search leave out people you blocked and people who blocked you (enforced on the server so both platforms agree). A block does not change membership or admin powers: an admin you blocked can still approve, remove or moderate you, and applicant and report notices to admins are not block-filtered, because handling them is the admin's duty.
18. **No community means onboarding.** A person with no active and no pending membership (never joined, left their last one, was removed from it, was rejected, or it was archived) sees the onboarding screen: join with a code, request to join a public community, or create one. The new build moves a running session there as soon as it learns of the change; the installed build does so at the next launch and shows its application form, which applies to the default community.

### 2.2 Flow catalog

| # | Flow | Entry point | Server call(s) | Result and notifications |
|---|---|---|---|---|
| F1 | Create a community | Profile → My communities → Create; onboarding screen | `create_community(p_name, p_description, p_join_policy)` | Community + owner membership; `primary_community_id` set if null; invite sheet opens immediately; no "approved" notice to the creator; platform admins get a bell row |
| F2 | Invite | My communities → row → Invite | `create_community_invite(p_community_id, p_max_uses, p_expires_at)` | `NC…` code, share text with the App Store link (`Constants.URLs.appStore`), QR; members get single-use codes that expire in 7 days, admins can make multi-use codes with an expiry; Universal Link in Phase 4 |
| F3 | Join with a code (signed in) | My communities → Join with a code; onboarding | `validate_community_invite(p_code)` → sheet → `redeem_community_invite(p_code, p_heard_about, p_join_reason)` | active or pending membership; when pending, the community's admins get `pending_approval` |
| F4 | Join with a code (signed out) | Welcome banner (Phase 4 link) or typed after sign-up | code stored in `PendingInviteStore`; validated and redeemed after sign-up | same as F3; no Seattle admin involved; the signed-out banner shows no community details |
| F5 | Request to join a public community | onboarding "Request to join <name>" | `request_to_join_community(p_community_id, p_heard_about, p_join_reason)` | pending membership; that community's admins notified |
| F6 | Approve / reject an applicant | Phase 2 build: My communities → row → Requests to join, or the `pending_approval` tap. Installed build: Pending Users (bridge, default community only) | `approve_community_member` / `reject_community_member`; installed build: `UPDATE profiles SET approved = true` / `admin_reject_pending_user` | see 2.4 for the notices. `reject_community_member` deletes the pending row and never the account. The installed build's reject works only for an applicant to the default community and deletes the account only when the person has no other membership row |
| F7 | Post a ride / favor | dashboard `+` | `rides` / `favors` INSERT with `community_id` (new build) or without (old build; fill trigger) | `new_ride` / `new_favor` to that community's unmuted members |
| F8 | Claim | detail screen | direct UPDATE as today | refused (42501) unless the claimer is an active member of the request's community, by policy and by trigger |
| F9 | Switch the Community tab | title menu | `forceFullRefreshAndWait(.townHall, trigger: "communitySwitch")` | feed, leaderboard and spotlights for the chosen community |
| F10 | Narrow Requests | title menu (optional) | none (local predicate) | chips hidden while narrowed; persisted per account; also the "Post to" default |
| F11 | Tap a push or bell row for another community's post | notification | `community_id` in `userInfo` or on the bell row, else looked up from the post | Community tab switches, then scrolls / opens as today; "no longer available" when the post cannot be read |
| F12 | Leave | My communities → row → Leave (three consequences listed with counts) | `leave_community(p_community_id)` | rule 13; if it was the only community the app moves to onboarding |
| F13 | Remove a member | Admin → Members (Phase 3) | `remove_community_member(p_community_id, p_user_id, p_reason)` | `removed`; requests unwound as for leaving; the member gets `account_restricted` and, on the new build, the community disappears (or onboarding if it was the only one) |
| F14 | Promote / transfer | Admin → Members (Phase 3) | `set_member_role`, `transfer_community_ownership` | owner-only; last-owner guard |
| F15 | Archive | owner (community settings, Phase 3) or platform admin (community list, Phase 2) | `archive_community` | rule 16 |
| F16 | Delete account | Profile; pre-approval and banned screens | `delete_user_account` | rule 14 |
| F17 | Report content or a person | every UGC surface (unchanged) | `submit_report` (unchanged signature) | `reports.community_id` derived; platform admins notified; from Phase 3 the community's admins too, per rule 10 |
| F18 | Guest browse | Welcome → Continue as guest | `guest_rides` / `guest_favors` / anon policies, now joined to `communities.is_public` | public communities only |
| F19 | Mute a community | My communities → row → Mute (Phase 2) | own-row UPDATE of `community_members.notifications_muted / muted_until` (column grant) | fan-out and community broadcasts skip the member |
| F20 | Report a community | invite preview sheet; My communities → row → Report (Phase 2) | `report_community(p_community_id, p_code, p_report_type, p_description)` | a report with `reported_community_id`; platform admins only |
| F21 | Take over a community with no owner | banner on the My communities row (Phase 2) | `claim_community_ownership(p_community_id)` | first active member to accept becomes owner; members get an announcement row |
| F22 | Review new communities | platform admin: Admin → Communities (Phase 2) | `get_platform_communities()`, `archive_community`, `unarchive_community` | list with member count, creator, "no owner" and "reported" markers |

### 2.3 Scenarios

- **S1 — The day after Phase 0, nobody has updated.** Alice (installed build) posts a ride. Her client sends no `community_id`; `fill_request_community` sets Seattle from `profiles.primary_community_id`. `notify_new_ride` loops over Seattle's 18 other members, as before. Her dashboard shows the same 106 rides. Nothing changed for her.
- **S2 — Bob creates "Ballard Neighbors" on the Phase 2 build.** `create_community` makes the community and his owner membership; his `approved` was already true. The invite sheet opens; he shares `NC7K2PQ9XA` to a WhatsApp group. His Requests feed now shows chips ("Seattle", "Ballard") on every card; the Community tab's title is "Naar's Cars Seattle ▾" with Ballard in the menu; creating a ride asks "Post to" and the button says which community. The four platform admins see "New community: Ballard Neighbors" in their bell.
- **S3 — Carol has never used the app and types Bob's code.** She signs up (open signup, unchanged), lands on the onboarding screen (`.needsApplication`), chooses "I have a code", enters it; `validate_community_invite` shows "Ballard Neighbors · an admin approves new members"; she answers the two questions; `redeem_community_invite` creates a pending Ballard membership; the mirror sets `application_complete = true`; the legacy bridge sees a pending membership and does **not** create a Seattle application. Bob, not Seattle's admins, gets "New request to join Ballard Neighbors" as a bell row and a push (the `should_notify_user` edit in Phase 0 is what lets it through to a non-platform admin). He taps it and lands on Ballard's Requests to join screen, reads her two answers (no email, no phone) and approves. Carol's `approved` flips; her waiting screen, which named Ballard, sees it and she enters the app. Her Requests feed shows only Ballard; she cannot find or message any Seattle member. A Seattle platform admin was not notified and, on the new build, does not see Carol in Seattle's list.
- **S4 — Dave (Seattle, installed build on his iPad, new build on his phone) joins Ballard from the phone.** Both devices read the union: the phone shows chips, the iPad shows the merged rows with no chips and posts into Seattle (primary). Isolation holds; only the presentation differs on the old build.
- **S5 — Erin asks to join Seattle on the new build.** `request_to_join_community` writes a pending Seattle membership with her answers and copies them to `profiles.heard_about / join_reason` so the installed admin build's Pending Users detail still shows them. A platform admin on the installed build taps Approve: `UPDATE profiles SET approved = true` → `sync_legacy_approval_to_membership` activates her pending **Seattle** row. On the new build the admin approves from Seattle's Requests to join screen (`approve_community_member`). Either way `notify_user_approved` fires once because `approved` flips once.
- **S6 — A Seattle platform admin on the installed build sees Carol (a Ballard applicant) in Pending Users.** The old list is `profiles WHERE approved = false` (`Core/Services/AdminService.swift:151-167`) and cannot tell her from a Seattle applicant. **Approve:** the bridge finds no pending Seattle row, restores `approved = false` in the same transaction, and the installed build shows its "Approval update failed" error banner (its verify re-read at `AdminService.swift:288-302` throws). **Reject:** `admin_reject_pending_user` finds no pending Seattle row and returns `{success: false, error: "This person applied to a different community"}`, which the installed build shows as "Failed to reject user: …" (`AdminService.swift:353-360`). Nothing is changed and nothing is deleted either way. Carol stays in that old list, and in the old build's Profile badge count, until Bob decides; the Phase 2 release notes tell the four admins to update (D10).
- **S7 — Priya (Seattle only) is forwarded a push for Dave's Ballard ride.** The detail fetch returns no row ("This request is no longer available"); a crafted claim UPDATE fails `guard_request_claim_membership` with 42501.
- **S8 — Carol reports a Ballard post.** `submit_report` is unchanged; `derive_report_community` sets Ballard; the four platform admins are notified and any of them can hide it. From Phase 3 Bob is notified too, sees the report in Ballard's list without Carol's name, and can hide the post. If the post is Bob's own, Bob gets nothing and the report is not in his list; only the platform admins handle it.
- **S9 — A guest opens the app.** Seattle is public, Ballard is not: the guest sees Seattle's open requests (addresses blanked) and Seattle's Town Hall, nothing from Ballard, no Ballard member in `public_profiles`.
- **S10 — Bob deletes his account as Ballard's only owner.** If Ballard has another admin, the longest-standing one becomes owner and members see "Ballard Neighbors has a new owner". If it has members but no admin, Ballard stays open, its row shows "No owner. Take over", pending applicants go to the platform admins meanwhile, and the first member to accept becomes owner. If Bob was alone, Ballard is archived. Bob's invite codes stop working. Then today's deletion steps run.
- **S11 — Maria is in both communities and reads Seattle's Town Hall while a Ballard post arrives.** The push shows a banner; tapping it flips the Community tab to Ballard and opens the comments. Her Requests tab, unaffected, still shows both communities. The Community tab badge counted the Ballard post; after she reads Ballard it clears, and the Seattle rows she had not read stay unread.
- **S12 — Carol leaves Ballard, her only community.** The Leave sheet says: "1 claim will reopen. 2 requests you posted will be removed; one has a helper who will be told." She confirms. `leave_community` unwinds, sets `left`, revokes her invite codes; the mirror sets `approved = false` and `application_complete = false`. The new build re-runs the launch check and shows onboarding. On an installed build she would stay in an empty app until the next launch, then see the application form, which would apply to Seattle.
- **S13 — First launch after updating to the Phase 1 build, in airplane mode.** No community is stored for the Community tab yet and the membership call fails. Town Hall treats "no community" as "no filter" and shows the posts the previous build cached (their community is unknown, so they are shown). Online, the launch sync writes each post's community and the tab resolves to the person's one community with no visible change.

### 2.4 What each membership event tells people

No new notification type is used through Phase 3. "Bell" is a `notifications` row; "push" is a queued APNs push. The installed build's tap destination is given because old devices receive these too.

| Event | Recipients | Type | Text | Push | Tap (new build / installed build) |
|---|---|---|---|---|---|
| Application to an approval community | that community's owner and admins; platform admins only when it has no owner or admin | `pending_approval` | "New request to join <community>" / "<name> wants to join." | yes | Requests to join for that community / Pending Users (platform admins only; an error screen for anyone else) |
| First approval (`approved` false→true by an approver) | the applicant | `user_approved` | "Welcome to <community>!" / "You've been approved. Tap to enter the app." | yes | enters the app (both) |
| Creating a community, or an instant invite join | nobody | — | the app enters directly | — | — |
| Approval into a further community | the applicant | `user_approved` with `community_id` | "You're in: <community>" / "Your request to join was approved." | yes (D22) | My communities, no relaunch / relaunch check, then the dashboard |
| Rejection (Phase 3) | the applicant | `user_rejected` | "Request not approved" / "Your request to join <community> was not approved." | yes | notifications list (both); the waiting screen moves to onboarding by itself |
| Removal (Phase 3) | the member | `account_restricted` | "Removed from <community>" / "A community admin removed you." | yes | My communities or onboarding / no navigation |
| New community created | platform admins | `announcement` | "New community: <name>" / "Created by <creator>." | no | Admin → Communities / announcements list |
| Ownership handed over on deletion | every member; the new owner also gets a push | `announcement` | "<community> has a new owner" / "<name> is now the owner because the previous owner's account was closed." | new owner only | announcements list (both) |
| Community left without an owner | every member | `announcement` | "<community> needs an owner" / "Any member can take over from My communities." | no | announcements list (both) |
| Community archived | every member | `announcement` | "<community> was archived" | no | announcements list (both) |

`send_approval_notification` (the pinned-row RPC) has had no caller since `d03cde4`; it is left as it is and is not part of any flow here.

---

## 3. Data model and architecture

### 3.1 Backend — DDL (`20261007_0001_communities_core.sql`, all additive)

Conventions follow the 2026-10 migrations: `text` + CHECK instead of enums, `(select auth.uid())` in predicates, `set search_path = ''` and schema-qualified names in every function, EXECUTE revoked from `public, anon` by default (the backend map §C4). **This file adds nothing that can reject a write from the installed build**: every new column on an existing table is nullable here, and the four `SET NOT NULL` statements live in `20261007_0006` (section 4).

```sql
create table public.communities (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null check (length(btrim(name)) between 2 and 60),
  description        text check (char_length(description) <= 300),
  slug               text unique,                                   -- reserved for the Phase 4 link
  created_by         uuid references public.profiles(id) on delete set null,   -- NULLABLE: deletion must succeed for creators
  is_default         boolean not null default false,                -- exactly one: the legacy community (bridges, old-client fill)
  is_public          boolean not null default false,                -- guest browsing + request-to-join
  join_policy        text not null default 'approve' check (join_policy in ('invite','approve')),
  members_can_invite boolean not null default true,
  timezone           text not null default 'America/Los_Angeles',
  owner_vacant_since timestamptz,                                   -- set when the only owner's account is deleted and no admin exists (D23)
  archived_at        timestamptz,
  archived_by        uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create unique index communities_one_default on public.communities (is_default) where is_default;
create index communities_public_active on public.communities (is_public) where archived_at is null;

create table public.community_invites (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references public.communities(id) on delete cascade,
  -- "NC" + 8 characters from the app's alphabet, Core/Utilities/InviteCodeGenerator.swift:16:
  -- ABCDEFGHJKMNPQRSTUVWXYZ23456789 (31 symbols: no I, L, O, 0, 1). 31^8 ≈ 8.5e11 codes.
  code          text not null unique check (code ~ '^NC[A-HJKMNP-Z2-9]{8}$'),
  created_by    uuid references public.profiles(id) on delete set null,
  max_uses      int check (max_uses is null or max_uses between 1 and 1000),
  use_count     int not null default 0,
  expires_at    timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index community_invites_community_live on public.community_invites (community_id) where revoked_at is null;
create index community_invites_creator_live   on public.community_invites (created_by)   where revoked_at is null;

create table public.community_members (
  community_id        uuid not null references public.communities(id) on delete cascade,
  user_id             uuid not null references public.profiles(id) on delete cascade,
  role                text not null default 'member' check (role in ('owner','admin','member')),
  status              text not null default 'pending' check (status in ('pending','active','left','removed')),
  invited_by          uuid references public.profiles(id) on delete set null,
  invite_id           uuid references public.community_invites(id) on delete set null,
  approved_by         uuid references public.profiles(id) on delete set null,
  heard_about         text check (char_length(heard_about) <= 500),     -- readable by the member and the community's admins only (3.4)
  join_reason         text check (char_length(join_reason) <= 500),
  removal_reason      text check (char_length(removal_reason) <= 500),
  notifications_muted boolean not null default false,               -- own-row column grant; UI in Phase 2
  muted_until         timestamptz,
  joined_at           timestamptz not null default now(),
  activated_at        timestamptz,
  ended_at            timestamptz,
  updated_at          timestamptz not null default now(),
  primary key (community_id, user_id),
  constraint community_members_role_requires_active check (role = 'member' or status = 'active')
);
-- the RLS hot path: "which communities am I an active member of"
create index community_members_user_active on public.community_members (user_id) include (community_id, role) where status = 'active';
-- admin lists and fan-out loops
create index community_members_community_status_role on public.community_members (community_id, status, role);

create table public.community_invite_redemptions (
  invite_id    uuid not null references public.community_invites(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  redeemed_at  timestamptz not null default now(),
  primary key (invite_id, user_id)
);

-- one row per validate / redeem call; the per-account rate limit counts these. No client access (RLS on, no policy).
-- Rows older than a day are deleted by the existing nightly job (03:15).
create table public.community_invite_attempts (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  attempted_at timestamptz not null default now(),
  succeeded    boolean not null
);
create index community_invite_attempts_user_time on public.community_invite_attempts (user_id, attempted_at desc);

-- append-only audit of membership and community transitions (the content_moderation_events pattern, 20261005_0024)
create table public.community_membership_events (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references public.communities(id) on delete cascade,
  user_id       uuid references public.profiles(id) on delete set null,
  actor_id      uuid references public.profiles(id) on delete set null,
  event         text not null check (event in ('applied','invited','approved','rejected','removed','readmitted','left',
                                               'role_changed','ownership_transferred','owner_vacated','ownership_claimed',
                                               'archived','unarchived')),
  old_role      text, new_role text, reason text,
  created_at    timestamptz not null default now()
);
create index community_membership_events_community on public.community_membership_events (community_id, created_at desc);
-- raise-on-mutation trigger copied from 20261005_0024. It permits two updates only: an FK column going to NULL,
-- and `reason` going to NULL (so account deletion can scrub free text written about the deleted user).

alter table public.profiles        add column primary_community_id uuid references public.communities(id) on delete set null;
alter table public.rides           add column community_id uuid references public.communities(id) on delete restrict;
alter table public.favors          add column community_id uuid references public.communities(id) on delete restrict;
alter table public.town_hall_posts add column community_id uuid references public.communities(id) on delete restrict;
alter table public.xp_events       add column community_id uuid references public.communities(id) on delete restrict;
alter table public.notifications   add column community_id uuid references public.communities(id) on delete set null;
alter table public.reports         add column community_id uuid references public.communities(id) on delete set null;
alter table public.reports         add column reported_community_id uuid references public.communities(id) on delete set null;
-- report_target_check (20260319074001) gains `or reported_community_id is not null`

create index rides_community_visible   on public.rides  (community_id, date) where hidden_at is null;
create index rides_community_status    on public.rides  (community_id, status);
create index favors_community_visible  on public.favors (community_id, date) where hidden_at is null;
create index favors_community_status   on public.favors (community_id, status);
create index thp_community_created     on public.town_hall_posts (community_id, created_at desc) where hidden_at is null;
create index xp_events_community_user  on public.xp_events (community_id, user_id, created_at);
create index xp_events_community_time  on public.xp_events (community_id, created_at);
create index notifications_user_unread_community on public.notifications (user_id, community_id) where read = false;
create index reports_community_status  on public.reports (community_id, status);
```

`ON DELETE RESTRICT` on the content FKs is deliberate: a community is archived, never hard-deleted while content references it (INV-C1).

**Backfill.** Two parts, both idempotent so they can be re-run. Part A (the community, memberships, the primary) runs right after the DDL, before any trigger exists, so it sends no notifications. Part B (content rows) runs after the fill triggers exist, so a row the installed build inserts in between is either filled by the trigger or picked up by Part B; no row is ever missed.

```sql
-- Part A
insert into public.communities (name, created_by, is_default, is_public, join_policy, timezone)
select 'Naar''s Cars Seattle', (select id from public.profiles where is_admin order by created_at limit 1), true, true, 'approve', 'America/Los_Angeles'
where not exists (select 1 from public.communities where is_default);          -- owner per D1

-- every approved profile → active member; the four admins → admin; the creator → owner
insert into public.community_members (community_id, user_id, role, status, joined_at, activated_at, heard_about, join_reason)
select c.id, p.id, case when p.is_admin then 'admin' else 'member' end, 'active', p.created_at, p.created_at, p.heard_about, p.join_reason
from public.profiles p cross join public.communities c where c.is_default and p.approved
on conflict (community_id, user_id) do nothing;
update public.community_members m set role = 'owner'
  from public.communities c where c.is_default and m.community_id = c.id and m.user_id = c.created_by and m.role <> 'owner';
-- pending applicants (approved = false, application_complete = true) → pending membership
insert into public.community_members (community_id, user_id, status, heard_about, join_reason)
select c.id, p.id, 'pending', p.heard_about, p.join_reason
from public.profiles p cross join public.communities c where c.is_default and not p.approved and p.application_complete
on conflict (community_id, user_id) do nothing;
update public.profiles set primary_community_id = (select id from public.communities where is_default)
 where approved and primary_community_id is null;
-- a few legacy accounts were approved without ever submitting the form; align the flag the mirror will own (no routing effect)
update public.profiles set application_complete = true where approved and not application_complete;

-- Part B (after the fill triggers of 3.3 exist)
update public.rides           set community_id = (select id from public.communities where is_default) where community_id is null;
update public.favors          set community_id = (select id from public.communities where is_default) where community_id is null;
update public.town_hall_posts set community_id = (select id from public.communities where is_default) where community_id is null;
update public.xp_events       set community_id = (select id from public.communities where is_default) where community_id is null;
update public.notifications n set community_id = (select id from public.communities where is_default)
 where n.community_id is null and (n.ride_id is not null or n.favor_id is not null or n.town_hall_post_id is not null or n.review_id is not null);
update public.reports r set community_id = (select id from public.communities where is_default)
 where r.community_id is null and r.reported_message_id is null;     -- content and person reports; message reports stay null
```

The application answers copied onto the membership rows are readable only by the member and by that community's admins (section 3.4). In the default community those admins are the four platform admins, who read the same answers on `profiles` today, so the copy exposes nothing new.

Live counts make this trivial (19 / 106 / 61 / 34 / 243 / 2,830 / 18). The owner in D1 is "the account that owns the project"; if that is not the oldest admin, set `created_by` by id in the insert.

**Why a nullable `community_id` is safe in the meantime, and why `NOT NULL` is safe later.** `fill_request_community` (BEFORE INSERT, section 3.3) fills the column before the RLS `WITH CHECK` and before any constraint; `fill_xp_event_community` does the same for the XP rows the three writer triggers insert. Once those exist no path can produce a null, and step 6 only turns that fact into a constraint after a count has confirmed it. The installed decoders ignore unknown response keys (`Ride` / `Favor` / `TownHallPost` use synthesized `CodingKeys`, `Core/Models/Ride.swift:40-64`).

### 3.2 Backend — the RLS vocabulary (caller-bound helpers)

All SECURITY DEFINER, STABLE, `set search_path = ''`. The two array-returning helpers take no user argument and read `auth.uid()` themselves, extending the `20261005_0020_rls_helpers_answer_only_for_caller.sql:30-45` rule; policies use them in the InitPlan form `(select public.my_community_ids())` so they run once per statement and every scoped scan is `community_id = ANY($1)` against the `(community_id, …)` indexes rather than a per-row function call. **An archived community is in neither array**, so archiving cuts every scoped read and write at once.

```sql
create or replace function public.my_community_ids() returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(m.community_id), '{}'::uuid[])
  from public.community_members m
  join public.profiles p    on p.id = m.user_id
  join public.communities c on c.id = m.community_id and c.archived_at is null
  where m.user_id = (select auth.uid()) and m.status = 'active' and p.is_banned = false;
$$;

-- communities the caller administers; platform admins get every non-archived community (the moderation fallback)
create or replace function public.my_admin_community_ids() returns uuid[]
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.is_banned)
      then coalesce((select array_agg(c.id) from public.communities c where c.archived_at is null), '{}'::uuid[])
    else coalesce((select array_agg(m.community_id)
                   from public.community_members m
                   join public.profiles p    on p.id = m.user_id
                   join public.communities c on c.id = m.community_id and c.archived_at is null
                   where m.user_id = (select auth.uid()) and m.status = 'active' and m.role in ('admin','owner') and p.is_banned = false),
                  '{}'::uuid[])
  end;
$$;

create or replace function public.is_active_member(p_community_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_community_id = any ((select public.my_community_ids()));
$$;
create or replace function public.is_community_admin(p_community_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_community_id = any ((select public.my_admin_community_ids()));
$$;
create or replace function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.is_banned);
$$;
-- "is p_user an active member of p_community" — answers only when the CALLER is a member of it (no oracle)
create or replace function public.community_has_member(p_community_id uuid, p_user_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_active_member(p_community_id)
     and exists (select 1 from public.community_members m
                 where m.community_id = p_community_id and m.user_id = p_user_id and m.status = 'active');
$$;
create or replace function public.shares_community_with(p_other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_other = (select auth.uid()) or exists (
    select 1 from public.community_members m
    where m.user_id = p_other and m.status = 'active' and m.community_id = any ((select public.my_community_ids())));
$$;
-- self; co-members; co-participants of threads the caller is still in (so a sender who left a community still
-- renders in a thread, and leaving a thread ends the exposure); and the other side of the caller's own reviews
-- (so the reviews on one's own profile keep their names after a community is left).
create or replace function public.my_visible_profile_ids() returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct u), '{}'::uuid[]) from (
    select (select auth.uid()) as u
    union all select m.user_id from public.community_members m
              where m.status = 'active' and m.community_id = any ((select public.my_community_ids()))
    union all select b.user_id from public.conversation_participants a
              join public.conversation_participants b on b.conversation_id = a.conversation_id
              where a.user_id = (select auth.uid()) and a.left_at is null
    union all select r.reviewer_id  from public.reviews r where r.fulfiller_id = (select auth.uid())
    union all select r.fulfiller_id from public.reviews r where r.reviewer_id  = (select auth.uid())
  ) s where u is not null;
$$;
create or replace function public.default_community_id() returns uuid
language sql stable security definer set search_path = '' as $$ select id from public.communities where is_default limit 1; $$;

-- non-caller-bound lookups used ONLY inside definer bodies and triggers
create or replace function public.community_of_request(p_type text, p_id uuid) returns uuid …;   -- service_role only
create or replace function public.community_of_post(p_post_id uuid) returns uuid …;             -- service_role only

revoke all on function public.my_community_ids(), public.my_admin_community_ids(), public.is_active_member(uuid),
  public.is_community_admin(uuid), public.is_platform_admin(), public.community_has_member(uuid, uuid),
  public.shares_community_with(uuid), public.my_visible_profile_ids(), public.default_community_id() from public;
grant execute on function (the nine above) to anon, authenticated, service_role;   -- anon gets '{}' / false / the default id
revoke all on function public.community_of_request(text, uuid), public.community_of_post(uuid) from public, anon, authenticated;
```

`anon` is granted the read helpers on purpose: they return an empty array or `false` for a null `auth.uid()`, so a `TO public` policy or an `EXISTS` subquery that runs under `anon` cannot fail with a function-permission error. `is_active_user(uuid)` and `is_admin_user(uuid)` keep their current bodies because `profiles.approved` is maintained (section 3.3) and `is_admin` stays the platform flag; nothing that calls them today changes. What `approved` means once it can be self-granted by creating a community is spelled out in section 3.8.

Because the helpers are SECURITY DEFINER, the `community_members` policies can use them without recursion (the same reason `is_conversation_participant` exists, `20261005_0005`). A `community_members` policy must never read `community_members` with invoker rights.

### 3.3 Backend — triggers: fill, guards, the maintained flags and the legacy bridges

```sql
-- Fills community_id when the client omits it (the installed build always omits it). Uses new.user_id,
-- not auth.uid(), so definer code that inserts for another user is covered too. The stored primary is
-- trusted only while it is a live active membership, so a stale or crafted value can never misroute a post.
create or replace function public.fill_request_community() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_c uuid;
begin
  if new.community_id is not null then return new; end if;
  select m.community_id into v_c
    from public.profiles p
    join public.community_members m on m.user_id = p.id and m.community_id = p.primary_community_id and m.status = 'active'
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where p.id = new.user_id;
  if v_c is null then
    select m.community_id into v_c
      from public.community_members m join public.communities c on c.id = m.community_id and c.archived_at is null
     where m.user_id = new.user_id and m.status = 'active'
     order by m.activated_at nulls last, m.community_id limit 1;
  end if;
  -- rollout safety only, removed in Phase 5: an approved legacy account the backfill has not reached yet
  if v_c is null and not exists (select 1 from public.community_members where user_id = new.user_id)
     and exists (select 1 from public.profiles where id = new.user_id and approved) then
    v_c := public.default_community_id();
  end if;
  if v_c is null then raise exception 'Choose a community' using errcode = '42501'; end if;
  new.community_id := v_c; return new;
end $$;
create trigger fill_community_rides  before insert on public.rides           for each row execute function public.fill_request_community();
create trigger fill_community_favors before insert on public.favors          for each row execute function public.fill_request_community();
create trigger fill_community_posts  before insert on public.town_hall_posts for each row execute function public.fill_request_community();

-- Same job for xp_events, whose rows are written only by the three record_xp_* triggers. It exists from step 1,
-- so those writers keep working unedited; step 3 then makes them pass the community explicitly. It never raises:
-- a failure here would abort the ride insert, completion or review that fired the writer.
create or replace function public.fill_xp_event_community() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.community_id is not null then return new; end if;
  new.community_id := case
    when new.source_type in ('ride_requested','first_ride','ride_fulfilled')
      then (select r.community_id from public.rides r where r.id = new.source_id)
    when new.source_type in ('favor_requested','first_favor','favor_fulfilled')
      then (select f.community_id from public.favors f where f.id = new.source_id)
    when new.source_type = 'review_received'
      then (select coalesce(r.community_id, f.community_id) from public.reviews v
              left join public.rides r on r.id = v.ride_id left join public.favors f on f.id = v.favor_id
             where v.id = new.source_id)
  end;
  if new.community_id is null then
    new.community_id := coalesce((select p.primary_community_id from public.profiles p where p.id = new.user_id),
                                 public.default_community_id());
  end if;
  return new;
end $$;
create trigger fill_community_xp_events before insert on public.xp_events for each row execute function public.fill_xp_event_community();

-- INV-R3: whenever claimed_by becomes non-null, the claimer is an active member of community_id. Binds definer code too.
-- Created after backfill Part B, so no existing row has a null community when it first runs.
create or replace function public.guard_request_claim_membership() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.claimed_by is not null and new.claimed_by is distinct from old.claimed_by
     and not exists (select 1 from public.community_members m
                     join public.profiles p    on p.id = m.user_id
                     join public.communities c on c.id = m.community_id and c.archived_at is null
                     where m.community_id = new.community_id and m.user_id = new.claimed_by
                       and m.status = 'active' and p.is_banned = false) then
    raise exception 'Only members of this community can claim this request' using errcode = '42501';
  end if;
  return new;
end $$;
-- attached BEFORE UPDATE on rides and favors; guard_request_client_update (20261006_0001) gains
-- `or new.community_id is distinct from old.community_id` in its immutable set (INV-R1).
```

**The mirror.** One function recomputes both flags and the primary for one user; two triggers call it. It is the only writer of these three columns besides the legacy client writes it reconciles.

```sql
-- INV-M5:  approved             := the user has an active membership in a non-archived community
--          application_complete := the user has an active or a pending one
--          primary_community_id := kept while it is a live active membership, else the earliest one, else null
-- Every column is written only when it differs, so the mirror is re-entrant and cannot ping-pong.
create or replace function public.recompute_profile_membership_flags(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_active boolean; v_pending boolean; v_primary uuid; v_keep uuid;
begin
  select coalesce(bool_or(m.status = 'active'), false), coalesce(bool_or(m.status = 'pending'), false)
    into v_active, v_pending
    from public.community_members m join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.user_id = p_user and m.status in ('active','pending');
  select m.community_id into v_primary
    from public.community_members m join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.user_id = p_user and m.status = 'active' order by m.activated_at nulls last, m.community_id limit 1;
  select m.community_id into v_keep
    from public.profiles p
    join public.community_members m on m.user_id = p.id and m.community_id = p.primary_community_id and m.status = 'active'
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where p.id = p_user;
  perform set_config('naars.membership_mirror', '1', true);          -- lets protect_admin_fields pass this one statement
  update public.profiles p
     set approved = v_active,
         application_complete = (v_active or v_pending),
         primary_community_id = coalesce(v_keep, v_primary)
   where p.id = p_user
     and (p.approved is distinct from v_active
          or p.application_complete is distinct from (v_active or v_pending)
          or p.primary_community_id is distinct from coalesce(v_keep, v_primary));
  perform set_config('naars.membership_mirror', '', true);
end $$;
revoke all on function public.recompute_profile_membership_flags(uuid) from public, anon, authenticated;

create or replace function public.maintain_profile_membership_flags() returns trigger
language plpgsql security definer set search_path = '' as $$
begin perform public.recompute_profile_membership_flags(coalesce(new.user_id, old.user_id)); return null; end $$;
create trigger maintain_profile_membership_flags
  after insert or update of status or delete on public.community_members
  for each row execute function public.maintain_profile_membership_flags();

-- Archiving (or restoring) a community changes every member's effective membership without touching their rows.
create or replace function public.recompute_flags_on_archive() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in select user_id from public.community_members where community_id = new.id and status in ('active','pending') loop
    perform public.recompute_profile_membership_flags(r.user_id);
  end loop;
  return null;
end $$;
create trigger recompute_flags_on_archive after update of archived_at on public.communities
  for each row when (old.archived_at is distinct from new.archived_at) execute function public.recompute_flags_on_archive();
```

**`application_complete` is now mirrored in both directions** (v1 let it only rise). That is what routes a person whose last community ended. Whatever ended it (leave, removal, rejection, archive), they then hold no active and no pending membership, the mirror writes `approved = false, application_complete = false`, and the unchanged launch routing (`App/AppLaunchManager.swift:259-266`) sends them to `.needsApplication`: `CommunityOnboardingView` on the new build, the application form on the installed build. Someone waiting on a pending membership has `application_complete = true` and is `.pendingApproval`, exactly as today.

The two legacy bridges, both **state-based** (no `current_user` test, which is the owner inside a definer trigger):

```sql
-- Installed build's application submit: direct UPDATE profiles … application_complete = true
-- (Core/Services/ProfileService+AccountStatus.swift:38-49; create_signup_profile and the Apple path insert it false).
-- It becomes an application to the DEFAULT community, unless the person already has or is waiting on a membership
-- somewhere (then the flag was flipped by the mirror, not by the old form).
create or replace function public.legacy_application_to_membership() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not (new.application_complete and not old.application_complete) then return null; end if;
  if exists (select 1 from public.community_members m join public.communities c on c.id = m.community_id and c.archived_at is null
             where m.user_id = new.id and m.status in ('active','pending')) then return null; end if;
  insert into public.community_members (community_id, user_id, status, heard_about, join_reason)
  select c.id, new.id, 'pending', new.heard_about, new.join_reason from public.communities c where c.is_default and c.archived_at is null
  on conflict (community_id, user_id) do update
     set status = 'pending', heard_about = excluded.heard_about, join_reason = excluded.join_reason,
         ended_at = null, updated_at = now()
   where public.community_members.status = 'left';        -- a `removed` row is never reopened by the applicant (D4)
  return null;
end $$;
create trigger legacy_application_to_membership after update of application_complete on public.profiles
  for each row execute function public.legacy_application_to_membership();

-- Installed admin build's approve: direct UPDATE profiles SET approved = true (Core/Services/AdminService.swift:258-290).
-- Three cases, decided from state: (1) a pending DEFAULT-community row → activate it (today's flow);
-- (2) no membership row at all → create an active default membership (today's semantics for a never-applied
-- account a platform admin vouches for); (3) anything else (pending only in OTHER communities, or only ended rows)
-- → restore approved = false in the same transaction (S6). A no-op when an active membership already exists.
create or replace function public.sync_legacy_approval_to_membership() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_default uuid := public.default_community_id(); v_actor uuid := (select auth.uid());
begin
  if not (new.approved and not old.approved) then return null; end if;
  if exists (select 1 from public.community_members m join public.communities c on c.id = m.community_id and c.archived_at is null
             where m.user_id = new.id and m.status = 'active') then return null; end if;
  if exists (select 1 from public.community_members where user_id = new.id and community_id = v_default and status = 'pending') then
    update public.community_members set status = 'active', activated_at = now(), approved_by = v_actor, updated_at = now()
     where user_id = new.id and community_id = v_default and status = 'pending';
  elsif not exists (select 1 from public.community_members where user_id = new.id) then
    insert into public.community_members (community_id, user_id, status, activated_at, approved_by, heard_about, join_reason)
    values (v_default, new.id, 'active', now(), v_actor, new.heard_about, new.join_reason);
  else
    perform set_config('naars.membership_mirror', '1', true);
    update public.profiles set approved = false where id = new.id;
    perform set_config('naars.membership_mirror', '', true);
  end if;
  return null;
end $$;
-- Named with an "a_" prefix on purpose: Postgres fires same-event triggers in alphabetical order, and this one
-- must run BEFORE on_user_approved_notify so that case (1) has an active membership when the welcome push
-- is built and case (3) has already restored approved = false (no push).
create trigger a_sync_legacy_approval_to_membership after update of approved on public.profiles
  for each row execute function public.sync_legacy_approval_to_membership();
```

`notify_user_approved()` (the `on_user_approved_notify` trigger) gains two guards and community-named text. It sends nothing unless an active membership exists (so a declined legacy approve, case 3, is silent even if trigger order ever changes), and nothing when `current_setting('naars.suppress_approval_notice', true) = '1'`, which `create_community` and the instant branch of `redeem_community_invite` set for their own transaction: a person who just created or instantly joined a community is already looking at the app and must not be told "your account has been approved". Otherwise it stays the single producer of the first-approval `user_approved`, with the title "Welcome to <community>!".

Re-entrancy trace for case (1): the client UPDATE sets `approved = true` → `a_sync_legacy_approval_to_membership` activates the pending row → the nested mirror computes `approved = true`, finds it already true, and writes at most `primary_community_id` → no second firing with `old.approved = false` → `on_user_approved_notify` fires once with an active membership present. For case (3) the inner `update … approved = false` re-fires `a_sync_legacy_approval_to_membership` with `new.approved = false`, which returns at the first guard, and `on_user_approved_notify` then sees no active membership and sends nothing. Covered by the probes "approve through both paths in one transaction" and "approve a probe-community-only applicant".

**`protect_admin_fields`** (`20260717200001_20260717_0001_lockdown_messaging_definer_rpcs.sql:388-404`, invoker-rights) changes in three ways. (1) Its first line becomes `if current_setting('naars.membership_mirror', true) = '1' then return new; end if;`. The setting is transaction-local and is switched on and off around exactly one `UPDATE profiles` in three definer bodies (the mirror, case 3 of the approve bridge, `set_primary_community`); clients cannot set it (PostgREST exposes no `set_config`). v1's `current_user` escape is dropped: it would have exempted every definer function that writes `profiles`, including `create_signup_profile`, whose conflict branch could then have reset a member's `approved`. (2) The admin test is made explicit. Today it is `IF NOT (SELECT is_admin FROM profiles WHERE id = auth.uid())`, which is NULL, and so does not raise, both when there is no end-user JWT (migrations, the SQL editor, cron, the service role; this is what lets maintenance writes through today and must keep working) and when a JWT's user has no profile row (an accident, not a rule). It becomes: raise when `auth.uid() is not null and not coalesce((select is_admin …), false)`. v1's plain `coalesce(…, false)` would have blocked every maintenance write, including this migration's own backfill. (3) `primary_community_id` joins the guarded set, so a client `PATCH` of it raises for a non-admin; the insert-side trigger `protect_admin_fields_on_insert` (`20261005_0014`) also nulls it for non-admins. The probe must show that a direct client UPDATE of `approved`, `is_admin`, `is_banned` or `primary_community_id` by a non-admin raises, and that the mirror's write succeeds.

Other new triggers:

| Trigger | Table / event | Purpose |
|---|---|---|
| `derive_notification_community` | `notifications` BEFORE INSERT | when `community_id` is null: from `ride_id` / `favor_id` / `town_hall_post_id`, else from `review_id` through the reviewed request (INV-N1). Rows that carry only a conversation or a message stay null on purpose (messaging is not community-scoped). `create_notification`'s signature is unchanged; membership RPCs that create entity-less rows (`pending_approval`, `user_approved`, the `announcement` notices of 2.4) set `community_id` with a direct UPDATE on the returned id |
| `derive_report_community` | `reports` BEFORE INSERT | content reports: the target's community. Person reports: the one community the reporter and the reported person share, when there is exactly one (D27); otherwise null. Message reports and community reports: null, platform admins only (INV-P1). `submit_report`'s signature is unchanged |
| `guard_last_owner` | `community_members` BEFORE UPDATE / DELETE | raise when the row is the last active owner of a community that is neither archived nor marked `owner_vacant_since`, and the new state is not an active owner (INV-M3). **Created in the SQL-editor step 4 together with the new `delete_user_account`**, never before it: the live deletion RPC deletes the profile and the cascade would hit this guard |
| `guard_community_members_client_update` | `community_members` BEFORE UPDATE (invoker rights) | when `current_user in ('authenticated','anon')`, only `notifications_muted`, `muted_until`, `updated_at` may change (defense in depth beside the column grant; mirrors `guard_request_client_update`) |
| `notify_pending_membership` | `community_members` AFTER INSERT OR UPDATE OF status, when the new status is `pending` | `pending_approval` row + push (`data.user_id`, `data.community_id`, text per 2.4) to the community's active owner and admins; to the platform admins instead when it has none (D21). **`notify_pending_user` on `profiles` INSERT becomes a no-op body** in the adjacent MCP call (section 4), which also fixes the "admins notified before the application exists" defect (the auth-admin map §2.1) |
| `recompute_flags_on_archive` | `communities` AFTER UPDATE OF `archived_at` | above |
| `community_membership_events_append_only`, `set_updated_at_*` | housekeeping | |

### 3.4 Backend — RLS: exactly which policies change

Every change is `ALTER POLICY … USING / WITH CHECK` (the MCP applies those; no `DROP POLICY`) or a `CREATE POLICY` on a new table. Parent-scoped tables use the idiom `EXISTS (select 1 from public.rides r where r.id = ride_id)`: policy subqueries run with invoker rights, so the parent's own policy applies inside the subquery. "Stays" means the predicate is already row-, owner- or conversation-scoped.

| Table (policies) | Change | Stays |
|---|---|---|
| `rides` (8) | **3** — auth SELECT → `user_id = uid or (hidden_at is null and is_active_user(uid) and community_id = any((select my_community_ids())))`; INSERT → `uid = user_id and is_active_user(uid) and community_id = any((select my_community_ids()))` (filled by the trigger by then); claim UPDATE USING → `… and community_id = any((select my_community_ids()))` | anon SELECT (`false`), the owner/claimer UPDATEs, unclaim, DELETE |
| `favors` (8) | **3** — identical | identical |
| `town_hall_posts` (4) | **3** — auth SELECT → `user_id = uid or (hidden_at is null and community_id = any((select my_community_ids())))`; anon SELECT → `hidden_at is null and exists (select 1 from communities c where c.id = community_id and c.is_public and c.archived_at is null)`; INSERT → `uid = user_id and is_active_user(uid) and community_id = any((select my_community_ids()))` | DELETE (own or platform admin; community admin added in Phase 3) |
| `town_hall_comments` (5) | **3** — auth SELECT → `(hidden_at is null or user_id = uid) and exists (select 1 from town_hall_posts p where p.id = post_id)` (closes today's "any signed-in account reads every comment" gap); anon SELECT → `hidden_at is null and exists (…)`; INSERT → add the EXISTS | UPDATE / DELETE own |
| `town_hall_votes` (4) | **2** — auth SELECT `true` → `user_id = uid or exists (post or comment visible)`; INSERT → add the target-visible EXISTS | UPDATE / DELETE own |
| `town_hall_post_interactions` (3) | **1** — SELECT → `user_id = uid or exists (post visible)` | INSERT / DELETE own |
| `request_qa` (4) | **3** — SELECT → `exists (ride visible) or exists (favor visible)`; anon SELECT `true` → `exists (select 1 from guest_rides g where g.id = ride_id) or exists (… guest_favors …)`; INSERT → `uid = user_id and (parent visible)` | DELETE own |
| `ride_participants` / `favor_participants` (3 + 3) | **2 + 2** — SELECT → `exists (parent visible)`; INSERT → `(request owner) and added_by = uid and community_has_member((select community_id from rides where id = ride_id), user_id)` | DELETE owner |
| `reviews` (3) | **2** — SELECT → `reviewer_id = uid or fulfiller_id = uid or exists (parent request visible)`; anon SELECT `true` → `exists (guest view id)`. This scopes the **list of written reviews**; the headline numbers come from `get_profile_stats` (3.5), so a profile's rating does not depend on the viewer | INSERT (`20261006_0002`, already membership-implied) |
| `conversation_participants` (4) | **1** — INSERT WITH CHECK → `is_conversation_creator(conversation_id, uid) and shares_community_with(user_id)` (creator-relative on purpose, rule 7) | SELECT, UPDATE (column grant `20261005_0015`), DELETE |
| `geocoding_cache` (3) | **3** — SELECT, INSERT and UPDATE `true` → `is_active_user(uid)`. The rows hold reverse-geocoded street data for every pickup and destination the app has cost-estimated; today any signed-in account, approved or not, can read the whole table. The installed build reads and writes it only as an approved member and treats a refused read as "no cache" (`Core/Utilities/GeocodingCacheService.swift:175-200`). Rows carry no user or community, so a member of one community can still read place rows produced by another; that residue is in D16 and closes in Phase 5 | — |
| `communities` (new, 2) | auth SELECT `archived_at is null and (is_public or id = any((select my_community_ids())) or id = any((select my_admin_community_ids())) or exists (select 1 from community_members m where m.community_id = id and m.user_id = uid and m.status = 'pending'))` (an applicant sees what they applied to; a removed or departed member does not); **separate** anon SELECT `is_public and archived_at is null`; no client INSERT / UPDATE / DELETE (RPCs only). Platform admins read archived communities through `get_platform_communities` | — |
| `community_members` (new, 2) | SELECT `user_id = uid or community_id = any((select my_admin_community_ids()))`. **Members do not read each other's rows from the table**; the directory is `get_community_members`, which returns public fields to members and the application answers and inviter only to that community's admins. UPDATE own row, column grant `notifications_muted, muted_until, updated_at` (the `20261005_0015` mechanism) | — |
| `community_invites` (new, 1) | SELECT `created_by = uid or community_id = any((select my_admin_community_ids()))`; writes via RPC; redemption never reads the table | — |
| `community_invite_redemptions`, `community_membership_events` (new, 1 + 1) | SELECT `user_id = uid or community_id = any((select my_admin_community_ids()))`; no client writes | — |
| `community_invite_attempts` (new, 0) | RLS enabled, no policy: definer RPCs only | — |
| `reports` (4) | **none, in any phase.** The table holds `reporter_id`; `20261005_0022` removed the reported user's read for exactly that reason. Community admins read reports only through `get_community_reports` (3.5) | own SELECT; platform-admin policies; inert INSERT |
| everything else | — | `profiles` (7; admin policies stay platform-only), `conversations` (6), `messages` (2), `message_reactions` (4), `typing_indicators` (4), `notifications` (3), `notification_queue` (3), `push_tokens` (4), `invite_codes` (5, frozen), `blocked_users` (3), `completion_reminders` (4), `content_moderation_events` (1), `xp_events` (1), the storage policies |

Total in Phase 0: **28 altered, 7 new, 75 untouched** (plus 1 altered in Phase 3: the `town_hall_posts` DELETE policy).

Two views change in the same migration (CLAUDE.md: a column added to `rides` / `favors` goes into the guest views in the same change, or every guest decode fails), and `public_profiles` gains its predicate:

```sql
create or replace view public.guest_rides with (security_barrier = true, security_invoker = false) as
select r.id, r.user_id, r.type, r.date, r."time", ''::text as pickup, ''::text as destination, r.seats, r.notes, r.gift,
       r.status, r.claimed_by, r.reviewed, r.review_skipped, r.review_skipped_at, r.created_at, r.updated_at,
       r.estimated_cost, r.flight_normalized, r.timezone, r.hidden_at, r.hidden_by, r.hidden_reason, r.community_id
from public.rides r join public.communities c on c.id = r.community_id
where r.hidden_at is null and c.is_public and c.archived_at is null;
-- guest_favors: the same join (column list from 20261006_0005_guest_request_views.sql)

create or replace view public.public_profiles with (security_barrier = true, security_invoker = false) as
select p.id, p.name, p.avatar_url, p.car, p.approved, p.created_at, p.updated_at
from public.profiles p
where p.id = any ((select public.my_visible_profile_ids()))
   or ((select auth.uid()) is null and exists (select 1 from public.community_members m join public.communities c on c.id = m.community_id
        where m.user_id = p.id and m.status = 'active' and c.is_public and c.archived_at is null));
```

`auth.uid()` reads the JWT claims, so it evaluates to the caller even inside an owner-rights view; the probe must prove it (as the address cut-over probes did for `guest_rides`). The join is an inner join, which is why the guest views must be replaced only after backfill Part B (a ride with a null community would vanish from the guest list). The embedded `sender:public_profiles!messages_from_id_fkey` hydration keeps working through the conversation arm of `my_visible_profile_ids()`. A person who is no longer visible to the viewer (left the shared community, no shared thread) is simply absent from `public_profiles`; the client renders their old posts, comments and requests with "Former member" (section 3.7).

### 3.5 Backend — functions: edited, wrapped, new

**Rule for every function in this design:** never add a defaulted parameter to an existing name (it creates a second overload and the installed build's call fails with "function is not unique"). A community-scoped variant gets a new name; the old name keeps its signature and becomes a thin wrapper. One `CREATE OR REPLACE FUNCTION` per MCP call; start from the **live** body (`md5(prosrc)` recorded first).

**Who may delete an account (INV-M9).** `auth.users` and `profiles` rows are deleted by exactly two functions: `delete_user_account` (the user, for themselves) and `admin_reject_pending_user` (a platform admin, for an applicant to the default community who has no other membership row). No new RPC in this design deletes an account, and no community owner or admin can reach either function's delete.

Edited in place (signature unchanged):

| Function | Edit |
|---|---|
| `notify_new_ride()`, `notify_new_favor()` | loop `select m.user_id from community_members m join profiles p on p.id = m.user_id join communities c on c.id = m.community_id and c.archived_at is null where m.community_id = new.community_id and m.status = 'active' and not p.is_banned and m.user_id <> new.user_id and not m.notifications_muted and (m.muted_until is null or m.muted_until < now())` (INV-N2); add `'community_id', new.community_id` to the push `jsonb_build_object` (reaches `userInfo` through the `...data` spread, `supabase/functions/send-notification/index.ts:389-390`; old clients ignore it) |
| `notify_town_hall_post()` | same loop plus the existing `notify_town_hall` filter; `batch_key := 'town_hall_' || new.community_id || '_' || bucket` (batching is dead today, but the key must not merge communities if revived) |
| `guard_request_client_update()` | `community_id` joins the immutable set |
| `handle_new_review()` | the review post inherits `community_id` from the reviewed ride / favor |
| `record_xp_on_request_created()`, `record_xp_on_completion()`, `record_xp_on_review()` | write `xp_events.community_id` explicitly from `new.community_id` / the reviewed request (INV-X1). They already work unedited from step 1 because of `fill_xp_event_community`; this edit removes the dependence on the lookup |
| `protect_admin_fields()` | the transaction-local escape, the explicit admin test (no-JWT maintenance writes still pass), `primary_community_id` guarded (section 3.3) |
| `notify_pending_user()` | body becomes `return new` (the producer moves to `notify_pending_membership`) |
| `notify_user_approved()` | the active-membership guard, the suppression setting, community-named text (section 3.3) |
| `should_notify_user(p_user_id, p_type)` | **export the live body first** (the committed `20260403074116` lacks the `content_reported` / `content_hidden` arms; `20260403_0011:249-297` matches live). **Two arms change in Phase 0:** `pending_approval` and `content_reported` return `v_profile.is_admin or exists (an active owner / admin membership of p_user_id in a non-archived community)` instead of `is_admin` alone. Without this, `create_notification` returns NULL and `queue_push_notification` returns NULL for every community owner who is not a platform admin, so nobody in a new community would ever hear about an applicant. The gate only answers "may this person ever receive this type"; which admins receive a given row is decided by the producer's recipient query, so a Ballard applicant still never reaches a Seattle admin. `account_restricted` gets an arm returning true (it falls to `ELSE false` today) |
| `handle_new_report()` | Phase 0: a branch for community reports (preview = the community's name); recipients stay the platform admins, exactly as today. Phase 3: recipients become the platform admins **plus** the active owner and admins of `new.community_id`, under the reporter-privacy rules below. Auto-hide threshold unchanged (3 distinct reporters). In a community too small to reach it, the platform admins, who receive every report, are the backstop |
| `send_broadcast_notifications(p_title, p_body, p_type, p_pinned)` | becomes a wrapper: platform admin → `send_community_broadcast(default_community_id(), …)`; a community admin with exactly one admin community → that community; else raise. The 4-argument call from the installed admin build keeps working |
| `get_xp_leaderboard(start_date, end_date)`, `get_leaderboard_spotlights(start_date, end_date)`, both `get_leaderboard` overloads | thin wrappers over `get_community_leaderboard` / `get_community_spotlights`, resolving the caller's primary community when it is a live active membership, else the default community; anon resolves to the default community (public) |
| `get_user_badges(target_user_id)`, `get_user_stats(p_user_id)`, `is_user_approved(uuid)` | bodies unchanged, one gate added: they answer only when the target is the caller, is in `my_visible_profile_ids()`, or (for anon) is an active member of a public community; otherwise an empty array / an empty row / false. Same visibility rule as `public_profiles`, so they stop being cross-community oracles for any uuid |
| `create_signup_profile(…)` | the `ON CONFLICT (id) DO UPDATE` branch no longer assigns `approved` or `application_complete` (both are mirrored now; resetting them beside an existing membership would break INV-M5 until the next membership write) |
| `admin_dashboard_stats()`, `admin_stats_fulfilled`, `admin_stats_savings`, `admin_stats_active_rides` | Phase 3: wrappers over `get_community_stats(p_community_id, …)` resolving as above |
| `admin_get_reports(p_admin_id, p_status)`, `admin_moderate_content(…)` | **unchanged in every phase; platform admins only.** They return `reporter_id` and `reporter_name` (`20260403_0011:315-320`) and the installed admin screen shows them (`Features/Admin/Views/AdminReportsView.swift:376`). Community admins get separate RPCs below |
| `admin_reject_pending_user(p_user_id)` | **Caller check unchanged: platform admins only** (the NULL-safe `is_admin` test of `20261005_0025:33-37`). It is the installed build's compatibility path and nothing else. New body: if the target has a `pending` row in the **default** community, delete that row (event `rejected`); then, only if the target holds **no `community_members` row of any status in any community**, delete the profile and the `auth.users` row (today's behaviour for a Seattle-only applicant) and return `{success: true, deleted_user_id, rows_deleted: 1}`; otherwise keep the account and return `{success: true, rows_deleted: 0}` (the mirror has already recomputed the flags). If the target has no pending default-community row it changes nothing and returns `{success: false, error}`: "This person applied to a different community", "This account has not applied yet", or "This person is already a member". The installed build shows that text (`AdminService.swift:353-360`). The old `approved = true` refusal is replaced by this per-row rule: a person active in another community with a pending default-community row loses only that row. SQL-editor migration (it deletes from `auth.*`) |
| `delete_user_account(p_user_id)` | three additions before today's STEP 1, nothing removed. (A) For each non-archived community where the user is the only active owner: promote the longest-standing other active admin to owner; else, if other active members exist, set `owner_vacant_since = now()`; else set `archived_at = now()`. Each writes an event row and the notices of 2.4. This runs **before** the profile delete so `guard_last_owner` sees a second owner, a vacancy mark or an archive when the cascade removes the user's row. (B) `update community_invites set revoked_at = now() where created_by = p_user_id and revoked_at is null` (today's RPC deletes the user's `invite_codes`; a live code must not outlive its creator). (C) `update community_membership_events set reason = null where user_id = p_user_id` (free text written about the user; the FK then nulls `user_id`). STEP 1–7 are unchanged: they already unwind the user's claims and requests in every community, and memberships, redemptions and attempts cascade with the profile. SQL-editor migration; re-probe with a sole owner who has an admin, one who has only members, one who is alone, a co-owner, an admin and a member |
| `get_badge_counts(p_include_details, p_user_id)` | existing keys unchanged. Adds `pending_members_total` (pending rows in live communities where the caller's role is owner or admin, plus, for platform admins, in communities with no active owner or admin), so the Profile badge has one authoritative source; with `p_include_details`, `community_details: [{community_id, requests_total, community_total, bell_total}]` grouped on `notifications.community_id`; and `total` (`requests_total + messages_total + community_total`) as its own MCP call (D28) |
| `get_or_create_conversation(uuid[])`, `get_or_create_request_conversation(uuid, uuid, uuid)` | `REVOKE EXECUTE … FROM authenticated, anon` (neither is called by iOS; the second references columns that do not exist live). Closes the member-set side door around the `conversation_participants` policy |

New RPCs (SECURITY DEFINER, `set search_path = ''`, caller = `auth.uid()` checked inside, EXECUTE to `authenticated` only unless noted, jsonb `{success:false, error}` on refusal like `create_signup_profile`, every status / role transition writes a `community_membership_events` row). "Community admin" in the Who column means `is_community_admin(p_community_id)`, which is true for that community's owner and admins and for a platform admin:

| RPC | Who | Behaviour |
|---|---|---|
| `create_community(p_name, p_description, p_join_policy default 'approve') → {community_id}` | any signed-in unbanned account, approval not required | insert community + `owner` active membership; sets `naars.suppress_approval_notice` for the transaction; one `announcement` bell row to each platform admin (D25); 3 per account per day (advisory lock + count, the `submit_report` idiom); cap 10 owned communities (D14) |
| `update_community(p_community_id, p_name, p_description, p_join_policy, p_members_can_invite, p_timezone)` | owner | validated updates; `is_public` and `is_default` only by platform admins in v1 (D7) |
| `archive_community(p_community_id)` / `unarchive_community(p_community_id)` | owner or platform admin / platform admin only | the default community cannot be archived (INV-L1). Before setting `archived_at`: an `announcement` row to every member, and for each confirmed request an unclaimed-type row to the poster and the helper ("cancelled because <community> was archived"). Setting `archived_at` fires `recompute_flags_on_archive`. Content is kept and is invisible to everyone but platform admins until restored |
| `create_community_invite(p_community_id, p_max_uses, p_expires_at) → {code}` | admin, or any active member when `members_can_invite` | **Limits enforced here, not in the client.** A member who is not an admin always gets `max_uses = 1` and an expiry of at most 7 days, and may hold at most 10 live codes per community. An admin may set `max_uses` up to 1,000 and must set an expiry of at most 90 days; at most 25 live codes per community. The code is `NC` + 8 symbols drawn from `extensions.gen_random_bytes` with rejection sampling over the 31-symbol alphabet (never `random()`), retried on a unique violation |
| `revoke_community_invite(p_invite_id)` | admin or the creator | `revoked_at` |
| `validate_community_invite(p_code) → {valid, expired, requires_approval, community_name}` | **authenticated only** | read-only preview with no ids; `member_count` is added only for a public community. Every call writes a `community_invite_attempts` row; after 10 failed attempts in an hour the account is refused until the hour passes. With 31^8 codes that limit is the brute-force bound. A signed-out person's code waits in `PendingInviteStore` and is validated after sign-up, so there is no anonymous lookup to rate-limit |
| `redeem_community_invite(p_code, p_heard_about, p_join_reason) → {community_id, status}` | self | shares the attempt limit; not revoked / expired / exhausted; a platform-banned caller gets `{success:false, error:'restricted'}`; a `removed` row is refused (admin re-admits); a `left` row is reactivated; `invite` → `active` (sets the suppression setting), `approve` → `pending`; `use_count++`, redemption row, `invited_by`, `invite_id` |
| `request_to_join_community(p_community_id, p_heard_about, p_join_reason)` | self | community must be `is_public`; banned caller refused as above; creates / flips to `pending`; copies the answers to `profiles.heard_about / join_reason` only for the default community (the installed admin build's detail screen reads them there); refused within 7 days of a `rejected` event |
| `approve_community_member(p_community_id, p_user_id)` / `reject_community_member(…)` | community admin | **approve:** a platform-banned target is refused with `error:'restricted'` (no ban detail is revealed); pending → active. If the person already had an active membership elsewhere, the RPC itself creates the community-scoped `user_approved` row and push of 2.4; otherwise the mirror flips `approved` and `notify_user_approved` sends the welcome. **reject:** delete the pending row, **never the account**; the mirror then routes a person with nothing left to onboarding; `user_rejected` from Phase 3 |
| `remove_community_member(p_community_id, p_user_id, p_reason)` / `readmit_community_member(…)` | community admin; an admin / owner target only by an owner | `unwind_member_requests`, role back to `member`, status `removed` / back to `active`; `account_restricted` from Phase 3 |
| `set_member_role(p_community_id, p_user_id, p_role)` / `transfer_community_ownership(p_community_id, p_user_id)` | owner | last-owner guard; the previous owner becomes admin on transfer |
| `claim_community_ownership(p_community_id)` | any active member, only while `owner_vacant_since` is set | advisory lock; the caller becomes owner; the mark is cleared; `announcement` rows to members (D23) |
| `leave_community(p_community_id) → {reopened, removed, cancelled}` | self | refused for the last owner unless they are the only active member (then the community is archived); `unwind_member_requests`; role back to `member` (the CHECK requires it), status `left` |
| `set_primary_community(p_community_id)` | self | must be a live active membership; the only client route to `profiles.primary_community_id` |
| `get_my_memberships() → rows (community_id, name, description, role, status, is_primary, join_policy, is_public, is_default, can_invite, owner_vacant, member_count, pending_count, notifications_muted, muted_until, joined_at, activated_at)` | self; works while `approved = false` (the waiting screen calls it) | one round trip for `CommunityContext`; `pending_count` only for admins; archived communities are left out |
| `get_community_members(p_community_id, p_status default 'active', p_limit, p_offset) → rows (id, name, avatar_url, car, role, status, joined_at, activated_at, heard_about, join_reason, invited_by_name, removal_reason)` | member; `pending` / `removed` rows only for admins of it | the directory and the admin lists. `heard_about`, `join_reason`, `invited_by_name` and `removal_reason` are **null unless the caller is an admin of that community**. **No email, no phone, no ban fields for anyone** (D12); platform admins keep `profiles` through `profiles_select_admin`. For a non-admin caller the list leaves out people blocked in either direction; admin lists are not block-filtered |
| `search_community_members(p_query, p_community_id default null, p_limit default 20) → setof public_profiles` | member | null = union of the caller's communities; block-filtered both ways on the server; replaces `ProfileService.searchPublicProfiles` for the pickers |
| `get_community_leaderboard(p_community_id, start_date, end_date)` | member, or anyone when the community is public | the existing body with three scoped pieces, not one: `xe.community_id = p_community_id` on the `xp_events` scan; `r.community_id = p_community_id` on the streak-bonus and savings subqueries over `rides` / `favors`; and `join community_members m on m.user_id = p.id and m.community_id = p_community_id and m.status = 'active'` instead of `profiles.approved`. The `badges` column stays per person (D5) |
| `get_community_spotlights(p_community_id, start_date, end_date)` | same | this body never reads `xp_events`. Every CTE over `rides` / `favors` (`fulfilled_weeks` for the streak, rising star, top requester), in both the SELECT and the `_claimed_users` de-dup INSERT of each category, adds `r.community_id = p_community_id` / `f.community_id = p_community_id`; the `profiles.approved` filters become the active-membership join |
| `get_profile_stats(p_user_id) → {avg_rating, review_count, fulfilled_count}` | the same visibility rule as `public_profiles` | **per person, over every community** (rule 8). `fulfilled_count` uses the client's definition: rides and favors with `claimed_by = p_user_id` and status confirmed or completed (`Core/Services/ProfileService.swift:451-467`). Replaces the client's three direct reads for the headline numbers |
| `send_community_broadcast(p_community_id, p_title, p_body, p_pinned)` | community admin | announcement post with `community_id`; one `notifications` row per active member who has not muted the community (self excluded; through `create_notification` so `community_id` derives); at most 3 a day per community (D14); the Town Hall push the post triggers already honours `notify_town_hall` and the mute. A dedicated `broadcast` push is D13 (Phase 4) and will honour the mute too |
| `report_community(p_community_id default null, p_code default null, p_report_type, p_description)` | any signed-in account that can see the community, or that holds a valid code for it | inserts a report with `reported_community_id`; `community_id` stays null so it reaches platform admins only; the limits of `submit_report` apply (one pending report per target, 20 an hour) |
| `get_platform_communities()` | platform admin | every community including archived ones: name, description, creator, created, member and pending counts, `owner_vacant`, `archived_at`, open report count |
| `get_community_reports(p_community_id, p_status)` (Phase 3) | community admin | the rows of `admin_get_reports` filtered by community, **without `reporter_id` and `reporter_name`**, and without any report whose reported person or content author is the caller |
| `moderate_community_content(p_report_id, p_action, p_reason)` (Phase 3) | community admin of the report's community | hide / unhide / dismiss for posts, comments, rides and favors of that community; dismiss only for a person report (removal is `remove_community_member`); refused when the caller is the reported person or the author |
| `get_community_stats(p_community_id)` and the three breakdowns (Phase 3) | community admin | the existing stat bodies filtered by community |
| `unwind_member_requests(p_community_id, p_user_id)` | internal, service_role only | scoped to one community: (1) the user's claims on confirmed requests are reopened and each poster gets the existing unclaimed notice; (2) the user's own `open` requests are deleted; (3) the user's own `confirmed` requests are deleted after the helper gets the existing "cancelled because the poster left" notice; `completed` requests are kept; (4) completion reminders for the affected requests are deleted; (5) the user's live invite codes for that community are revoked. Used by leave and remove. SQL-editor migration with the lifecycle functions |

**Reporter privacy for community admins (INV-P2), effective when Phase 3 extends the recipients.** `20261005_0022` exists because exposing `reporter_id` "exposes the reporter to retaliation and undermines the reporting pathway". A community admin is an ordinary user who can remove members, so the rule carries over in four parts: (1) a community-admin recipient's `content_reported` row is created with `source_user_id = NULL` (platform admins keep today's value); (2) the recipient set never contains the reporter, the reported user or the content's author; (3) when the reported user or author is an owner or admin of that community, **no** admin of that community is notified and the report does not appear in `get_community_reports` for any of them; the platform admins handle it; (4) `reports` gets no table policy for community admins. The report sheet tells the reporter: "Community admins do not see who reported. Platform moderators do."

Unchanged on purpose: `create_notification`, `queue_push_notification`, `mark_request_notifications_read`, every messaging RPC, `send-notification` (recipients come from rows; `community_id` reaches APNs through `...data`), `_shared/badges.ts` (it already returns `data.total` when the RPC provides it, `supabase/functions/_shared/badges.ts:20-22`), the notification type registry (33 types), `complete_request`, `handle_completion_response`, `process_completion_reminders`, `expire_past_open_requests`, `submit_report`, `admin_get_reports`, `admin_moderate_content`, `send_approval_notification` (no caller).

### 3.6 Invariants (each with its enforcement point)

- **INV-M1** one `community_members` row per (community, user) — PK; rejoin flips `status`.
- **INV-M2** `role <> 'member'` implies `status = 'active'` — CHECK; leave and remove reset the role.
- **INV-M3** a live community has ≥ 1 active owner, or is marked `owner_vacant_since` — `guard_last_owner`; `leave_community` and `delete_user_account` hand over, mark or archive first.
- **INV-M4** role and status change only through the RPCs — no client write policy; `guard_community_members_client_update` as defense in depth.
- **INV-M5** `profiles.approved` = has an active membership in a live community; `application_complete` = has an active or pending one; `primary_community_id` is null or a live active membership and is not client-writable — `recompute_profile_membership_flags` (membership and archive triggers), `protect_admin_fields`, `set_primary_community`; consumers that read the primary re-validate it.
- **INV-M6** a platform-banned user has no effective membership and cannot acquire one — `my_community_ids()` joins `is_banned = false`; fan-out loops too; join, redeem and approve refuse.
- **INV-M7** a `removed` user cannot return by themselves — `redeem_community_invite`, the legacy application bridge.
- **INV-M8** every transition writes one event row — inside the RPCs and bridges; append-only trigger.
- **INV-M9** an account is deleted only by its owner, or by a platform admin rejecting a default-community applicant with no other membership row — the two functions named in 3.5; probes for a community admin calling each.
- **INV-A1** an archived community is in nobody's `my_community_ids()` / non-platform `my_admin_community_ids()`, and archiving re-evaluates every member's flags — the helper joins; `recompute_flags_on_archive`.
- **INV-R1** `community_id` is immutable on rides / favors / posts, and non-null from step 6 — `guard_request_client_update`; the fill triggers; definer RPCs never write it.
- **INV-R2** the poster is an active member at insert — INSERT policies; `fill_request_community` for old clients.
- **INV-R3** a claimer is an active member of the request's community — claim policy **and** `guard_request_claim_membership` (binds definer code).
- **INV-R4 / R5** participants and Q&A authors are members of the request's community — INSERT policies with `community_has_member` / parent EXISTS.
- **INV-R6** membership lapse by leave or removal reopens the user's claims, removes their open requests and cancels their claimed ones in that community — `unwind_member_requests`. Account deletion does the same everywhere through its existing STEP 1–7.
- **INV-T1** posts carry the community; comments, votes and interactions inherit through `post_id` — policies with parent EXISTS.
- **INV-C1** communities are archived, never deleted while content references them — `ON DELETE RESTRICT`.
- **INV-I1** a non-admin's invite is single-use and expires within 7 days; codes come from a CSPRNG; invites die with their creator's membership or account — `create_community_invite`, `unwind_member_requests`, `delete_user_account`.
- **INV-N1** `notifications.community_id` equals the entity's community when a request, post or review id is present — `derive_notification_community`.
- **INV-N2** fan-out never crosses a community and skips muted members — the three loops and `send_community_broadcast`.
- **INV-N3** an application is announced to that community's owner and admins (platform admins only when it has none); a report always reaches the platform admins and, from Phase 3, that community's admins under INV-P2 — `notify_pending_membership`, `handle_new_report`, and the `should_notify_user` arms that let those rows through.
- **INV-P1** `reports.community_id` is the target content's community, or the single shared community for a person report — `derive_report_community`.
- **INV-P2** a community admin never learns who filed a report and never receives or sees a report about themselves — the rules in 3.5.
- **INV-X1** `xp_events.community_id` is the request's / review's community; per-community leaderboards read only that community's rows, reputation RPCs read all — the fill trigger and the XP writers.
- **INV-L1** exactly one `is_default` community exists while any pre-community build is supported, and it is never archived — partial unique index; `archive_community`.
- **INV-D1** a child table added later must scope through its parent with the EXISTS idiom — documented in `SECURITY.md` §2 and CLAUDE.md's database contract (process invariant).

### 3.7 Client (iOS) — models, SwiftData, services, sync, coordinator, navigation, notifications

**New types.** `Core/Models/Community.swift` (`Community`, `CommunityMembership`, `CommunityRole`, `MembershipStatus`, `CommunityInvite`); `Core/Services/CommunityService.swift` behind `Core/Protocols/CommunityServiceProtocol.swift` (new service → protocol, Architecture rule 5) wrapping the RPCs in 3.5; `App/CommunityContext.swift` — `@Observable @MainActor` singleton beside `NavigationCoordinator` (State rule 2 allows it for Core/UI state holders) holding `memberships`, `communityTabId: UUID?` (the Community tab's community), `requestsScope: .all | .community(UUID)`, `lastPostedCommunityId`, `hasMultipleCommunities`, `name(for:)`, `isAdmin(of:)`, `isPlatformAdmin` (from `AppState.currentUser?.isAdmin`). Not stored in SwiftData (a handful of rows). `PendingInviteStore` (UserDefaults `community.pendingInviteCode`, device-level, cleared on redemption or after 7 days).

**How `CommunityContext` is loaded, and what it is before that.**

- *Persistence.* `communityTabId`, `requestsScope` and `lastPostedCommunityId` are written to `community.tab.<userId>`, `community.requestsScope.<userId>`, `community.lastPosted.<userId>` on every assignment.
- *Restore (synchronous).* `CommunityContext.restore(for: userId)` reads those three keys. It is called in `AppLaunchManager.performDeferredLoading` on the line after `authService.currentUserId` is set and **before** `startDeferredSyncEnginesIfNeeded` (`App/AppLaunchManager.swift:291-295`), so the launch Town Hall sync reads the stored community. It does no network and cannot fail.
- *Membership load (asynchronous, never on the launch path).* `refreshMemberships()` calls `get_my_memberships` right after `startDeferredSyncEnginesIfNeeded`, inside the already-detached deferred task. Launch routing and hydration never wait for it. On failure it logs and keeps what it had. On success, if `communityTabId` is nil or no longer an active membership it becomes the membership flagged `is_primary` and is persisted; a narrow or last-posted value that is no longer an active membership is cleared.
- *Later refreshes.* App foreground (same place `recheckBanStatus` is called, throttled to once per 30 s); after the user's own create / join / leave / take-over; and on receipt of a `user_approved`, `user_rejected`, `account_restricted` or `pending_approval` push, in `PushNotificationService.handlePushReceived` beside the existing domain invalidation. This is not a coordinator domain and touches no engine.
- *When it is nil.* On the first launch after the Phase 1 update, after a fresh sign-in, or when the first membership load fails, `communityTabId` is nil until the load succeeds. **Nil means "no community filter" everywhere**: Town Hall fetches and reads without a community term (RLS still returns only the person's communities, which is exactly one for every member until Phase 2), the leaderboard calls the old wrapper RPC (the server resolves the primary), and a new post omits `community_id` (the fill trigger resolves the primary). Nothing shows an empty state because the context is not loaded.
- *Sign-out.* `resetForSignOut()` is called from `AuthService.clearPerAccountLocalState()` (`Core/Services/AuthService.swift:652-672`).

**The mandatory trio** (the client-data map §15.1; everything optional so the unversioned lightweight migration and old-row decoding are safe, §15.5):

- `Ride.communityId: UUID?` + `CodingKeys` `community_id` (`Core/Models/Ride.swift:40-64`, decoded with `decodeIfPresent`); `Favor.communityId`; `TownHallPost.communityId` (plus its hand-written `encode`, `Core/Models/TownHallPost.swift:75-90`, so `createPost` sends it); `AppNotification.communityId` (`Core/Models/AppNotification.swift:203-236`).
- `SDRide.communityId: UUID?`, `SDFavor.communityId`, `SDTownHallPost.communityId`, `SDNotification.communityId` (`Core/Storage/SDModels.swift`) — `UUID?` with no default is a lightweight-migratable addition; a non-optional property without an inline default makes `createModelContainer` throw and the app deletes the store, losing the durable send queue (`App/NaarsCarsApp.swift:48-56, 104-116`). **Rows cached by the previous build get `communityId == nil` in this migration**; the reads below treat nil as "unknown, show it".
- `Core/Storage/BackgroundSyncActor.swift`: the six ride field sites (66-96, 347-377, 718-733, 845-860, 478-504, 538-567), the six favor sites (130-158, 401-429, 754-770, 887-903, 506-531, 570-598), the post sites (933-942, 1033-1042, 657-674), the notification sites (201-216, 455-470, 790-801, 601-614); the `TownHallRepository` twins (`mapToSDTownHallPost` 199-218, `mapToTownHallPost` 169-197, `updateIfChanged` 222-239); `RequestFilterManager`'s reverse map (`Features/Requests/ViewModels/RequestFilterManager.swift:41-68, 76-101`); `NotificationGroupingManager.getFilteredNotifications`. Because `communityId` is compared in `updateIfChanged` / `updateSDPostIfChanged`, the first sync after the update rewrites every cached row's community.
- `Conversation`, `Message`, `MessagingMapper.parseMessage`: **untouched** (messages carry no community).

**Fetch scoping — explicit parameters, RLS remains the boundary.**

- *Requests (merged):* `DashboardSyncEngine.performFullSync` keeps calling `fetchRides()` / `fetchFavors()` unfiltered (`Core/Storage/DashboardSyncEngine.swift:89-91`); RLS returns the union; the store holds the union; the reconciliation deletes (`BackgroundSyncActor.swift:738-741, 775-778`) stay correct. `RequestFilterManager.fetchFilteredRides / Favors` (`:157-205`) and `computeFilterBadgeCounts` (`:212-213`) gain an optional `communityId == scope` term only when `requestsScope` is narrowed. Guests already narrow server-side. `performTargetedSync(entityId:)` is unchanged.
- *Town Hall (per community).* Four pieces, each with its nil case:
  1. **Service.** `TownHallService.fetchPostsPage(limit:offset:communityId: UUID?)` adds `.eq("community_id", …)` only when the id is non-nil (`Core/Services/TownHallService.swift:43-50`).
  2. **Engine.** `TownHallSyncEngine.performFullSync` (`Core/Storage/TownHallSyncEngine.swift:54-70`) reads `CommunityContext.shared.communityTabId` once at fetch start (the way `DashboardSyncEngine` reads `AuthService.shared.currentUserId`, which is why the restore above runs first), passes it to the fetch, keeps "prune every local post absent from the page" unchanged, and adds the scope it fetched to the `.townHallPostsDidSync` notification's `userInfo`. Targeted upserts and repository writes post the notification without a scope, as today. The store therefore holds the first page of whichever scope was synced last.
  3. **Repository.** `TownHallRepository.getPosts(communityId: UUID?)` (`Core/Storage/TownHallRepository.swift:25-32`): nil → today's query, no predicate; non-nil → `communityId == id || communityId == nil`. The nil arm keeps rows cached by the previous build visible until the first sync rewrites them. On an installed-build device whose owner joined a second community from another device, those unlabelled rows can include the other community's posts for the seconds before that sync; they are the person's own communities' posts and the sync then prunes them.
  4. **ViewModel.** `TownHallFeedViewModel` passes the active community to `getPosts`, to the enrichment `fetchPostsPage` (`Features/TownHall/ViewModels/TownHallFeedViewModel.swift:283`) and to `loadMore`. Its repository sink (`bindPosts`, `:220-227`) applies a full-sync emission only when the synced scope equals the active community (nil equals nil) and applies unscoped emissions as today; that is what stops a sync that was already running for community A from blanking community B's list through `keepingPagedPosts`' "an empty store empties the list" rule.

  **Switching.** The title menu sets `CommunityContext.communityTabId`. `TownHallFeedView` observes it and calls `viewModel.activeCommunityDidChange()`, which also runs when the launch membership load resolves nil to a community. For a real switch the ViewModel bumps a generation counter, clears `posts`, resets paging, shows the skeleton, and calls `refreshFromNetwork(trigger: "communitySwitch")`, which already runs the scoped enrichment fetch concurrently with `RefreshCoordinator.forceFullRefreshAndWait(.townHall, …)` (`:276-300`). The enrichment page is the last write, so the screen shows the new community after one round trip. Results that return after a newer switch are dropped by the generation check.

  **When the coordinator joins a sync that started for the previous community.** `forceFullRefreshAndWait` joins in flight and never cancels, and its result does not say that it joined (`Core/Services/RefreshCoordinator.swift:136-161`). The ViewModel does not need it to: after the awaited refresh it reads `repository.getPosts(communityId: active)` (a sanctioned repository read) and, if the store does not contain every post id of the enrichment page, issues one more `forceFullRefreshAndWait(.townHall, trigger: "communitySwitch:retry")`, at most twice. The previous task has finished by then, so the retry starts a sync that reads the new community. The screen is right after the first round trip; the store, which is only the offline cache, is right after the retry. No `reset()`, no `invalidate` from a ViewModel, no store wipe, no engine call, no change to `RefreshCoordinator` or to its result contract.

  **Launch.** The launch sync uses the restored community, or no filter when none is stored. `loadPosts()` paints the cache and then always refreshes from the network (`:67-91`), so opening the Community tab reconciles whatever the launch sync left. Nothing else is needed, and in particular `AppLaunchManager` issues no corrective refresh.
- *Leaderboard:* `LeaderboardService` calls `get_community_leaderboard` / `get_community_spotlights` with `communityTabId`, or the two old wrapper RPCs when it is nil; the 15-minute cache key includes the community (`Core/Services/LeaderboardService.swift:102-170`).
- *Member search:* `UserSearchViewModel` → `search_community_members(query, communityId:)` (`Features/Messaging/ViewModels/UserSearchViewModel.swift`); the create-form participants picker passes the chosen community; "new message" passes nil (union).
- *Conversations, messages:* unchanged.
- *Badges:* `BadgeCountsPayload` (`Core/Services/BadgeCountManager.swift:322-329`) gains optional `pendingMembersTotal`, `communityDetails` and `total`.

**Reputation on profiles.** `ProfileService.calculateAverageRating(userId:)` and `fetchFulfilledCount(userId:)` (`Core/Services/ProfileService.swift:380-396, 451-467`) call `get_profile_stats` instead of reading `reviews`, `rides` and `favors` directly, so `PublicProfileViewModel` (`:62-64`), `MyProfileViewModel` (`:65-67`) and the stats card show the same numbers to every viewer. `fetchReviews(forUserId:)` (`:311-318`) stays a direct, RLS-scoped read; when `review_count` exceeds the rows returned, `PublicProfileView` and `AllReviewsView` add "N more reviews in other communities". Reviewer names on one's own profile resolve through the review arm of `my_visible_profile_ids()`; a request title that can no longer be read (a community since left) is nil, which the row already handles. These three call sites are Phase 1 work.

**`RefreshCoordinator`:** untouched. Domains, state machine, timers, `reset()` (`Core/Services/RefreshCoordinator.swift:201-215`) and the sign-out path are not modified; the only new calls are the sanctioned `forceFullRefreshAndWait(.townHall, …)` for a community switch and `forceFullRefreshAndWait(.dashboard, trigger: "leftCommunity")` from the My communities ViewModel after a successful leave, so that community's requests drop out of the merged feed at once.

**Launch and auth state.** `AuthState` keeps its seven cases and `AppLaunchManager.checkAccountStatus` (`App/AppLaunchManager.swift:243-281`) is untouched; the two mirrored flags keep driving it. What changes:

- `.needsApplication` → `CommunityOnboardingView` replaces `ApplicationFieldsView` as that state's root (`App/ContentView.swift:38-79`, one line; Phase 2). With the two-way mirror this is where everyone with no community lands: newcomers, and people whose last community ended.
- `.pendingApproval` → `PendingApprovalView` (Phase 2) calls `get_my_memberships` itself on appear and on each 30-second poll tick, since `CommunityContext` is loaded only on the authenticated path. It lists every pending community by name ("Waiting for Ballard Neighbors to approve you"), keeps today's generic copy when the call fails, and offers **Join another community** and **Create your own**. When the call succeeds and shows neither a pending nor an active membership (a rejection, or a legacy state) it runs `performCriticalLaunch()`, which now routes to onboarding.
- On approval the waiting screen runs `performCriticalLaunch()` instead of setting `state` directly (`Features/Authentication/Views/PendingApprovalView.swift:255-278` skips `performDeferredLoading` today, open finding gap-3-5). Phase 1; a fragile-system-5 change.
- **A running session that loses its last community.** `recheckBanStatus()` (`App/AppLaunchManager.swift:194-206`) is generalised to `recheckAccountStatus()`: on foreground, when the state is `.ready(.authenticated)`, it re-reads the three flags and moves to `.banned` as today, or to `.needsApplication` / `.pendingApproval` when the profile now says so, setting `state` directly without a `.checkingAuth` hop, as the ban path already does. It is also called after the user's own successful leave and after a membership refresh that returns zero active memberships. **It must act only on a successful read.** `checkAccountStatus` returns `.needsApplication` when the query fails ("safer default" at launch); the re-check uses a throwing variant and does nothing on error, otherwise an offline foreground would eject every member to onboarding. Phase 1; traced through `AppLaunchManagerTests` (successful read with each flag combination; failed read is a no-op). The installed build has no such re-check: its session stays in an app that reads nothing until the next launch.
- **`.enterApp` no longer relaunches a running session.** `DeepLinkParser` maps `user_approved` to `.enterApp` (`Core/Utilities/DeepLinkParser.swift:124-125`) and `AppDelegate` answers it with `performCriticalLaunch()` (`App/AppDelegate.swift:386-390`), which sets `.checkingAuth` and swaps `MainTabView` out for `LoadingView`. That is right for the only recipient today, a person on the waiting screen. This design also sends `user_approved` to a signed-in member approved into a further community, so the handler gets a guard (Phase 1): when the state is already `.ready(.authenticated)` it refreshes `CommunityContext` and sets `pendingIntent` (`.dashboard`; `.myCommunities` from Phase 2) instead of relaunching; in every other state it behaves as today. An installed-build device of the same person still relaunches on that tap: a loading flash and a return to the first tab, the same thing a re-tap of an old approval push does today (D22).
- A person with one active membership and a second pending one is `.authenticated`; the pending row shows in My communities.

**Create forms.** A first `Section` "Post to" with a system `Picker` of active memberships above `ride_create_section_date_time` (`Features/Rides/Views/CreateRideView.swift:69`) / `favor_create_section_title_description` (`Features/Favors/Views/CreateFavorView.swift:69`), present only when `hasMultipleCommunities`. Default: the Requests narrow when one is set, else `communityTabId`, else `lastPostedCommunityId`, else the primary (D24). The primary button's title is "Post to <community>" when the section is shown. The choice is part of `hasRequiredFields` (`Features/Rides/ViewModels/CreateRideViewModel.swift:53-56`). `createRide(… communityId:)` / `createFavor` / `createPost` send `community_id` (`Core/Services/RideService.swift:140-160`, `FavorService.swift:142-166`, `TownHallService.swift:136-190`); `updateRide` / `updateFavor` never send it. Edit screens show the community as a read-only `NaarsChip` in the header. A Town Hall post goes to the Community tab's community.

**Cards and chips.** `RideCard` / `FavorCard` show a neutral `NaarsChip(text: context.name(for: communityId), tint: nil)` next to the status chip when `hasMultipleCommunities && requestsScope == .all` (`UI/Components/Cards/RideCard.swift:128-130`); detail headers likewise; `PastRequestsView` always chips; bell rows chip when `SDNotification.communityId` is set and the person has two or more memberships. No new color tokens. Wherever an author, poster, helper or reviewer profile is missing because the person is no longer visible to the viewer, the row shows the localized "Former member" with the placeholder avatar; Phase 1 checks each such row (post card, comment, request card and detail, review row) with a nil profile.

**Switchers and the tab badge.** Requests: an optional title menu (`toolbarTitleMenu`) listing *All communities* and each community, with a `navigationSubtitle` showing the narrow; the trailing `BellButton` + `+` menu are unchanged (`Features/Requests/Views/RequestsDashboardView.swift:35-62`). Community tab: the nav title becomes the active community's name with a title menu (`Features/Community/Views/CommunityTabView.swift:44-66`); with one membership the title stays `community_title` and there is no menu. The two selections are independent (D6). From Phase 2 the Community title menu shows each other community's unread Town Hall count from `community_details`, and `clearCommunityBadge` (`Core/Services/BadgeCountManager.swift:238-266`) marks read only the Town Hall rows whose `communityId` is the visible community or nil, so opening the tab no longer silently clears communities the person did not look at.

**Navigation.**

- *Town Hall targets carry a community when one is known.* `DeepLinkParser` reads `userInfo["community_id"]` for `town_hall_post`, `town_hall_comment`, `town_hall_reaction` and for the `content_hidden` case that carries a `town_hall_post_id` (`Core/Utilities/DeepLinkParser.swift:72-84, 114-117`). `DeepLink.townHallPostComments` / `.townHallPostHighlight` and `NavigationIntent.townHallPost` each gain `communityId: UUID?`. The default value keeps every construction site compiling, **but a pattern that binds the associated values does not**: `App/NavigationCoordinator.swift:183-187, 248-249, 399` and `Features/TownHall/Views/TownHallFeedView.swift:174` are edits (`CommunityTabView.swift:61` matches without bindings and is not). In-app taps carry it too: `NotificationIntent.openTownHallPost` gains `communityId`, filled from the bell row's `communityId` in `NotificationNavigationRouter` (the announcement-with-post case at `:78-80`, the post / comment / reaction cases, and `content_hidden`), and `applyNotificationIntent` (`App/NavigationCoordinator.swift:301-341`) passes it on.
- *One owner for the switch.* `CommunityTabView`'s `.onChange` keeps doing only what it does today, selecting the Town Hall segment. `TownHallFeedView`'s `.onChange(of: pendingIntent, initial: true)` hands the target to `viewModel.open(_ target:)` and nils the intent in the same pass, so the intent is still consumed exactly once and there is no ordering question between the two views. The ViewModel holds the target (`pendingNavigation`) and: resolves the community from the target, or, when it is absent (an old push, a row with no community), by fetching the post by id; if the post cannot be read it shows "This post is no longer available" and stops; if the community differs from the active one it sets `CommunityContext.communityTabId` and awaits the switch refresh above; then, if the post is in `posts`, it publishes the scroll / highlight / open-comments action the view performs today, and otherwise opens the comments sheet, which loads by id. One switch, one refresh, no loop.
- *Applicants.* From Phase 2, `pending_approval` with a `community_id` parses to `DeepLink.pendingMembers(communityId:)` → `NavigationIntent.pendingMembers(UUID)` (Profile tab; added to `intentIsAdminOnly` so guests drop it), consumed by `MyProfileView.applyProfileIntent`, which pushes `PendingMembersView(communityId:)`. Without the key it stays `.pendingUsers`. The bell-row path does the same from `notification.communityId` (`NotificationNavigationRouter.swift:128-129`). `PendingMembersView` shows an inline "You are not an admin of this community" state rather than an error screen if the server refuses. `pending_approval` now has two audiences (platform admins, community admins) and two routes; `affectedDomains` stays `[.dashboard]` and the badge refresh every push triggers picks up `pending_members_total`.
- *Reports.* From Phase 3, `content_reported` with a `community_id`, for a person who is not a platform admin, routes to that community's reports list; platform admins keep `.adminReports`.
- Everything else — `pendingIntent` only, no direct navigation from push handlers, the `initial: true` replay rule, `handlePushReceived` — is unchanged. `.joinCommunity(code)` and the Universal Link arrive in Phase 4.

**Notifications.** Phase 1 ships three hardening changes.

1. `NotificationType` decodes unknown raw values as `.other` (custom `init(from:)`), so a later server type cannot leave `bell_total` counting rows the lenient fetch drops (`Core/Services/NotificationService.swift:134-158`).
2. `entityIdKey` returns `town_hall_post_id` for the three Town Hall types (`Core/Models/AppNotification.swift:184-199`; the pinned test `NotificationTypeDomainMappingTests.testEntityIdKeyPresent` asserts the wrong key today and is corrected with it). **This changes behaviour on the push → coordinator seam**: today the key never matches, so `PushNotificationService.handlePushReceived` (`:793-823`) falls to `invalidate([.townHall])`; after the fix it calls `performTargetedRefresh(.townHall, entityId:)`, a single-post fetch and upsert.
3. So the single-post fetch must not fail closed. `TownHallService.fetchPost(id:)` uses `.single()` (`:91-99`), which throws on zero rows, and a throw puts the whole `.townHall` domain into backoff. It becomes a zero-row-tolerant read; when the post is not readable (hidden, deleted, another community, a forwarded push) `performTargetedSync` deletes the local row through `BackgroundSyncActor` if one exists and returns `.empty`. A targeted upsert for a post of a community other than the visible one lands in the store, is left out by the `getPosts(communityId:)` predicate, and is pruned by the next full sync.

**Admin.** Phase 2: `PendingMembersView(communityId:)` reads `get_community_members(p_status: 'pending')` and calls `approve_community_member` / `reject_community_member`; it is reachable from the My communities row ("Requests to join (n)") and from the notification. On this build the platform admins' Pending Users row opens the same screen for the default community (they still see email and phone on the detail, through their existing `profiles` read), so a new-build platform admin sees only Seattle's applicants and never uses the legacy direct UPDATE again. `BadgeCountManager.calculateProfileBadgeCount` (`:288-307`) reads `pendingMembersTotal` from the badge payload instead of calling `adminService.fetchPendingUsers()`, which removes the second client-side aggregation path and makes the badge work for community admins. Platform admins also get Admin → Communities (`get_platform_communities`, archive, restore; each row opens that community's Requests to join, which is how applicants to a community with no owner are handled). Phase 3: `AdminService` methods take `communityId`; `AdminPanelView(communityId:)` with a title menu over the communities the person administers (platform admins also get "All"); members, removal, roles, settings, community reports, stats; `MyProfileView`'s Admin Panel row shows for platform admins or admins of any community (`Features/Profile/Views/MyProfileView.swift:549-560`).

**Screens (new or changed).** `CommunityOnboardingView`, `MyCommunitiesView` (list, role chip, Create, Join with a code, Requests to join, Mute, Report, "No owner. Take over", Leave with the three consequences and their counts from the local store), `CreateCommunityView` (name, description, "Approve new members manually" toggle; "Allow guests to browse" shown to platform admins only), `JoinCommunitySheet` (preview → what the approver will see → questions → confirm; Report this community), `CommunityInviteSheet` (code, share, QR via Core Image, admin options), `PendingMembersView`, platform `CommunitiesAdminView`, then in Phase 3 `CommunityMembersView` + `MemberDetailView(communityId:)`, `CommunitySettingsView`, `AdminPanelView(communityId:)`, `CommunityReportsView`; the two title menus, the "Post to" section, chips. Strings: ~110 new keys under `community_*`, `invite_*`, `onboarding_*`, English plus the five machine-translated locales.

**Sign-out.** `CommunityContext.resetForSignOut()` and `PendingInviteStore` are cleared in `clearPerAccountLocalState()`; nothing else in `handleSignOut` changes.

**Guest mode.** No client change: the guest views and anon policies return fewer rows; `GuestRestrictionReason.joinCommunity` is raised on the Welcome banner path in Phase 4.

### 3.8 What "approved" still unlocks once it can be self-granted

Today `profiles.approved` means "a platform admin vetted this person". After this design it means "this person is an active member of some live community", and creating a community grants that with no human involved (rule 6). Nothing community-scoped is reachable that way: every read and write of requests, Town Hall, directories and leaderboards is bounded by `my_community_ids()`. What remains platform-wide:

| Consumer of `approved` / `is_active_user` | What a self-approved account (owner of its own empty community) can do | Verdict |
|---|---|---|
| `rides` / `favors` / `town_hall_posts` / comments / Q&A / participants / votes / interactions policies | only inside communities it belongs to | fine: membership-scoped in Phase 0 |
| `messages` INSERT (`is_active_user`) | send in conversations it participates in | fine: it can be added only by someone who shares a community with it, and can add only such people |
| `conversations_insert_approved` | create an empty conversation row | harmless; participants are gated by `shares_community_with` |
| `reviews` INSERT (`20261006_0002`) | review a completed request it posted | fine: implies membership of that request's community |
| `invite_codes` INSERT (dormant legacy table) | create a row nobody can redeem (no reachable client, owner-only SELECT) | harmless; table dropped in Phase 5 |
| `geocoding_cache` (after the Phase 0 change) | read and write place rows | accepted residue, D16 |
| Storage: `town-hall-images` INSERT requires `approved`; the other buckets need only a signed-in account (an owner path, or for message images being in some conversation); **all buckets are public** | upload images to a public URL | accepted with the mitigations below; private buckets with signed URLs are Phase 5 (D16) |
| fan-out loops, leaderboards | nothing: they loop over one community's members | fine |

So the remaining exposure of open creation is abuse of the app as a place to park content (a community name and description, uploads), not access to anyone else's community. The mitigations are the creation limits (3 a day, 10 owned), the bell row every platform admin gets for each new community, the platform community list with one-tap archive, and the report-a-community path, all in Phase 2 or earlier. A stricter alternative, holding a community created by a never-vetted account in a review state until a platform admin releases it, is D25.

---

## 4. Migration and rollout plan

Each phase ships alone, is backward compatible with the installed build, and says what an old client sees. Migrations follow the repo's header convention (APPLIED / NOT APPLIED, md5 of the deployed body, probe outcomes) and are committed in the same change. The MCP applies one `CREATE OR REPLACE FUNCTION` / `ALTER POLICY` per call, so **no step below depends on several calls being one transaction: after every single call the installed build's inserts, completions, reviews, approvals and account deletion still work.** `delete_user_account`, `admin_reject_pending_user`, `unwind_member_requests` and `guard_last_owner` go through the SQL editor in one run. A write-up of a hole that is still open on the live backend is not pushed to the public repo until it is closed.

### Phase 0 — Server only: isolation and the default community (no app update)

**Step 0 — `20261007_0000_live_bodies_snapshot.sql`.** Export the live bodies (md5 recorded) of `should_notify_user`, `notify_new_ride`, `notify_new_favor`, `notify_town_hall_post`, `notify_pending_user`, `notify_user_approved`, `handle_new_report`, `send_broadcast_notifications`, `handle_new_review`, the three `record_xp_*`, `protect_admin_fields`, `guard_request_client_update`, `get_xp_leaderboard`, `get_leaderboard_spotlights`, `get_badge_counts`, `get_user_badges`, `get_user_stats`, `is_user_approved`, `create_signup_profile`, `delete_user_account`, `admin_reject_pending_user`, and the predicates of the 28 policies and 3 views. This is the rollback artefact. Deploy `send-message-push` with the `left_at is null` filter (a pre-existing defect that becomes a privacy issue once private communities exist); it is the only edge deploy in this phase, because `_shared/badges.ts` already reads `total`. `REVOKE EXECUTE` on `get_or_create_conversation` and `get_or_create_request_conversation` from `authenticated, anon`.

**Step 1 — `20261007_0001_communities_core.sql`**, applied in this order:

| # | Calls | Why this position |
|---|---|---|
| 1a | tables, nullable columns, indexes, the `report_target_check` extension | purely additive |
| 1b | backfill Part A (the community, memberships, primary) | before any trigger exists: no notifications, no mirror writes |
| 1c | the helpers of 3.2 | need the tables |
| 1d | `protect_admin_fields` (first), `recompute_profile_membership_flags`, the two mirror triggers, the two legacy bridges; then re-run Part A and assert the consistency query returns no row | the escape must exist before the mirror's first write; the re-run catches anyone approved or applying between 1b and here |
| 1e | `fill_request_community` + 3 triggers, `fill_xp_event_community` + trigger, `derive_notification_community`, `derive_report_community` | from here no new row can lack a community |
| 1f | backfill Part B (content rows, `xp_events`, notifications, reports) | after the fill triggers, so nothing inserted meanwhile is missed |
| 1g | `guard_request_claim_membership` + 2 triggers, `guard_community_members_client_update`, the append-only trigger, `updated_at` triggers | the claim guard compares `community_id`, so it follows Part B |
| 1h | `should_notify_user` (the two arms), then the function `notify_pending_membership`, then `notify_pending_user` → no-op, then the `notify_pending_membership` trigger, as consecutive calls | the gate precedes the producer; the no-op and the new trigger are adjacent so an applicant is announced once. The gap is one MCP call; an applicant who submits inside it is still in the list and the badge, only the push is missed |

`guard_last_owner` is **not** in this step (see step 4).

**Step 2 — `20261007_0002_communities_rls.sql`:** the 28 `ALTER POLICY`, the 7 new policies, the three views, the column grant on `community_members`. Each `ALTER POLICY` alone is a no-op for a world with one community, so the order within the step does not matter.

**Step 3 — `20261007_0003_communities_fanout.sql`:** the three fan-out loops, the `notify_user_approved` guards, `guard_request_client_update`, `handle_new_review`, the three `record_xp_*` (explicit community), `handle_new_report` (community-report branch), `send_broadcast_notifications` wrapper + `send_community_broadcast`, the leaderboard wrappers + `get_community_leaderboard` / `get_community_spotlights`, `get_profile_stats`, the visibility gate on `get_user_badges` / `get_user_stats` / `is_user_approved`, `create_signup_profile`, and `get_badge_counts` (`pending_members_total` and `community_details` in one call; `total` in a separate call so it can be reverted alone, D28).

**Step 4 — `20261007_0004_communities_account_lifecycle.sql`** (NOT APPLIED → SQL editor, one run): `unwind_member_requests`, the new `delete_user_account`, the new `admin_reject_pending_user`, and `guard_last_owner` with its trigger. The guard and the deletion RPC land in the same transaction because the live `delete_user_account` (`20261005_0008:176-189`) deletes the profile with no membership handling: with the guard already in place, the cascade would remove the default community's only owner row, the guard would raise, and that person could not delete their account. Until this step INV-M3 needs no trigger: no client can write role or status, and the RPCs that can arrive in step 5.

**Step 5 — `20261007_0005_communities_rpcs.sql`:** the membership, invite, directory, context, report and platform RPCs. From here a second community can exist; everything that isolates it (steps 1–4) is already live.

**Step 6 — `20261007_0006_communities_not_null.sql`:** assert `count(*) where community_id is null` is 0 on `rides`, `favors`, `town_hall_posts`, `xp_events`; then the four `ALTER COLUMN community_id SET NOT NULL`. Applied only after steps 1–5 are live and the short probe below has passed after each of them.

**The short probe, run after every step** (`begin; … rollback;` as an existing member): insert a ride and a favor without `community_id`; claim and complete the ride as a second member; insert a 5-star review; read back the ride's community and three `xp_events` rows with a community; delete the account of a probe member, a probe admin and the default community's owner. Any failure stops the rollout at that step.

**The full probe matrix, run after step 5 and again after step 6.** It is committed as a parameterised script, `supabase/probes/communities_probe.sql` (member, unapproved, banned, probe-community-only member, community admin, platform admin and `anon` subjects), so each migration header cites a reproducible run:

- *No-op for the default community:* each of the 19 members reads 106 / 61 / 34 rows; an unapproved account reads 0 foreign rows; anon reads 106 / 61 from the guest views and 34 posts; `public_profiles` returns 19 rows for a member and 19 for anon; every user's XP total is unchanged; `explain analyze` of the rides SELECT as a member of three communities shows the InitPlan and an index range scan.
- *Isolation:* a probe community's ride is invisible to a Seattle member; its member is absent from a Seattle member's `public_profiles`, `search_community_members`, `get_user_badges`, `get_user_stats` and `get_profile_stats`; a Seattle member cannot be added to a thread by the probe member; `notify_new_ride` queues exactly one push per probe-community member; a claim across the boundary raises 42501 from the trigger even when issued by a definer function; spotlights and the leaderboard for the probe community show only its requests; a member of the probe community reads no `community_members` row but their own, and `get_community_members` returns null answers to them and the answers to its admin.
- *Legacy bridges:* old-client application UPDATE → pending default membership and exactly one `pending_approval` per default-community admin; old-client approve → active membership and `approved = true`; old-client approve of a probe-community-only applicant → `approved` stays false; approve through both paths in one transaction → one state, no error; **old-client reject of a default-community applicant → row and account gone; of a probe-community-only applicant → `success: false`, nothing changed; of a never-applied account → `success: false`, nothing changed; of a person active in the probe community with a pending default row → the row gone, the account kept; `admin_reject_pending_user` called by the probe community's owner → refused.**
- *Notifications to a community owner who is not a platform admin:* after an applicant redeems a code for an approval-gated probe community, its owner holds exactly one `notifications` row and one `notification_queue` row of type `pending_approval`; a Seattle admin holds none.
- *Privileged columns:* a non-admin's direct UPDATE of `approved`, `is_admin`, `is_banned` or `primary_community_id` raises; the mirror's write succeeds; a maintenance write with no JWT succeeds; `create_signup_profile` re-run by a member leaves `approved` true.
- *Membership end:* leave the only community → `approved = false`, `application_complete = false`; a removed member reads 0 `communities` rows for it and cannot redeem a code to it; a banned account cannot redeem, request or be approved.
- *Archive:* a member of an archived probe community reads 0 of its rides, cannot insert, and (it being their only community) has `approved = false`, `application_complete = false`; restoring it reverses both.
- *Invites:* a member's code is single-use and expires within 7 days regardless of the arguments; the 11th failed validation in an hour is refused; `validate_community_invite` as anon → permission denied.
- *Account deletion:* a sole owner with an admin → the admin is owner; with members only → `owner_vacant_since` set and a member can claim; alone → archived; in every case the profile deletes cleanly, the user's invites are revoked and their event rows have null `user_id` and `reason`.
- *Reports:* `report_community` creates a row only platform admins can read; a person report between two people who share exactly one community gets that community.
- *Reputation:* two viewers who each share a different community with the same person read identical `get_profile_stats` for them; a viewer who shares none gets an empty result; `get_community_leaderboard` for a private community the caller is not in is refused.
- *Blocks:* with a block in either direction, `get_community_members` (as a non-admin) and `search_community_members` leave the other person out; the admin's pending list does not.

**What old clients see:** nothing different. Same rows, same pushes, same approval screens, same admin lists. The admins are announced about an applicant after the application is filled rather than before (an improvement). An approval welcome push now names the community ("Welcome to Naar's Cars Seattle!"). If `total` is applied (D28), the number APNs puts on the app icon becomes requests + messages + community, which is the number the app itself already sets when it is open. The only other observable change is `community_id` in responses, ignored.

**Impact summary (high-blast seams touched in Phase 0).** `get_badge_counts`: three additive keys; consumers are `BadgeCountManager` (ignores unknown keys) and `_shared/badges.ts` (starts returning `total`; verify on a device that the icon number after a push equals the in-app number). `should_notify_user`: two arms widened; every producer that addresses those two types was checked (`notify_pending_membership`, `handle_new_report`). `notifications` rows gain `community_id`; no consumer reads it yet. Notification type registry: unchanged.

**Rollback:** `ALTER COLUMN … DROP NOT NULL`; `ALTER POLICY` back to the snapshot predicates; re-apply the snapshot bodies; disable the new triggers. The new tables and the nullable columns can stay.

### Phase 1 — iOS: hardening and community-aware reads (no visible change for a one-community member)

Client only (plus the Phase 0 RPCs it reads). Contents: the tolerant `NotificationType` decoder; the `entityIdKey` fix with the zero-row-tolerant single-post fetch; the `.enterApp` guard; `recheckAccountStatus`; `PendingApprovalView`'s `performCriticalLaunch` fix; section 3.7 "new types", "how `CommunityContext` is loaded", "mandatory trio", "fetch scoping"; reputation through `get_profile_stats`; the community-aware leaderboard; `search_community_members`; the Post-to section; the chips; both title menus; the Town Hall switch; `community_id` on Town Hall targets from pushes and bell rows; the "Former member" fallbacks. No onboarding or create / join UI: no member can hold two memberships yet, so every switcher, chip and picker is invisible to all 19 members, and the release doubles as a regression canary for the mapper trio and the install-over-previous-build SwiftData migration.

Two behaviour changes exist even with one community and are called out in the PR's Impact Summary: Town Hall pushes do a single-post refresh instead of invalidating the domain (3.7 Notifications), and a member whose approval is revoked server-side is moved out of the main UI on the next foreground instead of the next launch.

Verification: Lane B build; unit suite signed out. Named tests:

| Seam | Test |
|---|---|
| mapper trio | fixture tests in the `BackgroundSyncActorConversationSyncTests` style for rides / favors / posts / notifications with and without `communityId`, including "a cached row with nil community is rewritten by the next sync" |
| Town Hall scoping | `TownHallRepository.getPosts(communityId:)` with nil, matching, other and unlabelled rows; `TownHallFeedViewModelTests`: a sync for A is in flight, switch to B → final `posts` and store are B's and `posts` is never emptied after B's page arrived; nil → community resolution does not clear the list |
| launch | `AppLaunchManagerTests`: context restored from defaults before the engines start; context nil at launch; membership load failure leaves launch unaffected; `recheckAccountStatus` with each flag combination and with a failed read (no-op) |
| routing | `DeepLinkParserTests` and `NavigationCoordinatorRoutingTests` with and without `community_id` for the three Town Hall types and `content_hidden`; `.enterApp` while authenticated does not change the launch state; `simctl push` fixtures (`type`, `town_hall_post_id`, `community_id`) |
| push → coordinator | `WebhookFixtures.notificationPushPayload` gains a `community_id` variant; a `PushNotificationService` test asserts the targeted refresh for `town_hall_post_id` and that an unreadable post leaves `.townHall` out of backoff |
| badges | `BadgeCountManagerTests`: decode `pending_members_total`, `community_details` and `total`, each present and absent |
| registry | `NotificationTypeDecodingTests` for an unknown raw value; `NotificationFixtures.allRawValues` completed (three types are missing today) |
| filters | `RequestFilterManager` narrow-predicate tests |

`RenderPreview` / Lane B screenshots of the two forms, the dashboard and the Community tab in light / dark / AX5 with one and with three memberships (a DEBUG seam in `CommunityContext`), and of each "Former member" row. **Two install-over-previous-build runs on the simulator with a populated Town Hall store:** one online, opening the Community tab at once (the cached feed shows, then refreshes), and one in airplane mode (the cached feed shows and stays); both must also show that `createModelContainer` does not throw.

**What old clients see:** still nothing; they coexist with Phase 1 clients indefinitely.

### Phase 2 — iOS: create, invite, join, approve (the first real second community)

Client: `CommunityOnboardingView` as the `.needsApplication` root; `MyCommunitiesView` with Create, Join with a code, **Requests to join** (`PendingMembersView`: approve and reject, for community admins and, for the default community, platform admins), **Mute**, Report, Take over and Leave; `CreateCommunityView` → invite sheet; `JoinCommunitySheet` with typed codes, the "what the approver sees" line and Report; the waiting screen's membership list and two actions; `PendingInviteStore`; the `pending_approval` route to `PendingMembersView`; the Profile badge from `pending_members_total`; the Community title menu's per-community counts and the scoped `clearCommunityBadge`; platform admins' Communities list with archive and restore. Tests: stubbed `CommunityServiceTests` for every RPC wrapper; `DeepLinkParserTests` / `NavigationCoordinatorRoutingTests` for `pending_approval` with and without `community_id`; a `simctl push` fixture for it. Server: nothing new; Phase 0 shipped every RPC and the `should_notify_user` change.

This phase must contain the approve screen: new communities default to manual approval (D11), and v1 left their owners with no way to admit anyone until Phase 3.

**Legal and disclosure deliverable (ships with this build, before any non-operator can read an applicant's answers):**

- `Legal/PRIVACY_POLICY.md`: §4.1 adds application answers, community memberships, invite redemptions (who invited whom) and notes an admin writes when removing a member; §6.1 is rewritten per community ("members of the communities you belong to see your name, photo and car"; "owners and admins of a community you apply to or belong to also see your application answers, who invited you and your join date, and never your email or phone number"; "platform moderators may review reported content in any community, including private ones, and see who reported it"; phone-number visibility restated per community); §9 lists memberships, invites and admin notes among what deletion removes or anonymises.
- `Legal/TERMS_OF_SERVICE.md`: a new "Community owners and admins" section (anyone may create a community; what owners and admins may do: approve, remove, moderate, announce; what they may not; that ownership passes to an admin, or is offered to members, when an owner's account is closed, per D23; that the operator may archive a community); §4 and §9 reworded so "we" is no longer the only approver and moderator.
- `Legal/FAQ.md`: line 15 (how to join) now describes the three ways in: an invite code, a request to a public community, or creating your own; line 23 ("visible to all community members") becomes "visible to the members of the community you post it in"; line 35 already says community admins review reports and gains the reporter-privacy sentence.
- `Legal/PRIVACY-DISCLOSURES.md` reviewed against the same changes. Both effective dates bumped. **The app opens the Notion copies** (`Core/Utilities/Constants.swift:222-223`, used by Welcome, sign-up, Settings and the guest profile), so the owner mirrors both documents to those pages before submission.
- In the app: one sentence in the join sheet ("<Community>'s admins will see your name, photo, car and these answers. They never see your email or phone number."), one in the report sheet (reporter privacy, 3.5), and a seventh community-guidelines section on communities, their admins and platform moderators (`guidelines_7_title` / `guidelines_7_body`; the six existing sections are behavioural only).

**What old clients see:** a member of only the default community: nothing different. A member who also joined a second community from a new build sees the union on an old device with no chips, posts into the primary community (S4), and sees ratings and fulfilled counts computed from the reviews and requests that device can read. A platform admin on the installed build sees applicants to other communities, and accounts that have signed up but not applied anywhere, in Pending Users and in the Profile badge count, and can neither admit nor reject them: Approve shows "Approval update failed", Reject shows the server's reason (S6). A community owner's second device on the installed build that taps a `pending_approval` push lands on Pending Users' permission error. A person approved into a second community who taps that push on an installed-build device sees a loading flash (D22). **The release notes ask the four platform admins to update with this build, not the next one** (D10).

App Store: new UGC surfaces (community name and description, invite codes) with report paths for content, people and the community itself, block unchanged, and platform moderators who can archive any community; the review notes describe the invite flow with a test invite code and say that platform moderators see every report. Privacy policy and terms updated (above).

### Phase 3 — Community admin and moderation

Server: `handle_new_report` recipients extended under INV-P2; `get_community_reports`, `moderate_community_content`; `get_community_stats` + breakdowns and the `admin_*` wrappers; `town_hall_posts` DELETE policy gains `community_id = any((select my_admin_community_ids()))`; the `user_rejected` and `account_restricted` producers in `reject_community_member` / `remove_community_member`. Both types are already in the installed build's enum (`Core/Models/AppNotification.swift:64, 67`) and in `notificationTypes.ts:32-33`, so they are safe for old clients now; the tolerant decoder only matters for types the registry does not have yet. Before applying, confirm both raw values pass the live `notifications.type` CHECK and run `scripts/validate-notification-types.sh`.

Client: `AdminPanelView(communityId:)` under My communities for owners and admins; `CommunityMembersView` + `MemberDetailView` (remove, re-admit, promote, transfer); `CommunitySettingsView` (join policy, who can invite, archive); `CommunityReportsView` with the `content_reported` route; broadcast to a community; stats. Tests: stubbed `AdminServiceTests` (the service has no test class today) for every method that takes `communityId`; routing tests for `content_reported` with `community_id`.

Probe additions: a report on a probe-community post → its owner's `content_reported` row has null `source_user_id`, `get_community_reports` as that owner has no reporter column, and the platform admins' rows are unchanged; a report on the owner's own post → no row for the owner or any other admin of that community and nothing in their list; `moderate_community_content` on one's own content → refused.

**What old clients see:** as Phase 2. A community admin's installed-build device that taps a `content_reported` push lands on the platform reports screen's permission error.

### Phase 4 — Multi-membership polish

The "N in other communities" hint when Requests is narrowed; bell-row chips; a real `broadcast` push honouring `canBeDisabled == false` and the community mute, routed to Announcements (D13); one new notification type, `membership_update`, added through the four-layer registry procedure now that the tolerant decoder has adoption, to give ownership changes and second-community approvals their own tap route; the Universal Link `https://naarscars.com/join#<code>` (the code is in the fragment, so it reaches neither the web server's logs nor a referrer; `applinks:` entitlement and the Associated Domains capability added to the App ID and provisioning profile, an App Store Connect step for the owner; AASA hosted by the owner at `Constants.URLs.deepLinkBase`; `onOpenURL` → `DeepLinkParser.parse(url:)` → `DeepLink.joinCommunity(code)` → the join sheet; signed-out → `PendingInviteStore` + a Welcome banner that says only "You have an invite. Sign up or sign in to use it."; this revives the dead `AppDelegate.handleURL` path, `App/AppDelegate.swift:132-136`, through the UIScene route CLAUDE.md already lists as a fragile follow-up); community `timezone` as the create-form default.

**What old clients see:** nothing different; an old client that taps a Universal Link falls back to Safari, where the landing page reads the fragment in the browser and shows the code.

### Phase 5 — Deprecations (after the last pre-community build has aged out per App Store Connect)

Retire `legacy_application_to_membership`, `sync_legacy_approval_to_membership`, the rollout fallback in `fill_request_community` and the `is_default` dependence; `admin_reject_pending_user` revoked from `authenticated`; stop maintaining `profiles.heard_about / join_reason` for new rows (reads move to `community_members`; columns stay); delete the dead invite UI (`SignupInviteCodeView`, `SignupMethodChoiceView`, `AdminInviteView`, `InvitationWorkflowView`, `InviteCodeCard`, `InviteService`, `AuthService.signUp(email:password:inviteCode:)`), `ApplicationFieldsView` and `PendingUsersView` — Xcode project-file removals are owner steps; `invite_codes` and its policies / triggers dropped in a SQL-editor file; `geocoding_cache` read through a definer lookup that returns only the multiplier, direct SELECT revoked; private storage buckets with signed URLs for `message-images`, `group-images`, `town-hall-images`, `review-images` (both platforms; D16).

**What old clients see:** a pre-Phase-2 build can no longer apply to the default community through the old form once the bridge is retired; this is the moment the owner has accepted "old build must update".

### Documentation changes per phase

CLAUDE.md requires its affected sections to be re-verified and the audit date bumped with any fragile-system change. Each PR carries these edits.

| Document, section | Phase | What replaces the current text |
|---|---|---|
| CLAUDE.md, Current State, "Guest mode is implemented" | 0 | guests read only public communities; the guest views join `communities.is_public` |
| CLAUDE.md, Audit Notes, database contract, "Who can read `rides` and `favors`" | 0 | other people's requests are readable only in communities the reader is an active member of; `is_active_user` still required |
| CLAUDE.md, database contract (new bullets) | 0 | `profiles.approved`, `application_complete` and `primary_community_id` are mirrors maintained by `recompute_profile_membership_flags` and are not client-writable; `community_members` client-writable columns are `notifications_muted`, `muted_until`, `updated_at`; `admin_reject_pending_user` semantics; the `conversation_participants` INSERT predicate; "a column added to `rides` / `favors` goes into the guest views" now also means the join to `communities`; the helper vocabulary of 3.2 and INV-D1; who may delete an account (INV-M9); `geocoding_cache` requires an active account |
| CLAUDE.md, Fragile systems 4 and 7, Cross-Layer seams | 0 / 1 | `community_id` push payload key; `get_badge_counts` keys `pending_members_total`, `community_details`, `total`; `should_notify_user` arms; `entityIdKey` for Town Hall is `town_hall_post_id` and Town Hall pushes do a targeted refresh |
| CLAUDE.md, State Management rule 2 | 1 | `CommunityContext` joins the list of `@Observable` Core state holders |
| CLAUDE.md, Fragile system 5 and Quick Reference "Auth state" | 1 | `recheckAccountStatus` (acts only on a successful read); the waiting screen runs `performCriticalLaunch()`; `.enterApp` does not relaunch an authenticated session |
| CLAUDE.md, Fragile system 6 and Canonical Entry Points | 1 | "Switch the Community tab's community" = set `CommunityContext.communityTabId`; the feed ViewModel calls `forceFullRefreshAndWait(.townHall, …)`; `.townHallPostsDidSync` carries the synced scope; `TownHallSyncEngine` reads `CommunityContext` at fetch start |
| CLAUDE.md, Sign-out row and "Sign-out clears per-account local state" | 1 | `CommunityContext.resetForSignOut()`, `PendingInviteStore` |
| CLAUDE.md, File conventions; Testing Expectations | 1 / 2 | `CommunityServiceProtocol`; the Auth row gains community approval and zero-membership routing; `supabase/probes/` |
| CLAUDE.md, Notification rules | 2 | `pending_approval` has two audiences and two routes |
| AGENTS.md; `.cursor/rules/04` (badge contract), `05` (navigation intent), `06` (mapper mirroring) | 0 / 1 | the same facts in their shorter form |
| SECURITY.md §2 | 0 | §2.1.1 `public_profiles` predicate; §2.1.2 the InitPlan-helper idiom and `my_visible_profile_ids`; the 28 changed policies; new §2.28–2.33 for the six tables; §2.24 `geocoding_cache` is no longer "not sensitive, open to all signed-in accounts" |
| SECURITY.md §4 Admin Authorization | 0 / 2 | two admin notions: platform (`profiles.is_admin`, `verifyAdminStatus`) and community (role, checked inside each RPC); SEC-ADMIN-001 applies to platform operations only; INV-M9 |
| SECURITY.md §5.3 server-side rate limits | 0 | 3 communities a day, 10 failed code attempts an hour, 3 broadcasts a day per community, the invite caps |
| SECURITY.md §6 Invite Code Security | 0 | codes are generated on the server from a CSPRNG over the same 31-symbol alphabet (31^8); validation needs a signed-in account; the per-device limit is replaced by the per-account one |
| SECURITY.md §8.2 events to log | 0 | `community_membership_events` |
| `Legal/*`, the Notion copies, in-app guidelines | 2 | the Phase 2 deliverable above |
| `Docs/design-system/README.md` | 1 / 2 | the community chip and title-menu patterns; no new tokens |

---

## 5. Fragile-system invariants touched and how they are preserved

| Area (CLAUDE.md) | Invariant | How this design touches it | Risk / mitigation |
|---|---|---|---|
| RLS is the security boundary | client filtering is not security | all isolation is in policies, helpers and triggers; the client `.eq` on Town Hall and the local narrow predicate are performance / presentation filters | wrong predicate leaks B to A or blanks the default community for everyone → Phase 0 is server-only and semantically a no-op for the single community; the committed probe matrix is the gate; every policy is reversible by `ALTER POLICY`; the helper form is indexable, measured with `explain analyze` |
| Caller-bound helpers (`20261005_0020`) | helpers answer only for `auth.uid()` | the nine new read helpers take no user argument or answer only when the caller is a member; `community_of_*` are service_role only; the three per-user stat RPCs gain the `public_profiles` visibility gate | none new |
| Rollout ordering | every step leaves the live app working | `NOT NULL` last; fill triggers (including `xp_events`) before the content backfill; the lifecycle guard with the lifecycle functions; no multi-call atomicity assumed | a step applied out of order → the short probe (insert, claim, complete, review, delete account) runs after every step and stops the rollout |
| `RefreshCoordinator` | at most one task per domain; join, never cancel except sign-out; ViewModels call only `forceFullRefreshAndWait` | **not modified**; two new sanctioned calls (Town Hall switch, dashboard after leave) | a refresh that joins a sync started for the previous community → the screen is driven by the scoped enrichment page; the sink ignores full-sync emissions for another scope; the store is reconciled by at most two retries decided from a repository read |
| Sync engines | pure fetch-and-store; `BackgroundSyncActor` compare-before-write; reconciliation deletes | `DashboardSyncEngine` unchanged (union fetch); `TownHallSyncEngine` reads one fetch parameter from `CommunityContext` at fetch start, keeps "prune absent", stamps the scope on its notification; four optional columns copied at every field site; one new `BackgroundSyncActor` method deletes a single post that is no longer readable | a missed field site leaves `communityId` nil → chip missing, and the post is still shown (nil is "unknown, show") rather than hidden → fixture tests per entity; a nil `communityTabId` means no filter, never an empty feed |
| `NSNotification.Name` contract | consumers updated together | `.townHallPostsDidSync` gains an optional `userInfo` scope; posted at `TownHallSyncEngine.swift:66, 82` and `TownHallRepository.swift:88, 97`, consumed only by `TownHallRepository.getPostsPublisher` (`:38`) | a consumer that ignores `userInfo` behaves as today |
| Realtime (active conversation only) | ~3 channels; subscribe-then-fetch; main-actor marshalling | untouched | none |
| Optimistic send | `MessageSendManager → Worker → Service`; durable queue | untouched; no store wipe on switch | none |
| Reactions | `individualReactions` single source of truth | untouched | none |
| Notification routing | push → parser → `DeepLink` → intent → coordinator → consumer; `pendingIntent` only | additive `communityId` on the Town Hall `DeepLink` cases, `.townHallPost` and `.openTownHallPost` (four pattern-match sites edited); one owner for the community switch (the feed ViewModel); new `pendingMembers` route in Phase 2 and community reports route in Phase 3; the `.enterApp` handler no longer relaunches an authenticated session | routing-table and parser tests with and without the key; the intent is still consumed exactly once; `pending_approval` and `content_reported` documented as two-audience types |
| Push → coordinator seam | `affectedDomains` / `entityIdKey` match the payload | `entityIdKey` corrected for Town Hall: an invalidation becomes a targeted refresh | the targeted fetch tolerates zero rows, so an unreadable post cannot put `.townHall` into backoff; fixture test for both cases |
| Notification type registry | Swift enum = `NotificationTypeRegistry` = `notificationTypes.ts` = SQL CHECK; `should_notify_user` and `get_badge_counts` lists | **no new type through Phase 3**; `user_rejected` and `account_restricted` (already in every registry layer) get producers in Phase 3; one new type in Phase 4 after the tolerant decoder has adoption; `should_notify_user` gains two widened arms and one new arm in Phase 0 | export the live `should_notify_user` first; `scripts/validate-notification-types.sh` before Phase 3 and Phase 4; `NotificationFixtures.allRawValues` completed in Phase 1 |
| Badge system | one `get_badge_counts`; coordinator-only refresh; 5 s debounce; 5-minute poll | three additive keys; the Profile badge moves **onto** the RPC (`pending_members_total`) and the separate pending-users fetch is removed; `total` changes the number APNs sets on the icon to the number the app already shows (D28) | verify on a device that the icon number after a push equals requests + messages + community; the tab badge is cross-community by rule 12 and the clear is scoped from Phase 2 |
| Auth and launch | `initializing → checkingAuth → ready(authState)`; `AppState` / `AuthService` in sync | `checkAccountStatus` untouched; both flags mirrored in both directions; one `ContentView` root swap for `.needsApplication`; the waiting screen runs `performCriticalLaunch()` on approval; `recheckAccountStatus` can move an authenticated session to `.needsApplication` / `.pendingApproval`; `.enterApp` guarded | the mirrored flags are a second source of truth → the probe suite and a nightly consistency query (`select id from profiles p where p.approved <> exists(live active membership)` and the same for `application_complete`); the re-check acts only on a successful read (a failed read must never eject a member); `AppLaunchManagerTests` |
| Sign-out teardown | clears subscriptions, caches, engines, tokens, per-account state | `CommunityContext.resetForSignOut()` and `PendingInviteStore` added to `clearPerAccountLocalState()` | unit test asserting the keys are gone |
| SwiftData schema | additive only; optional properties migrate lightweight | four `UUID?` properties, no new `@Model` | two install-over-previous-build runs (online, airplane mode) in Phase 1 |
| `protect_admin_fields` | a client cannot flip `approved` / `is_admin` / `is_banned` | a transaction-local setting lets exactly three definer statements through; the admin test is explicit and still passes writes that carry no end-user JWT; `primary_community_id` guarded | probe: direct client UPDATE of each privileged column → raises; the mirror's write succeeds; a write with no JWT (the backfill) succeeds; `create_signup_profile` cannot reset a member |
| Two-way `approved` mirror | each trigger is a no-op when its state already holds | `recompute_profile_membership_flags` ⇄ `sync_legacy_approval_to_membership` with `is distinct from` guards | probe: approve through both paths in one transaction; the nightly query |
| Guest mode | gated in UI and RLS | anon policies and guest views now require `is_public`; the default community is public at backfill | if the owner later makes it private, guests see empty lists |
| Account deletion (App Store 5.1.1(v)) | works from every state; only the user deletes their account | `created_by` nullable; handover / vacancy / archive before the profile delete; the guard ships with the function; invites revoked; event text scrubbed; `admin_reject_pending_user` stays platform-only and default-community-only | SQL-editor migration; deletion re-probed after **every** Phase 0 step for an owner, an admin and a member; the Apple-revocation order remains the known follow-up |
| Moderation (App Store 1.2) | report / block / hide on every UGC surface; a reachable moderator | every report reaches the platform admins; community admins are added in Phase 3 without the reporter's identity and never for reports about themselves; a community can be reported; platform admins can archive any community from Phase 2 | platform admins can see private communities' reported previews, including the pickup → destination text of a reported ride → disclosed in the privacy policy, the terms and the guidelines; auto-hide needs 3 reporters, so in a tiny community the platform admins are the moderators in practice |
| Messaging reach | — | `conversation_participants` INSERT requires `shares_community_with` (creator-relative); the two RPC side doors are revoked; leaving a thread ends the profile exposure | `ConversationService.createConversationWithUsers` inserts participants in one batch (`Core/Services/ConversationService.swift:468-480`); a batch with one non-co-member fails whole — the picker only offers co-members, so the policy is the backstop |
| Storage and place data | — | storage not changed until Phase 5; `geocoding_cache` limited to active accounts in Phase 0 | **all buckets are public**: an image URL from a private community is readable by anyone who has it; place rows are readable across communities. Acceptable for the first private communities only if said plainly to the owner (D16) |
| Edge functions / webhooks | Vault secret; `x-webhook-secret` | `send-message-push` `left_at` only | none |
| `public_profiles` as a definer view | accepted advisor exception | predicate added | the predicate now reads membership, conversation and review data through one helper; the probe must prove `auth.uid()` evaluates to the caller inside the owner-rights view |
| Public repo | holes are not published while open | the Phase 0 migrations describe policies before they are live | commit and push only after each step is applied and probed |

**App Store checklist for this change.**

- New system permission: no.
- Collects or stores user data differently: **yes.** Memberships, per-membership application answers, who invited whom, admin-written removal reasons and a membership event log are new stored data, and application answers become visible to community owners and admins, who are ordinary users. The privacy policy, terms, FAQ and their Notion copies are updated with the Phase 2 build. No new data *type* for the privacy manifest (the answers are already collected).
- Account deletion: affected, re-verified per step; no one but the user gains the ability to delete an account.
- Reporting, blocking, moderation: affected; preserved and extended (report a community; reporter privacy).
- Notification behaviour: altered (recipients narrowed to a community; a community mute; `total` on the icon; a dedicated broadcast push if D13 is accepted).
- Third-party SDK: none. Privacy manifest update: none required by this change.
- New entitlement: Associated Domains, Phase 4.
- Subscriptions or payments: none.

Known gaps this design does not close (pre-existing, listed so they are not mistaken for regressions): Town Hall batching is dead; `notify_messages` is not enforced on the live message-push path; the in-app toast has no live trigger; Apple revocation runs before the deletion RPC; `get_leaderboard_spotlights` does heavy work for anonymous callers.

---

## 6. Effort estimate by phase

Agent-days = focused Claude Code sessions in the worktree with the Supabase MCP and the headless lane, including probes and fixture tests; review hours = the owner's time reading migrations, running the SQL-editor step, and exercising flows in the simulator with two accounts. The review moved work earlier (approve UI, mute, community reporting, legal) and added the probe script and the launch / routing tests; the total rises by about four agent-days over v1.

| Phase | Agent-days | Human review (h) | Notes |
|---|---|---|---|
| 0 Server: snapshot, core, RLS, fan-out, lifecycle, RPCs, NOT NULL | 5–6 | 7–9 | ~75 MCP calls (one function / policy per call), one SQL-editor run, the short probe after each of six steps, the committed probe script, `SECURITY.md` §2, §4, §5.3, §6, §8.2 |
| 1 iOS: hardening + read-aware client | 6–7 | 7–9 | mapper trio (~26 field sites), `CommunityContext` and its launch ordering, Town Hall scoping and switch, reputation RPC call sites, `recheckAccountStatus`, `.enterApp` guard, chips, two forms, title menus, deep-link key, the named tests, light / dark / AX5 captures, two install-over-build runs |
| 2 iOS: create / invite / join / approve / onboarding | 7–8 | 8–10 | `CommunityService` + protocol + stubbed tests, eight screens including Requests to join and the platform Communities list, the `pending_approval` route, mute, report-a-community, scoped badge clear, ~110 string keys × 6 locales, the legal documents and Notion copies (owner), App Store notes with a test code |
| 3 Community admin + moderation | 4–5 | 5–6 | report RPCs under the reporter-privacy rules, stat wrappers, members / settings / reports screens, the two producers, release-note coordination |
| 4 Polish: broadcast push, new type, Universal Link, hints | 3–4 | 4–5 | AASA hosting and the web landing page are owner actions; the entitlement goes through App Store review |
| 5 Deprecations (+ storage privacy) | 2–3 (+3 for signed URLs on both platforms) | 2–3 | Xcode file removals are owner steps; after adoption |
| **Total** | **27–33 (+3)** | **33–42** | Phase 1 development can start once Phase 0 step 3 is applied and ships after step 6; the first second community exists after Phase 2 |

---

## 7. Open decisions for the owner

Each with options and a recommendation; the body above assumes the recommendation. D1–D19 are v1's (seven of them revised, marked); D20–D28 are new and come from the review.

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | Legacy community name and owner | any name; owner = oldest admin / a named person | "Naar's Cars Seattle"; owner = the account that owns the project; the other three admins as `admin`. Shows in chips, menus and the approval welcome from Phase 0 |
| D2 | Approval model | (a) keep a global account gate; (b) per-community membership approval with open account creation; (c) both | **(b)** — it is what "create your own neighborhood" needs; the bridges keep the Seattle flow unchanged |
| D3 (revised) | Who may create invites, and how strong a member's invite is | admins only / any active member (`members_can_invite`, default on) | **Any active member by default, with limits the server enforces:** a member's code admits one person and expires in 7 days; only admins can make multi-use codes (up to 1,000 uses, expiry required, at most 90 days). The inviter is recorded; owners can turn member invites off. Without the limits, one member of an instant-join community could publish a code that admits anyone |
| D4 | Removed members rejoining | need a new invite / only an admin can re-admit / may re-request | **Only an admin can re-admit** (`readmit_community_member`) |
| D5 (revised) | What a profile's numbers cover | (a) **per person**: rating, review count, fulfilled count, savings, XP and badges are the same for every viewer (served by RPCs); the written reviews listed are only those of requests the viewer can see, with "N more in other communities". (b) **per viewer**: every number on someone's profile counts only the communities you share with them | **(a)** — a helper's reputation should travel with them into a new community, and a number that changes with the viewer reads as a bug. It reveals only aggregates across communities, never content. Leaderboard and spotlights are per community under both options. v1 stated (a) but wrote policies that produced (b) |
| D6 | Requests scope and the Community tab coupling | (a) merged Requests with an optional narrow, Community tab independent; (b) one shared active community that also narrows Requests; (c) one global switcher for every tab | **(a)** — asks are never hidden; the dashboard data path stays untouched |
| D7 | Guest browsing | (a) public communities only, the default community public, the flag editable by platform admins only; (b) no guest browsing of community content; (c) invite links open a read-only preview | **(a)** — preserves what Apple reviewed; (c) leaks content to anyone holding a forwarded link |
| D8 (revised) | Messaging reach | (a) you can start a thread with, or add, anyone who shares a community **with you**; a member of two communities can therefore put people from both in one group thread; threads survive leaving and removal and stay writable. (b) strict: everyone in a thread must share a community with everyone else, and a thread is closed to a person who no longer shares one. (c) anyone in the app | **(a)** — it is how group chats work everywhere and (b) needs a membership check on every send and breaks request threads when someone leaves. Its consequences are stated: a community admin cannot cut contact that already exists (blocking and reporting can), and a person with no community at all cannot reach Messages until they join one |
| D9 | Platform-admin reach into private communities | full (moderation fallback) / none | **Full**, disclosed in the privacy policy, the terms and the guidelines; required so every community has a reachable moderator from day one |
| D10 (revised) | Old-client coexistence | tolerate the merged old-build view / a soft minimum-build gate / a hard gate | **Tolerate for members; ask the four platform admins to update with the Phase 2 build** (not Phase 3 as in v1), because from Phase 2 the installed build's Pending Users list and badge include people it can neither approve nor reject. No hard gate at 19 users. A soft `Constants.MinimumSupportedBuild` prompt is a 1-day add-on |
| D11 | Default `join_policy` for new communities | `approve` (manual approval on) / `invite` (instant) | **`approve`**; the approve screen ships in the same build (Phase 2); switchable in community settings (Phase 3) |
| D12 | What community admins may see about applicants and members | public fields + answers (no email / phone) / also email | **No email or phone for community admins**; ordinary members never see anyone's answers; platform admins keep `profiles`. The join sheet says what the approver sees |
| D13 | Broadcasts | (a) a real `broadcast` push honouring `canBeDisabled = false` and the community mute, routed to Announcements, replacing the Town Hall side door; (b) keep the side door | **(a) in Phase 4**; platform admins may pick "All communities" |
| D14 | Caps | owned communities per account, members per community, uses per invite, broadcasts | 10 / 500 / 1,000 / 3 a day per community; pure product numbers |
| D15 (revised) | Invite delivery | typed codes only / a Universal Link + AASA | **Codes first (Phase 2), the link in Phase 4, with the code in the URL fragment** (`naarscars.com/join#NC…`) so it is not sent to the web server or a referrer. It needs the Associated Domains capability (an App Store Connect step) and an owner-hosted AASA file |
| D16 (revised) | Data that is not private per community yet | accept and schedule / block Phase 2 on it | **Accept, stated plainly:** (1) all storage buckets are public, so an image URL from a private community works for anyone who has it; (2) `geocoding_cache` rows (street-level place data with no user or community attached) are readable by any active account. Both close in Phase 5 (signed URLs on both platforms; a lookup RPC) |
| D17 (revised) | Community-level mute | ships with the first multi-community build (Phase 2) / Phase 4 / never | **Phase 2.** The server side is in Phase 0 either way; the switch is one row in My communities, and it is the only way to quiet one community's mandatory new-request pushes short of leaving it |
| D18 | The word | "community" / "neighborhood" / "group" | **"community"** (the tab already says it); the choice touches ~110 strings in six languages |
| D19 | Application questions at join | keep the two existing questions (optional when approval is off) / drop them | **Keep**; stored on the membership row; copied to `profiles` only for the default community's old-build admin screen |
| D20 (new) | What the installed build's Reject does | (a) acts only on applicants to the default community; refuses, with a visible reason, a person who applied elsewhere or has not applied anywhere; deletes the account only when no other membership row exists. (b) as v1: a platform admin's Reject removes any pending row and deletes the account when nothing else is left. (c) as (a) but still deletes never-applied accounts, as today | **(a).** The old screen cannot tell a Ballard applicant from a Seattle one, and an account deletion cannot be undone. The cost: an old-build admin can no longer clear a stale sign-up that never applied (they can still ban it). Community admins can never delete an account under any option |
| D21 (new) | Are platform admins notified about applicants to communities they do not run? | no, unless the community has no owner or admin / yes, always | **No.** An application is that community's business; platform admins can still open any community's list. It also keeps installed-build admins from being pushed to a list where they can do nothing |
| D22 (new) | Telling someone they were approved into a further community | (a) the existing `user_approved` push with the community's name, with the new build guarded so the tap does not relaunch the app; an installed-build device shows a loading flash on tap. (b) a bell row only until Phase 4's new type | **(a).** People wait for this notice. The flash affects only a second, un-updated device of someone who joined from an updated one |
| D23 (new) | A community whose only owner deletes their account | (a) hand to the longest-standing admin; with no admin, **keep it open without an owner**: platform admins cover approvals and moderation, and the first member who accepts takes over. (b) admin, else archive. (c) admin, else make the longest-standing member owner automatically (v1) | **(a).** (b) destroys a working group because one person left; (c) makes someone responsible without asking. The rule goes into the terms |
| D24 (new) | Default for "Post to" | (a) the community Requests is narrowed to, else the Community tab's, else the last one posted to, else the primary; the button says "Post to <name>". (b) no default when Requests is not narrowed: the person must pick | **(a).** A ride posted into the wrong private group shows an address to the wrong people, so the button names the destination; (b) is the stricter choice at the cost of a tap on every post |
| D25 (new) | Oversight of newly created communities | (a) open creation with limits; platform admins get a bell row for each new community and can archive in one tap; communities can be reported. (b) a community created by an account that was never a member anywhere is held for platform review before anyone but its creator can use it. (c) only existing members can create | **(a).** The owner's goal is that a new person can start a neighborhood and invite people at once; (b) and (c) put the operator back in front of every newcomer. (b) is the fallback if spam appears |
| D26 (new) | Leaving while a neighbor has claimed a request you posted | (a) the request is cancelled and the helper is told (as account deletion does today), listed with counts on the Leave sheet. (b) the request stays until it completes and you stay able to see just that request | **(a)** — one rule for leave, removal and deletion; (b) needs a visibility exception for non-members |
| D27 (new) | Reports about a person (not a post) | (a) when the reporter and the reported person share exactly one community, that community's admins see it too (anonymously, never the reported person); otherwise platform admins only. (b) always platform admins only | **(a)** — otherwise a community admin can act on a bad post but never hears about a member harassing neighbors. Message reports stay with platform admins under both options (private thread content) |
| D28 (new) | The number APNs puts on the app icon | (a) add `total` to `get_badge_counts` in Phase 0: pushes then set requests + messages + community, the number the app itself shows; today the server falls back to all unread notifications + unread messages, which can differ. (b) leave it until a client phase | **(a), as its own revertable call, checked on a device.** It is a badge-system behaviour change for all 19 members and is unrelated to communities, so it is called out rather than folded in silently |

---

## 8. Deliberately out of scope

- **Cross-posting one request to several communities** (a join table breaks INV-R3's single answer to "whose members may claim" and doubles every fan-out). Post twice.
- **Community-scoped conversations and per-community message badges** (`conversations.community_id`, a community in the message push, a new `get_conversations_with_details` shape). DMs are personal.
- **Strict pairwise messaging isolation** (D8 option b).
- **A public community directory, search or "near me" discovery.** Private groups are reached by invite; `is_public` plus the link is enough until there are more than a handful of communities.
- **Nested or federated communities** (`communities.parent_id` can be added later).
- **Moving a request or post between communities; merging communities; hard-deleting communities** (archive only; a purge job for archived communities with no content can come later).
- **Automatic archiving of a community that stays without an owner** (platform admins see the marker and decide).
- **Per-community guidelines text and acceptance** (the global guidelines gate stays, with one added section).
- **A per-community breakdown of reputation on profiles** (the schema supports it; D5).
- **Per-community custom notification preferences beyond mute**, digests (the batching path is dead and would need a rebuild), collapse keys.
- **Showing a reporter's identity to community admins**, under any setting.
- **Lowering the 3-reporter auto-hide threshold for small communities** (platform admins are the backstop).
- **An anonymous (signed-out) invite preview** (the code waits until sign-up).
- **Community avatars, colours or themes** (initials avatar from the name; no new colour tokens).
- **A JWT custom claim for the active community** (server correctness would depend on client state; unverifiable in a rolled-back probe; breaks when a push for B arrives while the token says A).
- **Partitioning the SwiftData store by community** (the dashboard store holds the RLS union; Town Hall holds one scope's first page).
- **Changing the realtime scope** (still conversation-only; no community channels).
- **Splitting the app-icon badge per community** (one integer per app; `community_details` gives the menus their counts).
- **Retiring `invite_codes` and the dead invite UI before Phase 5** (they need project-file removal in Xcode).
- **Android** — covered by the parallel native-Android design; every contract addition here (RPCs, payload key, badge keys, the mirror, server-side block filtering of directories) is platform-neutral by construction.

---

## 9. Alternatives considered and why rejected

**The tenant-aware data-model design ("multi-model").** It has the strongest isolation engineering on the panel — the InitPlan helpers, `community_has_member`, the claim-membership trigger, the invariant list with enforcement points, `notifications` / `reports` scoped from day one, a `community_invites` table with redemptions and an append-only membership log — and every one of those is grafted into this document. It was not adopted whole for three reasons the judges verified. First, its phase order ships the first build on which a second community can exist (Phase 5) before the visibility tightening (Phase 6: `public_profiles` scoping, the `conversation_participants` shared-community check, the Town Hall comment and vote policies), leaving a window in which a member of a new community can enumerate every Seattle member, add them to group threads and read every Seattle comment by post id; this document applies all of that in the server-only Phase 0. Second, its new `profiles` SELECT policy lets anyone who creates a community read the full profile rows of their members — email, phone number and ban fields — and the proposed remedy (a later column-level grant hiding email from community admins) cannot work because column grants are per role, not per policy; this document never adds such a policy and gives community admins an explicit RPC projection instead. Third, it is the largest surface — five new tables, eight new columns, a replaced launch path with a new `AuthState` case, `communityId` on six intents, a store partitioned across ~40 field sites with scoped reconciliation deletes, `conversations.community_id` with a message-insert gate, a rewritten request-conversation RPC and the Universal Links entitlement — spread over seven phases and ~34.5 agent-days, three of them before any visible value, touching four of the eight fragile systems, where this document rewrites none of their pipelines and makes bounded edits to three (the foreground account re-check, notification routing, and one fetch parameter in the Town Hall engine).

**The product-and-UX-first design ("multi-product").** It has the best product thinking on the panel — the merged Requests feed with chips and an optional narrow, the independent per-community Community tab, "Post to" only when it matters, one approval toggle, the invite sheet opening right after Create, link / code / QR, a waiting screen that is never a dead end, consequences spelled out on Leave, and nineteen decisions with recommendations — and this document adopts essentially all of its UX and its dashboard data strategy. It was unshippable as written because of its legacy bridges, both verified against the code: the old-build sign-up bridge hooks `notify_pending_user` on `profiles` INSERT, but `create_signup_profile` and the Apple path insert the profile with `application_complete = false` and the questions arrive in a later UPDATE, so an "applied" legacy membership is created before the application exists and for every invite-link newcomer (profile creation and redemption are separate RPC calls); and it provides no reverse bridge for the installed admin build's direct `UPDATE profiles SET approved = true`, so in its server-only Phase 1 — when every admin is on the installed build — each approval yields `approved = true` with an "applied" membership, the newcomer reads zero rides, favors and posts, cannot post (42501 from the fill trigger) and is flipped back to pending by the next membership write. It also left the `get_or_create_conversation` side door unmentioned, used `ON DELETE CASCADE` from `rides` to `communities`, called `RefreshCoordinator.invalidate` from a ViewModel, and scheduled Universal Links in the same phase as the first second community. This document keeps its product shape and replaces its migration layer with the state-based bridges of §3.3.

**Two shapes rejected by all three designs, recorded for completeness.** A single `community_id` on `profiles` (one community per person) contradicts the owner's requirement that a person may belong to several. A JWT custom claim carrying the "active community" so that no client call changes makes server correctness depend on client state, makes RLS unverifiable in a rolled-back probe without minting tokens, and breaks the moment a push for community B arrives while the token says A.

**Alternatives weighed in this revision.**

- *Awaiting `get_my_memberships` before launch hydration* would make the Town Hall scope known by construction, but adds a serial round trip to every launch and a failure mode on the launch path. Restoring the last community synchronously from UserDefaults and defining nil as "no filter" gives the same result without either.
- *A Town Hall store partitioned by community* (prune only within the synced community) would make switching instant from cache and would survive a joined sync without a retry, but changes a reconciliation-delete rule in `BackgroundSyncActor` and needs a second prune for communities the person has left. The single-scope store with a guarded sink and a bounded retry is the smaller change; partitioning can follow if switching feels slow.
- *Making archive a membership status* (flip every member to a terminal status) would fire the mirror for free, but loses the information needed to restore a community. Excluding archived communities in the helpers and recomputing flags from a trigger on `communities` keeps restore a one-column change.
- *Widening the existing admin report functions to community admins* (v1) reuses a screen but hands over the reporter's name. Separate RPCs with a narrower projection cost two functions and close that.
- *Letting the legacy reject function serve community admins* (one reading of v1) would let anyone who creates a community delete another person's account. It stays platform-only and community admins get `reject_community_member`, which cannot delete anything but a pending row.
- *A third argument on `should_notify_user`* (the community) was considered for the admin-type gate. It would force a signature change through `create_notification` and `queue_push_notification`, which every producer calls. The gate stays a per-person eligibility test and the producers' recipient queries do the routing.

---

## 10. Review responses

One line per finding. "Confirmed" findings survived the three-vote refutation panel and are all addressed in the body.

### Confirmed, high or critical

- **RLS-1** — `admin_reject_pending_user` keeps its platform-admin-only check, acts only on a pending default-community row, refuses everything else without change, and deletes an account only when no membership row of any status remains; the per-row rule replaces the old `approved = true` refusal; INV-M9 states who may delete an account; four probe cases added (3.5, 3.6, 4, D20).
- **MIGRATION-1** — the four `SET NOT NULL` moved to a final step 6; `xp_events` gets a fill trigger in step 1 so the XP writers work unedited; fill triggers precede the content backfill; no step assumes multi-call atomicity; the `notify_pending_user` no-op and the new trigger are adjacent calls; a short insert / complete / review / delete probe runs after every step (3.1, 3.3, 4).
- **MIGRATION-2** — nil `communityTabId` is defined as "no filter" in the service, the engine and the repository; cached rows with a nil community are shown, and healed by the first sync because the trio compares `communityId`; the community is restored from UserDefaults before the engines start and the membership load never blocks launch; two install-over-previous-build runs (online, airplane mode) are Phase 1 verification (3.7, 4).
- **FRAGILE-1** — `should_notify_user`'s `pending_approval` and `content_reported` arms are widened in Phase 0 to owners and admins of a live community, applied before the producer; the probe asserts one row and one queue row for a non-platform owner and none for a Seattle admin (3.5, 4).
- **FRAGILE-3** — load order specified: synchronous restore before `startDeferredSyncEnginesIfNeeded`, asynchronous membership load after; a nil scope fetches unfiltered and prunes as today; `loadPosts()` always refreshes on appear so no corrective launch refresh is needed; `AppLaunchManagerTests` cases added (3.7, 4).
- **PRODUCT-1** — the installed build's Reject can no longer delete another community's applicant: it returns an error the old screen displays; platform admins are not notified about other communities' applicants (D21); S6 now says what the old-build admin actually sees for both buttons; admins are asked to update at Phase 2 (2.3, 3.5, D10, D20).
- **PRODUCT-2** — `application_complete` is mirrored in both directions, so a person with no active or pending membership routes to onboarding on both builds; the new build re-routes a running session through `recheckAccountStatus` (successful reads only) and after its own leave; the Leave sheet says what comes next (rule 18, 3.3, 3.7, S12).
- **PRODUCT-3** — headline numbers come from `get_profile_stats` (per person); the review list stays viewer-scoped with "N more reviews in other communities"; the three `ProfileService` call sites are Phase 1 scope; reviewer names on one's own profile resolve through a new arm of `my_visible_profile_ids()`; D5 rewritten with both options (rule 8, 3.4, 3.5, 3.7).
- **COMPLIANCE-1** — community admins never read `reports` and never use `admin_get_reports`; `get_community_reports` omits the reporter and excludes reports about the caller; community-admin notification rows carry no source user; reports about an owner or admin skip that community's admins; platform admins are the stated backstop for the unreachable auto-hide threshold; Phase 3 probes added (rule 10, 3.4, 3.5, INV-P2).
- **COMPLIANCE-2** — a legal and disclosure deliverable is added to Phase 2: privacy policy, terms, FAQ, `PRIVACY-DISCLOSURES.md`, the Notion copies the app opens, a seventh guidelines section and two in-app sentences; the App Store checklist now answers "stores user data differently: yes" (4, 5).
- **COMPLETENESS-2** — the `.enterApp` handler is guarded so an authenticated session is not relaunched; the second-community approval's route is traced for both builds and made a decision (D22); `send_approval_notification` is recorded as having no caller and is left alone (2.4, 3.7).
- **COMPLETENESS-3** — the gate is fixed in Phase 0 (FRAGILE-1); Phase 2 now ships `PendingMembersView` with approve / reject and a `pendingMembers` route for the tap, so an approval-gated community can admit people from its first build (3.7, 4).
- **COMPLETENESS-4** — same resolution as PRODUCT-3: the policy scopes the written list, the RPC serves the numbers, and D5 states the choice; probe "a non-member cannot read `get_profile_stats`; a co-member in B reads the same rating a co-member in A does".

### Confirmed, medium or low

- **RLS-2** — `primary_community_id` is server-owned: guarded in `protect_admin_fields`, written only by the mirror and `set_primary_community`; `fill_request_community` and the leaderboard wrappers use it only while it is a live active membership; probe added.
- **RLS-3** — both array helpers exclude archived communities; the `communities` applicant arm is limited to `status = 'pending'`; probes for an archived community's member and a removed member.
- **RLS-4** — the `community_members` SELECT policy is own rows plus the community's admins; `get_community_members` returns answers, inviter and removal reason only to admins; the backfill copy is kept and explained (only the four platform admins, who see those answers today, can read it).
- **RLS-5** — member codes are single-use and expire in 7 days by RPC rule; admin codes need an expiry; live-code caps; codes from `gen_random_bytes` with rejection sampling; validation is authenticated-only with a 10-failures-an-hour limit recorded in a small table; keyspace corrected to 31^8.
- **RLS-6** — new section 3.8 lists every remaining consumer of `approved` and what a self-approved account can do with it; storage upload stays the accepted residue (D16); the review-state alternative is D25.
- **RLS-7** — the `current_user` escape is replaced by a transaction-local setting bracketing three statements; `create_signup_profile`'s conflict branch stops assigning the mirrored flags.
- **RLS-8** — `get_user_badges`, `get_user_stats` and `is_user_approved` answer only under the `public_profiles` visibility rule.
- **RLS-9** — D8 now says reach is creator-relative and transitive through group threads, with strict pairwise isolation as the rejected option; the conversation arm of `my_visible_profile_ids()` requires the caller's `left_at is null`.
- **RLS-10** — banned targets are refused in request, redeem and approve with a neutral `restricted` error; S6 reworded to the error the installed build shows.
- **MIGRATION-3** — `guard_last_owner` ships in the SQL-editor run with the new `delete_user_account`, never before; the new function hands over, marks vacancy or archives before the profile delete; deletion is re-probed after every step.
- **MIGRATION-4** — archive is honoured by the helpers and a trigger on `communities.archived_at` recomputes every member's flags; a member whose only community is archived routes to `.needsApplication` (onboarding / the form) on both builds; probe added.
- **MIGRATION-5** — covered by the two-way `application_complete` mirror: an installed-build leaver sees the application form, which the bridge turns into a default-community application; a person removed from the default community is not re-admitted by that form.
- **MIGRATION-6** — the `badges.ts` redeploy is dropped (it already reads `total`); the two existing types' producers move to Phase 3 with the reason corrected; the tolerant decoder is described as protection for types not yet in the registry.
- **FRAGILE-4** — `pending_approval` with a `community_id` routes to `PendingMembersView` from Phase 2; two audiences and two routes are documented; parser and routing tests named; an installed-build second device's dead-end is stated.
- **FRAGILE-5** — the invalidation → targeted-refresh change is called out as a seam change; the single-post fetch tolerates zero rows and removes the local row; the hidden-then-pruned path for another community's post is stated; fixture tests named.
- **FRAGILE-6** — the feed ViewModel owns the pending target and the switch; the intent is consumed once; `CommunityTabView` only selects the segment; the four pattern-match sites that stop compiling are listed as edits.
- **FRAGILE-7** — the Profile badge moves onto `get_badge_counts` (`pending_members_total`) and the separate fetch is removed; the `total` change is in the Phase 0 impact summary and is D28.
- **FRAGILE-8** — addressed the other way round from its recommendation, deliberately: unlabelled cached rows are shown, not excluded (MIGRATION-2 asked for this and it avoids an empty first launch); the install-over-build checks are in Phase 1.
- **PRODUCT-4** — rule 12 states the tab badge is cross-community; from Phase 2 the clear is scoped to the visible community and the title menu shows per-community counts.
- **PRODUCT-5** — rule 13 and the Leave sheet list all three consequences with counts; `unwind_member_requests` is specified step by step; the keep-until-complete alternative is D26.
- **PRODUCT-6** — default chain reordered (narrow → Community tab → last posted → primary) and the button names the community; D24.
- **PRODUCT-7** — D8 covers both cases: no community means no access to Messages until rejoining; threads survive removal and stay writable, and the limits of that are stated.
- **PRODUCT-8** — a person report is routed to the single shared community's admins from Phase 3, anonymously; D27.
- **PRODUCT-9** — creators and instant joiners get no approval notice (a transaction-local suppression setting); pending and welcome notices name the community; the copy for every membership event is in 2.4.
- **PRODUCT-10** — the waiting screen loads memberships itself on appear and each poll tick, lists every pending community, and falls back to generic copy; `get_my_memberships` works while unapproved.
- **PRODUCT-11** — every ownership change produces an announcement row for members and a push for the new owner; automatic promotion of a plain member is dropped (D23).
- **COMPLIANCE-4** — invites are revoked on leave, removal and deletion; event-log reasons are nulled on deletion (the append-only trigger permits exactly that); the handover rule is D23 and goes into the terms; deletion probes extended.
- **COMPLIANCE-5** — `report_community` and `reports.reported_community_id` added (Phase 0 server, Phase 2 UI); the platform Communities list with archive, and the new-community notice, move to Phase 2.
- **COMPLIANCE-6** — rule 17: directory and search are block-filtered on the server; admin duties (applicant and report notices, approve, remove) are deliberately not; a block never changes membership.
- **COMPLIANCE-7** — no anonymous preview at all; `member_count` only for public communities; the link carries the code in the fragment; the Associated Domains capability is listed as a provisioning step (D15).
- **COMPLETENESS-5** — per-RPC predicates written out: the leaderboard's `xp_events` scan and its ride / favor subqueries, and every ride / favor CTE of spotlights, which never reads `xp_events`; probe added.
- **COMPLETENESS-6** — `community_id` is carried for `content_hidden` and for every in-app bell-row tap that opens a post; when absent, the community is resolved by fetching the post.
- **COMPLETENESS-7** — `geocoding_cache` is limited to active accounts in Phase 0; the cross-community residue is disclosed in D16 and closes in Phase 5.
- **COMPLETENESS-8** — tests are named per seam in Phase 1 (badge payload, push payload with `community_id`, launch, routing, Town Hall race); stubbed `CommunityService` / `AdminService` tests in Phases 2–3; the probe matrix is a committed script.
- **COMPLETENESS-9** — "Documentation changes per phase" lists each CLAUDE.md section, AGENTS.md and the cursor rules with the replacing statement (kept inside section 4 so that section 10 stays the review responses).
- **COMPLETENESS-10** — the same table lists SECURITY.md §2, §4, §5.3, §6 and §8.2.
- **COMPLETENESS-11** — the derive trigger also resolves `review_id`; conversation and message rows are null on purpose.
- **COMPLETENESS-12** — one alphabet, the app generator's 31 symbols, in the CHECK, the RPC and SECURITY.md §6.

### Rejected review findings

The panel's majority refuted these. Each is rejected as stated; what was real in it is noted.

- **FRAGILE-2** (2 of 3 refuted) — rejected as a "false premise, high" finding: the enrichment page is the last write, so the screen showed the right community after one round trip, and v1 already named the joined-sync case. Two points from it are adopted because the one upholding vote showed a reachable empty-state flash: the sink now ignores full-sync emissions for another scope, and the retry is decided from a repository read instead of an engine property, bounded at two (3.7).
- **COMPLIANCE-3** (3 of 3 refuted) — rejected: no non-disableable `broadcast` push exists before the mute does, the mute's server side ships in Phase 0, and mandatory new-request pushes are today's reviewed behaviour, narrowed here to communities the person joined; Guideline 4.5.4 concerns promotional pushes. Adopted from the refuters' own notes: the mute switch moves to Phase 2 because it costs one row (D17), and `send_community_broadcast` and the Phase 4 broadcast push are stated to honour the mute.
- **COMPLETENESS-1** (2 of 3 refuted) — rejected as "not addressed": v1's F6 and 3.5 did specify the old-build Reject, and it is a confirmed, two-step action, not one tap. Its substance is the same as PRODUCT-1 and RLS-1, which are confirmed and fixed; the old-build list and badge over-count is now stated plainly under Phase 2 and D10.

### Found while revising (not raised by the review)

- **`protect_admin_fields` NULL-safety.** v1 told the implementer to wrap the admin test in `coalesce(…, false)`. The live test passes when `auth.uid()` is null, which is what lets migrations, the SQL editor, cron and the service role write `approved` today; the plain coalesce would have blocked all of them, including Phase 0's own backfill. The test is now explicit: it raises only for a signed-in non-admin (3.3).
- **`content_reported` had the same dead-end tap as `pending_approval`.** v1 sent it to community admins from Phase 0, but its tap opens the platform reports screen, which refuses them. Community admins are added as recipients only in Phase 3, together with their reports screen and route; until then every report goes to the platform admins as today (3.5, 4).
- **The foreground re-check must not reuse `checkAccountStatus`.** That function answers `.needsApplication` when its query fails. Harmless today, because the re-check only acts on `.banned`; once it can also move a session to onboarding, a failed read would eject every member who foregrounds the app offline. The generalised re-check uses a throwing read and does nothing on error (3.7).
- **"Leaving does what account deletion's STEP 1–2 do" was inaccurate.** In the live function STEP 2 only notifies helpers; the user's requests, completed ones included, are deleted in STEP 7. `unwind_member_requests` is therefore specified on its own terms (open requests deleted, claimed ones cancelled with notice, completed ones kept), and account deletion keeps its existing steps unchanged instead of being rebuilt on the new function (3.5).
