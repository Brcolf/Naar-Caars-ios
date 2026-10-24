# Naar's Cars: multi-community and native Android roadmap

> Date: 2026-10-07
> Status: **Proposed.** Nothing here is approved, applied to Supabase, built or scheduled. The two design specs carry the detail; this document is the map, the sequencing and the short decision list.
> Specs: [`Docs/superpowers/specs/2026-10-07-multi-community-design.md`](../superpowers/specs/2026-10-07-multi-community-design.md) and [`Docs/superpowers/specs/2026-10-07-android-parity-design.md`](../superpowers/specs/2026-10-07-android-parity-design.md). Evidence: the research maps, kept outside the repository (see [`research/README.md`](research/README.md)).
> Public-repository note: the specs describe defects that were still open on the live backend when they were written; the owner chose to publish them without the research maps.

## 1. What was asked

1. **Multi-community.** A person creates their own neighborhood, invites people into a private group, and rides and favors stay inside that group. A person may belong to several groups; the app decides where a post goes; Town Hall, stats and leaderboards are per group.
2. **Native Android with parity.** A second native codebase maintained with AI agents, sharing the Supabase backend, with a development environment that mirrors work across the two platforms and tests the mirror for function and completeness.

## 2. The starting point

The app is a single community in every layer, and the assumption lives in the backend, not the client.

- Membership is `profiles.approved = true and is_banned = false`, read through `is_active_user()` in nine policies and directly in fourteen more.
- "Everyone" is defined by five fan-out loops over approved profiles: new ride, new favor, new Town Hall post, admin broadcast, and the admin alerts for applicants and reports.
- Every statistic, leaderboard and spotlight is global, and the XP ledger has no scope column.
- Guests read through two views and several anonymous policies that expose all content.
- Admin is one global flag.

The backend is also the only layer the two apps will share, and it is the layer that has drifted most. A live function body exists in no migration file. The push edge function reads a badge key the RPC never returns. Town Hall pushes carry a key the client looks for under another name. One array parameter is sent in two encodings. A port written from the Swift code would copy each of these; a port written from a tested contract surfaces them. That observation shaped the Android recommendation.

## 3. Multi-community: the recommendation

Add three tables (`communities`, `community_members` with roles and statuses, `community_invites` with redemptions) and one `community_id` column on rides, favors, Town Hall posts and XP events, plus a derived, nullable one on notifications and reports. Every "everyone" predicate becomes a membership predicate evaluated once per statement through caller-bound helper functions, so Row Level Security enforces isolation from the first server-side migration and no client filter is ever the boundary. The existing group becomes the default community, with every current member and every existing row back-filled into it.

The installed App Store build keeps working through the whole rollout. Its three legacy writes (submit application, admin approve, admin reject) are bridged to memberships in the default community by state-based triggers, and the two profile flags the app routes on become maintained mirrors of membership.

What a person sees:

- **Requests is one merged feed** across their communities, with a community chip on each card. The chip is hidden while they belong to one community.
- **Town Hall and the leaderboard are per community**, behind a title menu on the Community tab.
- **Messages, the bell and Profile are per person.** Reputation (rating, fulfilled count, XP, badges) travels with the person; leaderboards do not.
- **The create forms ask "Post to"** only when the person belongs to more than one community, and the button names the destination.
- **Joining** is by invite code, by request to a public community, or by creating one. Each community has its own owner and admins who approve, remove and moderate; platform admins keep full reach as the moderator of last resort.

A current member sees an app identical to today except for one new Profile row.

| Phase | What ships | A member notices |
|---|---|---|
| 0 | Server only: tables, back-fill, isolation policies, fan-out, bridges, new RPCs | Nothing. No app update needed |
| 1 | iOS: community-aware reads, hardening, the hidden switchers | Nothing |
| 2 | iOS: create, invite, join, approve, mute, report a community; legal documents | The first second community can exist |
| 3 | Community admin and moderation screens | Owners and admins get their tools |
| 4 | Broadcast push, invite links, polish | Invite links open the app |
| 5 | Retire the bridges and the dead invite code; private storage | Old builds must update |

## 4. Native Android: the recommendation

Build Android as a one-to-one architectural twin of the iOS app in Kotlin and Jetpack Compose, with **no shared client code**. Kotlin Multiplatform, React Native and Flutter were each evaluated on their merits and rejected for this app. The hardened part of the iOS app (the SwiftData write actor, the refresh coordinator, the durable send queue, the main-actor realtime callbacks, the Keychain session) is exactly what a shared core would have to replace on a live App Store app, for no benefit to iOS users. The spec records the reasoning so the question stays closed unless a web client lands on the roadmap.

Share three things instead, all checkable by machine:

- **The backend**, already shared.
- **A `shared/` contract directory** in the same repository: a generated snapshot of the live schema, one JSON contract per client-callable RPC (there are 42), JSON fixtures for push types, table rows and realtime event sequences, the notification type registry, the behavioural constants, the string catalog exported to Android resources, the design tokens, feature specs with numbered rules, Maestro scenarios that run unchanged on both simulators, test ids with their accessibility labels, and a parity ledger that CI reads.
- **A seeded Supabase stack** built from a one-time schema dump of production, because the migration history in this repository cannot be replayed. The production-pointing webhook function is replaced before any seeded row is inserted, and a probe refuses to seed without that override.

How parity is enforced, which is the part of the request that tooling can answer:

- **Contract first.** A feature starts as a spec plus a contract change in its own PR, proven on the throwaway stack before an agent applies it to production. Client PRs cannot reference an RPC, column or push key the contract does not have.
- **A ledger gate that cannot be satisfied by a label.** A feature counts as shipped on a platform only when its scenarios passed there. Once a feature is shipped on both, a change to one side must come with a change to the other or with a recorded divergence. Every source file is owned by a feature, so logic cannot sit outside the gate.
- **A symmetric port agent and an advisory parity reviewer.** Either platform can be the source. The reviewer writes one line per spec rule with code anchors on both platforms. Mechanical checks gate; the model advises; the owner merges.
- **Paired release trains** with a dated two-device manual pass on a real iPhone and a real Android phone.
- **iOS is hardened before it is copied.** The send path and the realtime manager have no tests today. They get them, and the message insert is made idempotent, before any Android messaging code is written.

The harness phases pay off for the iOS-only project on their own. The port follows the iOS build order and ships messaging last, in two sub-phases.

## 5. Sequencing: the one decision that shapes everything

The two initiatives pull against each other. Porting a moving target costs twice. Delaying the product change for the length of the port costs most of a year.

| Ordering | Sequence | A second community can exist on iOS after | Android in production after, one agent lane / two |
|---|---|---|---|
| **A. Communities first** | harness phases 0 to 2, then the community server phase and its first two iOS phases, then the Android port of the community-aware app | about 2.5 months | about 10.5 months / about 6.5 to 7 months |
| B. Android first | harness, then the full port of today's app, then communities on both platforms through the mirror workflow | about 10.5 months / about 7 months | about 9 months / about 6 to 6.5 months |

**Recommendation: ordering A.** The community server phase is a no-op for the single existing community, so it can be proven on the throwaway stack early. Android then arrives about six weeks later on one lane and never has to re-port a dashboard. Both specs now recommend this order.

Either way the first three harness phases come first. They are the test hardening the audit notes keep asking for, and they protect every later migration.

## 6. Effort

An agent-day is one focused Claude Code session producing merged, verified work. Owner hours are hands-on steps only the owner can take (dashboards, Xcode project steps, real-device passes, store forms) plus reading verification reports and deciding.

| Workstream | Agent-days | Owner hours |
|---|---|---|
| Multi-community, backend and iOS | 27 to 33, plus 3 for private storage | 33 to 42 |
| Native Android with parity, including the harness | 175 to 210 | 110 to 150 |
| Shared work counted once | minus 2 | minus 2 |
| The Android twin of the community screens | plus 10 to 18 | plus 8 to 12 |
| **Both** | **about 210 to 260** | **about 150 to 200** |

The Android figure rose from 127 to about 190 during review. The first estimate priced messaging at half the design's own rate for fragile files and left out the release path. Steady state after the port: a feature's mirror costs about two thirds of its source implementation, plus one contract PR and about half an hour of the owner's time.

## 7. Decisions for the owner

The multi-community spec has 28 numbered decisions and the Android spec has 60, each with options and a recommendation. Most have a default an agent can take. These are the ones that change what gets built or when.

**Sequencing**

1. Ordering A or B (section 5).
2. Whether a web client is on the twelve-month roadmap. "Yes" is the only answer that reopens the unified-stack question.

**The shape of communities**

3. Approval model: per-community membership approval with open account creation (recommended), or keep a global account gate.
4. Requests: one merged feed with an optional narrow (recommended), or one active community that switches every tab.
5. Guest browsing: public communities only, with the existing group public so the flow Apple reviewed is unchanged (recommended).
6. Messaging reach: anyone who shares a community with you (recommended). A member of two communities can then put people from both in one group thread.
7. Oversight of new communities: open creation with limits, a notice to platform admins and one-tap archive (recommended), or hold each new community for review.
8. A community whose only owner deletes their account: hand it to an admin, else keep it open for a member to take over (recommended), else archive.
9. Private storage: accept that image URLs from the first private communities are readable by anyone who has the link, and close it in the last phase (recommended), or block the first second community on it.
10. The word: "community" (recommended, the tab already says it), "neighborhood" or "group".

**Android**

11. Sign-in on Android: email plus Google plus Apple through the web (recommended), or email plus Google. Two members have Apple as their only sign-in method. Apple over the web needs an Apple Services ID and a client secret the owner regenerates every six months.
12. Play developer account type. A new personal account must run a closed test with at least twelve outside testers for fourteen days before production; an organization account does not.
13. A domain and static hosting. `naarscars.com` is referenced in the code and does not resolve. The Play account-deletion page needs a host when closed testing starts, and invite links need one later.
14. Fix the message duplication on iOS before Android messaging is written (recommended), and pick which small iOS fixes land first so the twin starts identical.
15. One hosted staging project for the iOS scenario lane (recommended and required for that lane; the macOS CI runners cannot host the containers).
16. Minimum Android version: 12 (recommended, no second code path for the lock, the blur and authenticated notification actions) or 10.
17. Launch scope: full parity including the admin panel (recommended), or member-facing parity first.

**Environment**

18. Monorepo with the Xcode project left in place and `android/` plus `shared/` beside it (recommended), and a repository rename.
19. Split the operating manual: a short root `CLAUDE.md`, the iOS manual under `NaarsCars/`, an Android manual under `android/`.

## 8. Found along the way, independent of the roadmap

These came out of the mapping and review. Each stands on its own and none needs a roadmap decision.

- **Sign-in credentials are committed in the UI test file** (`NaarsCars/NaarsCarsUITests/NaarsCarsUITests.swift`) and are on `main` in a public repository. Rotating those passwords is the fix; removing the lines does not clear git history.
- **`CLAUDE.md` describes the message send path as manager, then worker, then service.** The code sends inline from `MessageSendManager`; `MessageSendWorker` is a recovery drain started with the session. The manual should say what the code does.
- **A retried message can appear twice.** The insert uses a fresh id per attempt, and the drain can pick up a row whose inline send is still in flight. The second route is read from the code, not reproduced. One fix closes both.
- **The message push still reaches a member who left a conversation.** The edge function's recipient query does not filter on `left_at`.
- **The app-icon badge number set by a push can differ from the number the app shows**, because the RPC does not return the `total` key the edge function reads.
- **`naarscars.com` does not resolve**, and it is the app's deep-link base constant.

## 9. How this proposal was produced and what was verified

- The live database was queried for tables, policies, functions, triggers, views and row counts. Six mapping agents then wrote inventories of the backend, the client data layer, the UI and navigation, auth and admin, notifications and push, and tooling and tests, citing files and lines. They are kept outside the repository; [`research/README.md`](research/README.md) says what they were.
- Seven independent designs were written from different angles: three for communities (minimal diff, data-model purity, product first) and four for Android (two native codebases, a Kotlin Multiplatform core, a contract-first parity harness, and a devil's advocate for a unified stack). Three judges per initiative scored them and named fatal flaws. One synthesis per initiative took the winner and grafted in the best ideas from the rest.
- Twelve adversarial reviewers produced 109 findings. The 38 rated high or critical were to go to a three-vote refutation panel; a cap on the panel left six Android findings without a vote, and those were taken as real. Of the 32 voted on, 28 were confirmed and 4 rejected. Every confirmed finding and every medium or low finding is folded into the specs. Section 10 of each spec has one line per finding, including the rejected ones and the reason.
- Checked by hand against the live backend and the code, beyond what the agents reported: the admin-field guard runs with invoker rights and passes when there is no end-user session, which is what lets maintenance writes through today; the notification gate function is platform-admin-only for applicant and report alerts; both leaderboard RPCs already default both parameters, so a community-scoped variant needs a new name; `MessageSendManager` calls the service directly; two accounts are Apple-only and two more have both Apple and email; the domain does not resolve; the UI test file holds credentials.

**Not verified.** Nothing was built, no migration was applied and no probe was run. Every DDL sketch, policy predicate and trigger in the specs is a design to be proven on the throwaway stack before it touches production. Android platform and Play policy statements could not be checked from this machine and are marked as such in the spec.

## 10. What the review changed

The first drafts were sound on isolation and backward compatibility and wrong at the edges. The corrections that matter most:

- **The server phase would have broken the live app between two of its steps.** A column was made NOT NULL before the triggers that fill it were edited, so every ride, favor, completion and review insert would have failed. NOT NULL is now the last step, and a short probe runs after every step.
- **The old admin build's Reject could have deleted an applicant to another community.** It now acts only on applicants to the default community and refuses everyone else with an error the installed build already displays. Community admins can never delete an account.
- **Community owners would never have received applicant alerts.** The notification gate is platform-admin-only; it is widened in the server phase, and the approve screen moves forward to the first build on which a second community can exist.
- **Reputation would have changed depending on who was looking.** Rating and fulfilled count now come from one RPC.
- **Community admins would have seen who reported them.** They get a reduced report view with no reporter and no reports about themselves.
- **The Android realtime and send-queue mappings named Kotlin look-alikes without checking what they do.** The Kotlin realtime flow drops events that arrive before a collector is attached, and WorkManager cannot run a one-second retry loop. Both rows are rewritten by mechanism.
- **The parity gate keyed on a self-declared status.** It now requires a diff on both platforms or a recorded divergence, and "shipped" is derived from scenario results.
- **The cross-platform scenarios could not run in CI as written.** Each is now two per-platform halves with the other party played by an API actor, plus a dated two-device manual pass per release.

## 11. Next steps

1. The owner reads the two specs and answers the decisions in section 7. This is the back-and-forth the request asked for; one decision at a time is fine.
2. With the decisions taken, each spec becomes an implementation plan in its own session. The harness phases 0 to 2 come first under either ordering.
3. The first implementation session exports the live function bodies and takes the baseline schema dump, because every later migration is proven on the seeded stack before an agent applies it to production.
