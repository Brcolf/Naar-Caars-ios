# Community discovery, open communities and trust: design

> Date: 2026-10-21. Status: **decided, not built.** Nothing here is built or scheduled; the only live changes are the Test Community rename and the hiding of its old content (4.10).
> Sources: the owner's decisions of 2026-10-20 and 2026-10-21, the navigation synthesis and the eight approved mockups S1 to S8 (`build/design/`, kept locally). Where they differ from this file, this file wins. It builds on [`2026-10-07-multi-community-design.md`](2026-10-07-multi-community-design.md) and [`2026-10-17-multi-community-decisions.md`](2026-10-17-multi-community-decisions.md).
> Labels: a plain statement is the owner's decision. **Orchestrator's call** is a choice the orchestrator made, including in writing this file; the owner can overrule it. **Builder's call** is left to whoever plans the build, usually with a recommendation.

## 1. Intent

The owner wants strangers in a town to ask each other for rides and favors, safely. Today a community is a closed circle: someone invites you, or an admin approves you. The next step lets a town have an open community that anyone nearby can find and join, while people stay protected from each other until they choose to connect.

The owner also wants the app to feel like one piece. Phases 1 to 5 landed in corners of the old layout: My communities sits under Profile and joining takes four taps. This design gives communities a front door (Explore) and a page each, and keeps the weekly job, asking for or giving a ride, where members already find it.

The balance, in the owner's words: new users should feel welcome and existing users should feel safe.

## 2. Goals, non-goals, anti-goals

**Goals**
- Anyone finds a listed community by typing its name, or a town or ZIP, or by tapping "Use my location": guest, new account or member.
- Two owners who agree can merge their communities into one (2026-10-21 addition).
- An owner makes a community open, ask-to-join or invite-only, listed or hidden, and can change it later.
- No member of any community reads a street address before being connected to that request. The server enforces it.
- In open communities the poster chooses the helper.
- Questions about a request are asked and answered on the request, in public.
- Four tabs plus Explore, with every Phase 1 to 5 feature in a clear place.

**Non-goals (this version):** chat screen changes beyond a closed state; location for anything but the one search (no background location, no tracking, no stored coordinates of a person).

**Anti-goals (do not build):** an address directory for a town; a friend or follower system; a location permission used for anything other than the search the person just asked for; a platform-admin gate on creating communities; a mixed feed where someone misjudges what a stranger sees (every card states its rules).

## 3. Constraints

- **App Store.** Account deletion, Sign in with Apple, reporting, blocking, moderation and guest mode stay intact. New user content (offer notes, answers) gets a report path. The privacy policy, terms and App Privacy answers are reviewed for areas, stored coordinates of typed addresses, offers, and the one new permission: "while using" location, asked only when the person taps "Use my location" in Explore, with an `NSLocationWhenInUseUsageDescription` that says exactly that; the device location goes into that one search request and is never stored or logged, which the App Privacy answers must state correctly (**Builder's call:** check whether the optional-disclosure exemption for data used only to service a request applies, or declare Location as collected for app functionality, not linked, not for tracking).
- **The server is the boundary.** As with `guest_rides` / `guest_favors` and the `moderate_*` RPCs, who sees an address, who may offer, message or post is decided by RLS, views, triggers or SECURITY DEFINER RPCs. Screens only explain.
- **No pre-community build remains** (confirmed 2026-10-20). Every user is on a build of this branch, not always the newest; 4.10 says what each older build sees.
- **The shipped schema is extended, not replaced,** and it is the live one: Phase 4 Files B and C and the four Phase 5b files were all applied on 2026-10-20, so every new migration starts from those function bodies. An RPC whose signature changes gets a new name, not a defaulted parameter (the existing rule).
- **CLAUDE.md.** `RefreshCoordinator` owns refresh; no new domain is proposed (offers ride on `.dashboard` and `.badges`). WebSockets stay conversation-scoped. UIKit messaging is untouched except a closed state. The SwiftData trio changes together and additively. New ViewModels are `ObservableObject` + `@MainActor`.
- **Notification registry.** New types go into all four layers at once and `scripts/validate-notification-types.sh` must pass.
- **Design system.** Tokens, `NaarsChip`, `NotificationBadge`, `.cardStyle()`; glass only on floating surfaces.

## 4. The decided design

### 4.1 Community model

Two switches replace three loose types.

| Switch | Values | Rule |
|---|---|---|
| Listed | listed (in search) or hidden | Hidden: never in search, never shown to guests, joined only by code or link. A hidden community uses approval or invite, never open. |
| Join policy | open, approval ("Ask to join"), invite ("Invite only") | Open: anyone signed in joins at once (listed communities only). Approval: an admin approves each person; in a hidden community a code leads to a pending request, as today. Invite: a code or link admits at once. |

A town-wide community is listed and open. The default community is renamed "Test Community" (done 2026-10-21), stays listed with approval, and is the showcase that guests and new accounts explore (4.11).

**Server.** `communities.join_policy` gains `'open'`. **Builder's call** (recommended): keep `is_public` as the column with the meaning "listed", since every guest view and policy reads it, and add a CHECK that a hidden community is not open (**Orchestrator's call:** hidden plus approval stays a valid combination, because today's `create_community` defaults to hidden plus approval, so most communities people have made are exactly that, and turning them invite-only would let every outstanding code admit people at once, weakening a gate their owners chose; no data migration). This replaces D7, under which only platform admins could make a community public. Platform admins can still unlist or archive after a report (A2).

**Changing settings.** "An owner should always be able to adjust the security of their group to turn it private or public, etc." **Orchestrator's call:** only the owner changes the two switches and the service area, through a new owner-only RPC (for example `update_community_access`); admins keep editing name and description.

**Orchestrator's call: a request keeps the rule it was posted under.** Each request stores `help_mode` (`offer` or `claim`), set from the policy at posting. A policy change never alters a request in flight.

| Change | Effect on existing members |
|---|---|
| Approval or invite → open | Members stay. New requests use offers. Pending join requests are admitted and told. The community stops giving messaging reach (4.7); existing threads stay. No cool-off for existing members. |
| Open → approval or invite | Members stay; the owner can remove anyone. New requests are instant claims; pending offers on older requests run to the end. Messaging reach starts. |
| Listed → hidden | An open community must first choose approval or invite; approval and invite stay as they are. Leaves search and guest views at once. Pending join requests stay for admins to decide. |
| Hidden → listed | Needs a service area and the nearby check (4.2). |

Members get one `announcement` bell row saying what changed. Today's hidden communities keep their approval policy (the orchestrator's call above).

### 4.2 Service area, search and the nearby check

A listed community has a service area: a center and a preset radius (1, 2, 5, 10 miles), geocoded from a town or ZIP the owner types. `communities` gains center, radius, area name and creation reason. **Builder's call:** use the town or ZIP centroid MapKit returns and refuse street-level results, so a center is never a home.

**Search, by name or by place.** One field in Explore. What the person types is searched two ways at once and shown in two groups: **"By name"**, listed, unarchived communities whose name contains the text (case-insensitive, two characters or more; a new RPC, for example `search_communities_by_name(p_query)`, callable by guests, capped at 20 rows), and **"Near <place>"**, when MapKit resolves the text as a town or ZIP (`MKGeocodingRequest`, which also retires the deprecated `CLGeocoder` calls): a new RPC (for example `find_communities_near(p_lat, p_lng)`), callable by guests, returns listed, unarchived communities whose circle covers the point, nearest first, with name, policy, area, distance from the searched place and member count. Hidden communities never appear in either group. Neither the text nor the point is stored or logged. **Builder's call:** great-circle math in SQL, no PostGIS; whether the two RPCs are one with two optional arguments.

**"Use my location"** (2026-10-21 addition) is a button beside the field. Tapping it asks for "while using" location the first time, with a purpose string that says it finds communities near you and nothing else. On permission, the device location is reverse-geocoded on the device to the town or ZIP, which fills the field, and the search runs as if typed; the coordinates go only into that one `find_communities_near` call. A refusal leaves the field for typing, with no nag. Location is never read at any other time, never in the background, and never for a member's requests or areas.

**The nearby check stays soft.** "I want a user to be aware of existing communities but not restricted." When the new circle overlaps listed communities, the create flow shows them with links and requires a short reason. No approval gate ("may have to revisit this later if there is abuse"). The server re-checks the overlap and refuses a missing reason. The same check runs when a community becomes listed or moves its area.

**Platform admins** see each new or newly listed community with its area and reason in Admin → Communities (`get_platform_communities` gains both) and as an `announcement` bell row without push, the A1 pattern.

**Merging two communities** (2026-10-21 addition, the owner's "if we can"): see 4.12.

### 4.3 The Requests feed

- **Merged by default ("All communities"),** as D6 decided. Chips under the title include or exclude each community ("Showing 2 of your 3 communities"). The title menu lists each community with its open count; picking one narrows the feed and shows that community's rule as the subtitle (S2). The filter is local, remembered per account.
- **A policy chip on every card:** globe Open, lock Ask to join, key Invite only. "I like the chips and it appears clear to me." **Orchestrator's call:** the policy chip shows even with one membership; the community name shows only with two or more, as today.
- **Tiles: Open, Mine, Helping.** Helping replaces Claimed: what you help with, plus pending offers with a Waiting chip.
- **"You have N offers to review"** appears only when a poster has pending offers and opens Mine, where cards carry an "N offers" chip.

### 4.4 Areas and addresses, for every community type

"All neighborhood types - open, private, invite only can benefit from the obfuscated addresses and only see areas until they have been connected for a ride."

**An area** stands in for each end of a request (pickup and drop-off; a favor's location): a place name ("Ballard area") and a rough circle, never a pin. It is computed when the request is posted or its address edited, and stored beside the address.

**The connection.** In an open community: the poster accepting an offer. In an approval or invite community: the helper's claim, which confirms at once as today. It lasts until completion, cancellation, release by the poster or the helper backing out; then the helper sees areas again.

| Viewer | Before | While connected | After |
|---|---|---|---|
| Poster | addresses | addresses | addresses |
| Participants the poster added (**Builder's call**, recommended: as the poster) | addresses | addresses | addresses |
| Connected helper | areas | addresses, pins, Open in Maps | areas |
| Other members | areas | areas | areas |
| Community owners and admins (**Orchestrator's call**) | areas | areas | areas |
| Platform admins | addresses (today's access) | addresses | addresses |
| Guests and visitors | areas (guests see blanks today) | areas | areas |

**Server mechanism (a proposal the builder may adjust).**
1. **Columns.** `rides` gains `pickup_area`, `destination_area`, their circle centers and a radius, the exact coordinates of each end, and `help_mode`; `favors` the same for `location`. Every view over these tables gains them in the same migration.
2. **Computing the area.** The server has no geocoder, so the posting client sends the point MapKit gave it for the picked place, and the neighborhood or town name. A BEFORE INSERT / UPDATE trigger (for example `derive_request_area`) snaps the point to a coarse grid, applies an offset fixed per request, enforces a minimum radius (**Builder's call**, about 0.75 mile) and checks the label (no house numbers, length cap). Without a point it falls back to the community's area. The client never decides the circle.
3. **Close the address columns.** Revoke SELECT on the address and exact-coordinate columns of `rides` and `favors` from `authenticated`; `anon` already reads nothing. Row policies stay, so every policy that checks a request by id (`request_qa`, `reviews`, participants) keeps working.
4. **One definer function** (for example `my_request_addresses()`) returns addresses and coordinates only where the caller is the poster, a participant, the connected helper (`claimed_by` is the caller, status `confirmed`) or a platform admin.
5. **Two views** for every signed-in read, `member_rides` and `member_favors`, with `security_invoker = true` so the row policies still decide which rows appear. They return the address from step 4 when there is one and the area in the same column otherwise, plus `addresses_shared`, the caller's `my_offer_status` and, for the poster, `pending_offer_count`.
6. **Guest views** return areas instead of `''`.
7. **Texts that carry addresses switch to areas:** the new-ride push and bell text ("needs a ride to …"), XP descriptions written at posting and completion, and report previews (`content_reported`, `get_community_reports`, the platform list). **Builder's call:** grep every live function body for `pickup`, `destination` and `location`.
8. **Probes**, rolled back: an unconnected member reads areas and gets 42501 reading an address column; the claimer reads the address while confirmed and the area after completion; a community admin reads areas; a platform admin reads addresses; anon reads areas.

**Client.** `ridesReadSource` / `favorsReadSource` return the member views for a session, so every service and sync read goes through them. Inserts and edits still write the tables but return the row through the view or by named columns (a `select *` would hit revoked columns). Cards, detail screens and `RequestMapView` draw circles from the area columns and pins from exact coordinates, with no on-device geocoding of other people's addresses; Copy and Open in Maps need `addresses_shared`. The SwiftData trio gains the fields, and a re-read after a connection ends replaces the cached address with the area. What a helper copied out (a calendar event) stays on their device.

### 4.5 Offers in open communities, instant claims elsewhere

"I love this option to make the poster feel in control." In open communities a claim becomes an offer (S5, S6). The offer sheet shows what the poster will see (photo, full name, rating, reviews, car) and takes an optional short note. The request stays open until the poster accepts someone. In approval and invite communities claims stay instant.

**States:** `pending`, then `accepted`, `declined`, `not_chosen` (someone else accepted), `withdrawn` (by the helper) or `closed` (request deleted or expired). If an accepted helper backs out or is released, the request reopens and older offers stay closed. **Orchestrator's calls:** no timeout, offers end with the request; a declined helper cannot offer again on that request.

**Server.** A table `request_offers` (request, community, helper, note, status, times): the helper reads own rows, the poster reads through an RPC, no client writes. New SECURITY DEFINER RPCs with typed refusal codes, in the `CommunityRPCError` style:
- `help_with_request(type, id, note)`, one entry for both modes: checks membership, `help_mode`, cool-off, blocks either way, a phone on file (today only the client checks) and limits; answers `claimed` or `offered`.
- `withdraw_help(type, id)`: withdraws a pending offer or backs out.
- `get_request_offers(type, id)`, poster only: photo, name, rating, completed helps, reviews, car, note, and "Helped you before" (a completed request together).
- `accept_request_offer(offer_id)`: sets `claimed_by` and `confirmed`, marks the rest `not_chosen`, creates the request conversation (4.7).
- `decline_request_offer(offer_id)` and `release_helper(type, id)`.

`ClaimService` and the claim and unclaim sheets move to these, and the direct claim and unclaim UPDATE policies on `rides` / `favors` are retired. **Builder's call:** limits, recommended one offer per person per request, 10 pending per request, 5 per helper.

**Who is told.** Four new generic types (34 → 38), like the `qa_*` types; the payload carries `ride_id` or `favor_id`.

| Event | Recipient | Type | Push | Opens |
|---|---|---|---|---|
| Offer made | poster | `offer_received` | yes | the request, at the Offers card |
| Offer accepted | helper | `offer_accepted` | yes | the request, with addresses |
| Declined, not chosen, released, closed | helper | `offer_declined`, with `offer_event` naming which | yes | the request, or "no longer available" |
| Pending offer withdrawn | poster | `offer_withdrawn` | bell row only (**Orchestrator's call**) | the request |
| Accepted helper backs out | poster | existing `ride_unclaimed` / `favor_unclaimed` | yes | the request |

All feed the Requests badge; `get_badge_counts` gains `offers_to_review`, counted into the Requests badge and `total`. Fixtures go in `Docs/qa/push-fixtures/`. The status-change trigger must not tell a poster about the claim their own acceptance made.

**The poster's decision screen** is the Offers card on their request: rows with Profile, Report (notes are user content), Decline and Accept. Accept asks once: "Sam will see your exact addresses and you can message each other." The card becomes "Your helper: Sam" with Message, Profile and Release helper.

**Completion and reviews are unchanged:** the accepted helper is `claimed_by`, so `complete_request`, reminders, reviews and XP work as today. Leaving, removal and `delete_user_account` withdraw pending offers and treat an accepted one as a claim.

### 4.6 Phones and profiles

- **Phones.** No phone is ever shown in open communities; the phone on file stays a check for offering or claiming, now on the server. **Correction to the mockups:** today no member sees another member's phone. Since 2026-10-05 other profiles are read through `public_profiles`, which has no phone column, so the phone row on `PublicProfileView` only shows your own. **Orchestrator's call:** no phones anywhere, in any community type, which is today's behaviour; S4 and S7's "each other's phone numbers" goes. The owner can overrule by asking for phones between connected people in approval and invite communities, which would need its own definer read, screen, privacy-policy text and probes.
- **Profiles** show full name, photo, car, rating and reviews to everyone, guests included ("the user would decide what they want" as a photo). Never email or phone. **Builder's call:** `public_profiles` must also return active members of listed communities to signed-in visitors, as it does for guests, and reviews in listed communities must be readable by them, or a visitor's community page cannot show posters.

### 4.7 Messaging and the request Q&A

| | Open communities | Approval and invite communities |
|---|---|---|
| Start a conversation with a member | no | yes, as today |
| Request conversation | opens when the poster accepts | as today |
| After the request ends | read-only, kept as the record | unchanged |
| Questions about a request | the Q&A only | the Q&A first; messages allowed |

"In a public group, no": a past helper cannot message the poster before being accepted again.

**Server.** Reach becomes "shares an approval or invite community" (a narrowed `shares_community_with`), which narrows D8; existing threads survive. `conversations` gains a request link and `closed_at`. `accept_request_offer` creates the thread for the two people; the messages INSERT policy refuses a closed thread; a trigger closes it when the connection ends. A request thread takes no added participants and `find_conversation_for_participants` ignores it, so the next request gets a new thread.

**Client.** The `Conversation` trio gains the link and `closed_at`. The thread shows a header card linking to the request ("Airport ride · Ballard Neighbors"); when closed, the composer gives way to "Completed · addresses no longer shared" (`setComposerSuppressed` exists). A refused send stays recoverable, as today. New Message lists only reachable people, with a footer saying why.

**The Q&A becomes the way to ask.** The owner had an "ask questions" section in earlier versions and wants it back as the public channel. **Correction:** today a poster cannot answer. `request_qa` has no UPDATE policy and `RideService.postAnswer` has no caller, though the `answer` column and the `qa_answer` push trigger exist.
- A new RPC (for example `answer_request_question(qa_id, answer)`), poster only, while the request is open; the existing trigger tells askers.
- Asking stays open while offers are pending and closes when a helper is connected. In open communities the closed line becomes "This request has a helper. Questions are closed." (today's text points to messages).
- The Q&A sits above the Offer or Claim button. Pushes stay `qa_question` and `qa_answer`.
- Everything in the Q&A is public to members and guests; the answer field says "Everyone can read this. Don't share your address." **Builder's call:** a server check for house numbers in Q&A, titles and notes.

### 4.8 Cool-off and moderation

**Orchestrator's call: 24 hours** from joining an open community, during which the member cannot post requests, offer, post or comment in Town Hall, or ask questions. Reading, voting, reactions, profile edits, reporting, blocking and leaving are allowed. Approval and invite communities have none; platform admins are exempt. The server enforces it from `community_members.activated_at` in the insert policies and `help_with_request`, refusing with the time it ends; the client shows that time on +, Offer to help and New post, plus a welcome card on Requests.

Owner duties, community reports (now with area previews), platform moderation, blocking and reporting stay as today. A block either way stops offers and claims between the two.

### 4.9 Navigation and screens

**Tab bar (S1).** Four tabs in one glass capsule: Requests (landing), Messages, Town Hall (renamed from Community, without the Leaderboard switch) and Profile. Explore is the iOS 26 search-role tab at the trailing end: iOS shows the magnifying glass, and "Explore" is the screen title and VoiceOver name. Its badge counts people asking to join communities you own or run. The bell stays a toolbar button opening a sheet.
- Step zero: `MainTabView` still uses `.tabItem`; it moves to the `Tab` API, keeping the tab-to-domain mapping and the `onChange(of: selectedTab)` trigger (Explore has no domain).
- **Builder's call, "maybe there is a way to shrink it slightly".** The system draws the search tab at the bar's height and documents no size control. Use what it supports (`tabBarMinimizeBehavior(.onScrollDown)` shrinks the bar while scrolling) and never replace the system bar. Show the owner a device capture. Under the iOS 27 SDK a search tab may be drawn prominent by default; check.
- Check on a device that the search tab can carry a badge. If not, keep the button and show the count in Explore and on Manage.

**Explore (S3),** one screen for guests, newcomers and members, with one search field and a "Use my location" button beside it (4.2). Before typing: your communities with role chips and "Requests to join N" for admins, "Waiting for approval", a saved invite code (`PendingInviteStore`, Use code and Remove), "Have an invite code?" (a guest gets the sign-in prompt) and "Start a community". After typing: the "By name" group, then "Near <place>" nearest first, each row with policy chip, area, distance (place results) and member count. With none in either: "No community here yet. Sign up to start one." My communities and its admin entries move here from Profile.

**Community page (S4),** opened from Explore and from "About this community" in the title menu:
- A plain rule sentence. Open: "Anyone nearby can join. Helpers see only the area until a poster accepts them. No phone numbers are shown. Messaging opens when a poster accepts a helper." Ask to join: "An admin approves every member. A helper's claim confirms at once, and only then are addresses shared."
- The service-area circle on a small map, live requests at area level, recent Town Hall posts.
- Visitors: a floating glass Join or Ask to join bar (guests get the sign-up prompt). Members: Invite, Mute, Report this community, Leave, leaderboard, guidelines; owners and admins also Manage, which opens today's admin panel, where the owner also finds "Merge with another community" (4.12).
- Signed-in visitors read it through a new definer RPC (for example `get_community_preview`): listed communities only, areas only. Later, possibly: show guests less if gated content grows.

**Profile** keeps you: stats, reviews, settings, share, sign out, Delete Account, and the platform admin panel for platform admins only.

**Start a community (S7):** Basics; Who can join (Listed, then Open, Ask to join or Invite only); Service area (listed only); Nearby check; Invite people. "Lets build it now and we can test with real users once it is built."

**Welcome and newcomers (S8).** "I have an invite code" leaves Welcome: codes are used after sign-in, in Explore or on Get started. The Phase 4 banner for a code saved from a link stays, and the code shows in Explore after sign-in. "Continue as Guest" becomes "Look around first" and opens Explore. Get started (`CommunityOnboardingView`) leads with search, remembers the community a guest was viewing, and keeps Sign Out and Delete Account.

**Pushes (Orchestrator's call).** A request push from another community opens the request on top without changing the Requests filter or the Town Hall community. A Town Hall push switches the Town Hall community and shows "Now in <community>" briefly.

**Where the mockups differ:** S2's Ask to join card shows street addresses (now areas); S4 and S7 promise addresses and phones (now neither); S5 frame 4 keeps the conversation open (now read-only); S8 shows "I have an invite code" (removed); S1's Explore button is full size.

### 4.10 Test data and rollout

**Test data.** The default community was renamed "Test Community" on 2026-10-21 (owner's decision): it stays listed with approval, gets a Seattle service area (**Builder's call**, 10 miles), and is the one community every guest and new account can look at, so it holds example content only (4.11). Its members' earlier rides, favors and Town Hall posts were hidden the same day; permanent deletion is the owner's SQL-editor script (`supabase/scripts/2026-10-21_test_community_cleanup.sql`). Four persistent test communities exist beside it, owned by the test account "NC Test Owner" (`Docs/qa/test-data.md`): Test Public A and B (listed, approval) and Test Private A and B (hidden, invite); two open ones follow once open exists. **Orchestrator's call:** a platform-admin-only `is_test` flag on `communities` keeps those four out of search, the join list and guest views for everyone except their members and platform admins, so they never appear to a real person searching Seattle. Test Community is not flagged: it is meant to be found.

**Release 1, the navigation shell with today's behaviour.** Client: the `Tab` migration, four tabs and Explore (a flat list of listed communities until search exists), the Town Hall rename, the community page without its map, the leaderboard move, the slimmer Profile, Welcome, chips and filters, Helping, the push behaviours. Server: `get_community_preview` and the `public_profiles` extension. A Phase 5a build sees no difference.

**Release 2, discovery.** Server: service-area columns, the owner's listed switch with its CHECK (no data migration: hidden approval communities keep their policy), `search_communities_by_name` and `find_communities_near`, the overlap check, a new-name create RPC with area and reason, `update_community_access`, the platform list, the merge proposal table and RPCs (4.12), the `is_test` flag and the example-content columns and refresh job (4.11). Client: search by name and place, "Use my location" with its permission string, Start a community steps 2 to 4 (Open not offered yet), settings switches, Merge under Manage, search-first Get started, "Join another" on the waiting screen, the Example chip and the refused offer on examples. A Release 1 build lists new listed communities and still creates hidden ones through the old RPC.

**Release 3, trust, in two server steps.**
- **3a, additive:** area columns and trigger, the member views (still returning addresses to members), `request_offers` and its RPCs, the answer RPC, request threads, cool-off checks, the narrowed reach function (unused), and the four types in every registry layer.
- **Client:** reads the views, uses the RPCs, shows areas, offers and the open policy.
- **3b, the gated flip:** revoke the address columns, views return areas, retire direct claim policies, allow `'open'`, switch reach and the texts. A Release 2 build would then fail to read `rides` and `favors` and could not claim, so 3b waits until the owner confirms from App Store Connect that Release 2 builds are gone, a gate like Phase 5b's. The owner may flip at once, as on 2026-10-06, accepting errors until people update.
- **Backfill (Builder's call):** requests from before 3a get an area from the town in their address text and the community's circle.

### 4.11 Example content in Test Community

The owner wants guests and new accounts to have "something to consider as they explore the app", in Test Community, as real rows they can open, not pictures. Rides and favors age out (hidden 12 hours after their time, expired nightly), so example rows need their own rule. **Orchestrator's calls**, the owner may overrule:

- **Author.** The example rows are posted by the test account "NC Test Owner", made a member of Test Community for that purpose, and carry `is_example = true` (new column on `rides`, `favors` and `town_hall_posts`). Only platform admins can set the flag (a definer RPC or a column grant), so no member can mark their own request as an example.
- **Content.** Six to ten requests that read like real neighbor asks, between public places only (a library, a market, a park, a transit station), never a street address; two or three Town Hall posts (a pinned welcome announcement that says what the community is for, a question with an answer, a thank-you); a couple of answered Q&A entries on a request so the Q&A pattern is visible. Nothing names a real person. Areas are computed like any other request.
- **Always current.** A scheduled server function (`refresh_example_requests()`, run daily by pg_cron, which the project has) moves each example request's time forward so it always falls in the coming seven days, keeps its status open, and re-opens any example that was completed or cancelled. `expire_past_open_requests` and the client's 12-hour visibility rule skip `is_example` rows. The new-request notification trigger skips them too, so refreshing them never pushes to Test Community's members.
- **What you can do with one.** Open it, read its area, read and ask questions (the test account never answers, so each example's seeded answers stay the model). Offer to help or claim is refused with a plain message ("This is an example request. Real requests in your community work the same way."), so no real person is ever connected to the test account. Cards and the detail screen carry an "Example" chip.
- **Guests** see them through the guest views as today; signed-in members of Test Community see them in the merged feed with the chip and can exclude Test Community with the filter.
- **Removal.** If Test Community ever gets real neighbors, platform admins hide the examples; the flag makes them easy to find.

**Builder's call:** the refresh function's exact schedule and the client's handling of `is_example` in the SwiftData trio and the filter manager (the chip, the exemption from the 12-hour rule, the refused offer).

### 4.12 Merging two communities

Two owners who agree can make their communities one. "It might even be worth going so far as to allowing owners of groups to merge their groups if they mutually agree." **Orchestrator's calls**, the owner may overrule:

- **Who and how.** The owner of community A opens Manage → "Merge with another community", searches for B by name (listed or not, if they know the name; a hidden community can be found this way only by its exact name) and proposes: "Merge A into B" or "Merge B into A", with a note. The owner of B gets a push and a bell row (an `announcement` row addressed to that owner, with `community_id`; no new notification type) and sees the proposal under Manage with Accept and Decline. A proposal expires after 7 days; one pending proposal per community at a time; either owner can withdraw. Platform admins see proposals and merges in Admin → Communities.
- **What the merge does**, in one server transaction (`merge_communities`, SECURITY DEFINER, run by the accepting owner's RPC): the surviving community keeps its name, settings and area; the merged community's owner joins it as an owner too (the two are co-owners), its admins as admins. Every active member of the merged community becomes an active member of the survivor; its owner becomes an owner and its admins become admins of the survivor (the survivor's owners can change that afterwards); someone already in both keeps their higher role. Posts and comments of a person who had been removed from the survivor arrive hidden (restorable by a platform admin); their requests are withdrawn. Pending join requests, open and in-progress requests (with their offers, Q&A and reminders), Town Hall posts and comments, invites and reports move to the survivor; completed history moves too, so stats and leaderboards follow people. Muted-community settings carry over. The merged community is archived with a notice saying where its members now are, and its invite codes stop working. Conversations are not community-scoped and are untouched.
- **Rules.** Both communities must be unarchived; the survivor's owner limit is unaffected (the merged community leaves the proposer's count); if the two have different join policies, the survivor's applies to everyone from then on and both owners see that in the confirmation ("Members of B will follow A's rules: Ask to join, areas until a claim"). A merge between an open community and an approval or invite community shows an extra warning, because it changes who can see whom. The merge is irreversible; both confirmations say so.
- **Who is told.** Every active member of both communities gets one `announcement` bell row with push ("A and B are now one community: <survivor>"), sent as a system announcement through the existing broadcast path, not counted against the owners' daily announcement limit.
- **Release.** Ships with Release 2 (discovery), after the nearby check, since the two answer the same problem. **Builder's call:** the exact table for proposals (for example `community_merge_proposals`), the role mapping details, and what the Requests filter does when a chosen community disappears (recommended: it is replaced by the survivor).

## 5. Left to the builder, and open questions

**Builder's calls:** each one marked above, plus RPC and column names (the ones here are proposals); new `forceFullRefreshAndWait` triggers after offer actions (for example `.dashboard` and `.badges` with "offerDecision"), added to CLAUDE.md's sanctioned list; the CLAUDE.md, SECURITY.md, legal and App Privacy updates each release needs; probes and fixture tests for every seam touched.

**Answered by the owner on 2026-10-21:** the default Seattle community is renamed "Test Community", stays listed, and holds example content for new users to explore; its old member content is hidden, and permanent deletion is the owner's script (4.10, 4.11). The owner also asked, the same day, for search by name, "Use my location" and community merging in this pass (2, 4.2, 4.12) and approved the orchestrator's calls below as written.

**Settled by the orchestrator (overrule if wrong):** hidden communities keep approval or invite (4.1); no phones anywhere (4.6); a 24-hour cool-off (4.8); the example-content mechanism and the `is_test` flag (4.10, 4.11); a request keeps the rule it was posted under (4.1); only the owner changes the two switches and the area (4.1); community admins see areas (4.4); no offer timeout and a declined helper cannot re-offer on that request (4.5); the push behaviours (4.9).

## 6. Glossary

- **Listed:** appears in Explore search and to guests; has a service area.
- **Hidden:** never in search or guest views; joined only by code or link; approval or invite, never open.
- **Open:** anyone signed in joins at once; offers instead of claims; no messaging reach; a 24-hour cool-off.
- **Ask to join:** an admin approves each person; claims confirm at once.
- **Invite only:** a code or link admits at once; claims confirm at once.
- **Area:** a place name and rough circle standing in for an address, computed on the server; never a pin.
- **Connection:** the accepted offer (open) or the claim (approval, invite) that lets one helper see a request's addresses until it ends.
- **Offer:** a helper's request to help in an open community, with an optional note; the poster accepts or declines.
- **Helping:** the tile, formerly Claimed, listing what you help with and your pending offers.
